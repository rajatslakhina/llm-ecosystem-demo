import Foundation
import InstructionComplianceKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the ninety-fourth scenario's turns bill against.
extension ProviderIdentifier {
    static let instructionComplianceHost = ProviderIdentifier("instruction-compliance-host")
}

extension EcosystemDemo {
    /// The ninety-fourth scenario: the instructions in a request, kept.
    ///
    /// `InstructionComplianceKit` reads what the user asked the answer to look like: a word limit and a
    /// closing question that hold "from now on", plus three to five bullets without the word "synergy"
    /// for this turn. `ProviderGatewayKit` carries the turn and `TokenMeterKit` meters it. The first answer
    /// breaks three of the instructions; the report's feedback goes back to the model and the rewrite keeps
    /// all of them. The next request contradicts itself, so it is turned back before any provider call is
    /// paid for. A later turn carries the standing instructions without the user repeating them.
    static func runInstructionComplianceScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .instructionComplianceHost, script: instructionComplianceScript)
            ])
            let session = ComplianceSession()
            let request = "From now on, keep every answer under 60 words and end with a question. "
                + "Summarize the outage as 3 to 5 bullet points, and don't use the word \"synergy\"."
            let plan = await session.begin(request: request)
            print("[instruction compliance scenario] user: \(request)")
            print("[instruction compliance scenario] instructions: "
                + plan.directives.map { $0.summary + ($0.scope == .standing ? " (standing)" : "") }
                    .joined(separator: ", "))

            let first = try await instructionComplianceTurn(request, router: router, meter: meter)
            let report = await session.review(answer: first)
            print("[instruction compliance scenario] answer 1: \(first.replacingOccurrences(of: "\n", with: " / "))")
            print("[instruction compliance scenario] verdict \(report.verdict.rawValue): "
                + report.violated.map { "\($0.directive.summary) (\($0.observed))" }.joined(separator: "; "))

            let repair = request + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await instructionComplianceTurn(repair, router: router, meter: meter)
            let fixed = await session.review(answer: second)
            print("[instruction compliance scenario] answer 2 (after the feedback): "
                + second.replacingOccurrences(of: "\n", with: " / "))
            print("[instruction compliance scenario] verdict \(fixed.verdict.rawValue), strict "
                + "\(Int((fixed.strictAccuracy ?? 0) * 100))%; the app shows answer 2")

            let contradictory = "Explain the root cause in at most 2 sentences, across at least 3 paragraphs."
            let blocked = await session.begin(request: contradictory)
            print("[instruction compliance scenario] user: \(contradictory)")
            for conflict in blocked.conflicts {
                print("[instruction compliance scenario] not sent: \(conflict.reason); the app asks which one")
            }

            let followUp = "What should we change first?"
            let carried = await session.begin(request: followUp)
            let third = try await instructionComplianceTurn(followUp, router: router, meter: meter)
            let kept = await session.review(answer: third)
            print("[instruction compliance scenario] user: \(followUp) (in force without repeating them: "
                + carried.carried.map(\.summary).joined(separator: ", ") + ")")
            print("[instruction compliance scenario] answer 3: \(third)")
            print("[instruction compliance scenario] verdict \(kept.verdict.rawValue)")
            let totals = await session.totals
            print("[instruction compliance scenario] session: \(totals.turns) turns, \(totals.checked) checks, "
                + "\(totals.met) met, \(totals.violated) violated, \(totals.conflictedTurns) turned back")
            print("[instruction compliance scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[instruction compliance scenario] FAILED: \(error)")
        }
    }

    private static let instructionComplianceScript = [
        """
        - The cache tier stopped answering at 09:12 after a config push.
        - Failover took 14 minutes because its health check was off.
        - The on-call team showed great synergy.
        - The push was reverted.
        - The health check is back on.
        - A review is booked for Friday.
        """,
        """
        - The cache tier stopped answering at 09:12 after a config push.
        - Failover took 14 minutes because its health check was off.
        - The push is reverted and the check is back on.
        Should config pushes wait for a passing health check?
        """,
        "Make the health check a required gate in the deploy pipeline, so a push cannot ship while it is off. "
            + "Want me to draft the pipeline change?"
    ]

    private static func instructionComplianceTurn(
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
