import Foundation
import OutcomeMonitorKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the eightieth scenario's routed agent turns bill against.
extension ProviderIdentifier {
    static let outcomeMonitorHost = ProviderIdentifier("outcome-monitor-host")
}

private struct ScriptedQuoteCall: Decodable {
    let tool: String
    let arguments: [String: String]
}

extension EcosystemDemo {
    /// The eightieth scenario: `ToolRegistryKit` (scenario 5) validates a tool call's *arguments*,
    /// and `GroundingKit` checks the model's *answer*, but nothing checked the tool's *result*.
    /// Here `get_quote` answers from a stale cache with a negative price. The call is valid, the
    /// result is well-formed JSON, and without a check it reaches the model as fact.
    /// `OutcomeMonitorKit` checks the result against an outcome contract and hands the model the
    /// unchanged result plus a receipt that names the recovery tool, `refresh_quote`.
    ///
    /// The agent's replies are scripted, so turn 2 follows the receipt because the script says so.
    /// What the scenario shows for real is what the model is handed at each step, and that the
    /// recovery tool's result passes a contract mined from known-good quotes.
    static func runOutcomeMonitorScenario(meter: TokenMeter) async {
        let providerID = ProviderIdentifier.outcomeMonitorHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [
                #"{"tool": "get_quote", "arguments": {"sku": "LMP-200"}}"#,
                #"{"tool": "refresh_quote", "arguments": {"sku": "LMP-200"}}"#,
                "LMP-200 costs 41.50 USD (fresh quote from origin)."
            ])
        ])
        let registry = await quoteRegistry()
        var transcript = "What does the LMP-200 lamp cost? Use the quote tools."
        do {
            let monitor = try await quoteMonitor()
            for turn in 1...3 {
                let response = try await LLMSession(router: router).send(transcript)
                await meter.record(
                    TokenUsage(promptTokens: transcript.count / 4, completionTokens: response.text.count / 4),
                    for: providerID.rawValue
                )
                let decoded = try? JSONDecoder().decode(ScriptedQuoteCall.self, from: Data(response.text.utf8))
                guard let call = decoded else {
                    print("   turn \(turn) answer: \(response.text)")
                    break
                }
                let raw = try await dispatchQuote(call, turn: turn, registry: registry)
                let inspection = await monitor.inspect(tool: call.tool, result: raw)
                print("[outcome monitor scenario] turn \(turn) \(call.tool)(sku: LMP-200) -> \(raw)")
                print("   \(describeInspection(inspection))")
                transcript += "\n\nTool \(call.tool) returned:\n" + inspection.annotate(raw)
            }
            let report = await monitor.report()
            print("   monitor: \(report.inspected) results inspected, \(report.violated) violated, " +
                "\(Int((report.monitoredShare * 100).rounded()))% under a contract")
            print("   without the monitor, turn 2 sees only {\"price\": -41.5} with nothing marking it wrong")
        } catch {
            print("[outcome monitor scenario] FAILED: \(error)")
        }
    }

    private static func describeInspection(_ inspection: Inspection) -> String {
        switch inspection {
        case .conforms(let tool):
            return "\(tool): conforms to its contract"
        case .unmonitored(let tool):
            return "\(tool): no contract"
        case .violated(let receipt):
            let broken = receipt.violations.map { "\($0.property) (observed \($0.observed))" }
            return "VIOLATED \(broken.joined(separator: "; ")); receipt names " +
                receipt.recoveryTools.map(\.name).joined(separator: ", ")
        }
    }

    /// A declared contract for `get_quote`, and one mined from three known-good quotes for
    /// `refresh_quote`.
    private static func quoteMonitor() async throws -> OutcomeMonitor {
        let declared = OutcomeContract(
            tool: "get_quote",
            properties: [.kind("price", .number), .range("price", min: 0), .oneOf("currency", ["USD", "EUR"])],
            recoveryTools: [RecoveryTool(name: "refresh_quote", purpose: "re-fetch from origin, bypassing the cache")]
        )
        let mined = try ContractMiner().mine(tool: "refresh_quote", samples: [
            #"{"currency": "USD", "price": 12.0, "sku": "A-1", "source": "origin"}"#,
            #"{"currency": "EUR", "price": 7.25, "sku": "B-2", "source": "origin"}"#,
            #"{"currency": "USD", "price": 99.0, "sku": "C-3", "source": "origin"}"#
        ])
        print("[outcome monitor scenario] refresh_quote contract \(mined.origin): " +
            mined.properties.map(\.name).joined(separator: ", "))
        return OutcomeMonitor(contracts: [declared, mined])
    }

    /// Dispatches through `ToolRegistryKit` and renders the result as sorted-key JSON text,
    /// the form a provider would be handed.
    private static func dispatchQuote(
        _ call: ScriptedQuoteCall,
        turn: Int,
        registry: ToolRegistryKit.ToolRegistry
    ) async throws -> String {
        let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
            id: "q\(turn)", toolName: call.tool, argumentsJSON: try JSONEncoder().encode(call.arguments)
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch result.outcome {
        case .success(let value):
            return String(bytes: try encoder.encode(value), encoding: .utf8) ?? "{}"
        case .failure(let error):
            return "{\"error\": \"\(error)\"}"
        }
    }

    private static func quoteRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        let schema = JSONSchema.object(properties: ["sku": .string(description: "product SKU")], required: ["sku"])
        // The cache holds a quote written by a bad price-feed import: a valid object, a negative price.
        await registry.register(
            ToolRegistryKit.ToolDefinition(name: "get_quote", description: "Cached price quote.", parameters: schema),
            handler: ClosureToolHandler { _ in
                .object(["sku": .string("LMP-200"), "price": .number(-41.5), "currency": .string("USD"),
                         "source": .string("cache")])
            }
        )
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "refresh_quote", description: "Quote from origin.", parameters: schema
            ),
            handler: ClosureToolHandler { _ in
                .object(["sku": .string("LMP-200"), "price": .number(41.5), "currency": .string("USD"),
                         "source": .string("origin")])
            }
        )
        return registry
    }
}
