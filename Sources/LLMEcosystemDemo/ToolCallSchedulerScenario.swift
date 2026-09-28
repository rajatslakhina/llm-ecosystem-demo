import Foundation
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolCallSchedulerKit
import ToolRegistryKit

/// The identifier the seventy-fifth scenario's routed hop bills against.
extension ProviderIdentifier {
    static let toolCallSchedulerHost = ProviderIdentifier("tool-call-scheduler-host")
}

/// The shape the scripted model uses to emit several tool calls in one turn.
private struct ScriptedToolBatch: Decodable {
    struct Call: Decodable {
        let id: String
        let tool: String
        let arguments: [String: String]
    }

    let calls: [Call]
}

private struct DispatchFailure: Error, CustomStringConvertible {
    let description: String
}

extension EcosystemDemo {
    /// The seventy-fifth scenario: `ToolRegistryKit` (scenario 5) dispatches one call and
    /// `StreamAggregatorKit` (scenario 16) reassembles a batch, but nothing in the series decided which calls of
    /// one turn may run at the same time. A routed turn emits five tool calls at once;
    /// `ToolCallSchedulerKit` plans them against declared effects, runs them through the registry
    /// three at a time, and hands results back in emission order.
    static func runToolCallSchedulerScenario(meter: TokenMeter) async {
        let providerID = ProviderIdentifier.toolCallSchedulerHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [
                #"{"calls": [{"id": "c1", "tool": "read_file", "arguments": {"path": "notes.md"}}, "# +
                #"{"id": "c2", "tool": "write_file", "arguments": {"path": "notes.md"}}, "# +
                #"{"id": "c3", "tool": "get_weather", "arguments": {"city": "Delhi"}}, "# +
                #"{"id": "c4", "tool": "get_weather", "arguments": {"city": "Pune"}}, "# +
                #"{"id": "c5", "tool": "write_file", "arguments": {"path": "notes.md"}}]}"#
            ])
        ])
        do {
            let prompt = "Update notes.md with today's weather for Delhi and Pune."
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
                for: providerID.rawValue
            )
            let batch = try JSONDecoder().decode(ScriptedToolBatch.self, from: Data(response.text.utf8))
            let calls = batch.calls.map { ScheduledToolCall(id: $0.id, toolName: $0.tool, arguments: $0.arguments) }
            let scheduler = try ToolCallScheduler(catalog: schedulerCatalog(), maxConcurrency: 3)
            let plan = try scheduler.plan(calls)
            print("[tool call scheduler scenario] model emitted \(calls.count) calls in one turn; " +
                "plan: \(plan.waves.map { $0.joined(separator: "+") }.joined(separator: " | ")) " +
                "(\(plan.sequentialRounds) sequential rounds -> critical path \(plan.criticalPathLength))")
            let registry = await schedulerRegistry()
            let report = try await scheduler.execute(calls) { call in
                let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
                    id: call.id, toolName: call.toolName, argumentsJSON: try JSONEncoder().encode(call.arguments)
                ))
                guard case .success(.object(let fields)) = result.outcome,
                      case .string(let text) = fields["result"] else {
                    throw DispatchFailure(description: "\(result.outcome)")
                }
                return text
            }
            for record in report.records {
                print("   \(record.call.id) start #\(record.startOrder.map(String.init) ?? "-") " +
                    "\(describeScheduledOutcome(record.outcome))")
            }
            print("   \(report.succeeded)/\(report.records.count) succeeded, peak concurrency " +
                "\(report.peakConcurrency)/\(report.maxConcurrency); the two notes.md writes never overlapped")
        } catch {
            print("[tool call scheduler scenario] FAILED: \(error)")
        }
    }

    private static func schedulerCatalog() -> ToolEffectCatalog {
        ToolEffectCatalog([
            "read_file": ToolEffectRule(reads: [ResourceSelector("file", instanceArgument: "path")]),
            "write_file": ToolEffectRule(writes: [ResourceSelector("file", instanceArgument: "path")]),
            "get_weather": .pure
        ])
    }

    private static func schedulerRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        let tools: [(name: String, argument: String)] = [
            ("read_file", "path"), ("write_file", "path"), ("get_weather", "city")
        ]
        for (name, argument) in tools {
            await registry.register(
                ToolRegistryKit.ToolDefinition(
                    name: name,
                    description: "Demo \(name) tool.",
                    parameters: JSONSchema.object(
                        properties: [argument: .string(description: argument)], required: [argument]
                    )
                ),
                handler: ClosureToolHandler { arguments in
                    guard case .object(let fields) = arguments,
                          case .string(let value) = fields[argument] ?? .null else {
                        return .object(["error": .string("missing \(argument)")])
                    }
                    return .object(["result": .string("\(name)(\(value))")])
                }
            )
        }
        return registry
    }

    private static func describeScheduledOutcome(_ outcome: ToolCallSchedulerKit.ToolCallOutcome) -> String {
        switch outcome {
        case .succeeded(let output):
            return "ok \(output)"
        case .failed(let message):
            return "FAILED \(message)"
        case .skipped(let blocker):
            return "SKIPPED (blocked by \(blocker))"
        }
    }
}
