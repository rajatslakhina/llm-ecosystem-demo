import Foundation
import NumberBindingKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the ninety-third scenario's turns bill against.
extension ProviderIdentifier {
    static let numberBindingHost = ProviderIdentifier("number-binding-host")
}

extension EcosystemDemo {
    /// The ninety-third scenario: a tool result restated wrong.
    ///
    /// `ToolRegistryKit` runs a real `analytics` tool and `ProviderGatewayKit` carries the model's answer,
    /// metered by `TokenMeterKit`. The answer puts the conversion rate at 6.7% where the tool said 0.057.
    /// `NumberBindingKit` binds every number in the answer to the tool output and the user's message,
    /// calls the rate contradicted, and the app re-prompts with the note; the corrected answer binds in
    /// full, including a growth figure the model computed from the user's Q2 number and the tool's Q3
    /// number. On a follow-up turn with no tool call, the session reports the numbers the model only
    /// carried over from its own earlier answers as echoed, and its projection as unbound.
    static func runNumberBindingScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .numberBindingHost, script: numberBindingScript)
            ])
            let json = try await analyticsOutput()
            let question = "How did Q3 go? Conversion rate, orders, and growth on Q2's 2,300 orders."
            print("[number binding scenario] user: \(question)")
            print("[number binding scenario] tool analytics -> \(json)")
            let session = BindingSession()
            let evidence: [NumberSource] = [.user(question), .tool("analytics", output: json)]
            let prompt = "User: \(question)\nTool analytics returned: \(json)"

            let first = try await numberBindingTurn(prompt, router: router, meter: meter)
            let report = await session.review(answer: first, evidence: evidence)
            print("[number binding scenario] answer 1: \(first)")
            print("[number binding scenario] \(report.summary)")
            print("[number binding scenario] note: \(report.note ?? "-")")

            let repair = prompt + "\nSystem: Restate the answer using only figures the tool or the user gave. "
                + (report.note ?? "")
            let second = try await numberBindingTurn(repair, router: router, meter: meter)
            let fixed = await session.review(answer: second, evidence: evidence)
            print("[number binding scenario] answer 2 (after the note was sent back): \(second)")
            print("[number binding scenario] \(fixed.summary); the app shows answer 2")
            let growth = fixed.figures.first { $0.status == .derived(.percentChange) }
            print("[number binding scenario] 15% is derived from "
                + (growth?.support.map { "\($0.sourceLabel) \($0.figure.text)" }.joined(separator: " and ") ?? "-"))

            let followUp = "What will Q4 look like?"
            let third = try await numberBindingTurn(prompt + "\nUser: " + followUp, router: router, meter: meter)
            let projected = await session.review(answer: third, evidence: [.user(followUp)])
            print("[number binding scenario] follow-up, no tool call: \(third)")
            print("[number binding scenario] \(projected.summary)")
            print("[number binding scenario] note: \(projected.note ?? "-")")
            let totals = await session.totals
            print("[number binding scenario] session: \(totals.turns) answers, \(totals.verified)/\(totals.checked) "
                + "numbers bound, \(totals.contradicted) contradicted, \(totals.unverified) unverified")
            print("[number binding scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[number binding scenario] FAILED: \(error)")
        }
    }

    private static let numberBindingScript = [
        "Q3 conversion rate was 6.7% on 46,404 sessions, with 2,645 orders, up 15% on Q2.",
        "Q3 conversion rate was 5.7% on 46,404 sessions, with 2,645 orders, up 15% on Q2.",
        "If growth holds at 15%, Q4 would land near 3,040 at a 5.7% conversion rate."
    ]

    /// Dispatches the `analytics` tool through `ToolRegistryKit` and returns its output as JSON text.
    private static func analyticsOutput() async throws -> String {
        let registry = ToolRegistryKit.ToolRegistry()
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "analytics",
                description: "Demo store analytics for one quarter.",
                parameters: JSONSchema.object(
                    properties: ["period": .string(description: "quarter")], required: ["period"]
                )
            ),
            handler: ClosureToolHandler { _ in
                .object([
                    "period": .string("Q3"), "sessions": .number(46_404), "orders": .number(2_645),
                    "conversion_rate": .number(0.057)
                ])
            }
        )
        let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
            id: "nb1", toolName: "analytics", argumentsJSON: Data(#"{"period":"Q3"}"#.utf8)
        ))
        guard case let .success(output) = result.outcome else { throw NumberBindingDemoError.toolFailed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(bytes: try encoder.encode(output), encoding: .utf8) ?? "{}"
    }

    private static func numberBindingTurn(
        _ prompt: String,
        router: ProviderRouter,
        meter: TokenMeter
    ) async throws -> String {
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: response.providerID.rawValue
        )
        return response.text
    }
}

private enum NumberBindingDemoError: Error {
    case toolFailed
}
