import Foundation
import LoopGuardKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the seventy-sixth scenario's routed hops bill against.
extension ProviderIdentifier {
    static let loopGuardHost = ProviderIdentifier("loop-guard-host")
}

/// The single tool call the scripted model emits each turn.
private struct ScriptedLoopCall: Decodable {
    let tool: String
    let arguments: [String: String]
}

extension EcosystemDemo {
    /// The seventy-sixth scenario: `AgentLoopKit` (scenario 6) stops a stuck agent only at
    /// `maxSteps`, after every remaining turn has been billed. Here a routed agent keeps asking
    /// `ToolRegistryKit`'s `search` tool the same question and getting the same empty answer.
    /// `LoopGuardKit` nudges it on turn 3 and halts it on turn 4 of an 8-turn cap, and
    /// `TokenMeterKit` shows what the halt saved.
    static func runLoopGuardScenario(meter: TokenMeter) async {
        let providerID = ProviderIdentifier.loopGuardHost
        let maxTurns = 8
        let reply = #"{"tool": "search", "arguments": {"q": "swift 7 release date"}}"#
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: Array(repeating: reply, count: maxTurns))
        ])
        let registry = await loopGuardRegistry()
        let guardian = LoopGuard()
        let prompt = "When is Swift 7 released? Use the search tool."
        var billedTurns = 0
        do {
            for turn in 1...maxTurns {
                let response = try await LLMSession(router: router).send(prompt)
                await meter.record(
                    TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
                    for: providerID.rawValue
                )
                billedTurns = turn
                let call = try JSONDecoder().decode(ScriptedLoopCall.self, from: Data(response.text.utf8))
                let arguments = try JSONEncoder().encode(call.arguments)
                let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
                    id: "t\(turn)", toolName: call.tool, argumentsJSON: arguments
                ))
                let verdict = await guardian.record(LoopGuardKit.ToolStep(
                    toolName: call.tool,
                    arguments: String(bytes: arguments, encoding: .utf8) ?? "{}",
                    observation: "\(result.outcome)"
                ))
                print("[loop guard scenario] turn \(turn) \(call.tool)(q: swift 7 release date) -> " +
                    describeLoopVerdict(verdict))
                if case .halt = verdict { break }
            }
            print("   halted after \(billedTurns) of \(maxTurns) billed turns; " +
                "\(maxTurns - billedTurns) turns a maxSteps cap alone would have paid for were never sent")
        } catch {
            print("[loop guard scenario] FAILED: \(error)")
        }
    }

    private static func loopGuardRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "search",
                description: "Demo web search.",
                parameters: JSONSchema.object(properties: ["q": .string(description: "query")], required: ["q"])
            ),
            handler: ClosureToolHandler { _ in .object(["result": .string("No results found.")]) }
        )
        return registry
    }

    private static func describeLoopVerdict(_ verdict: LoopVerdict) -> String {
        switch verdict {
        case .proceed:
            return "proceed"
        case let .nudge(signal, remaining):
            return "NUDGE (\(remaining) left): \(signal.summary)"
        case let .halt(signal):
            return "HALT: \(signal.summary)"
        }
    }
}
