import ArithmeticClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the ninety-eighth scenario's turns bill against.
extension ProviderIdentifier {
    static let arithmeticClaimHost = ProviderIdentifier("arithmetic-claim-host")
}

extension EcosystemDemo {
    /// The ninety-eighth scenario: arithmetic an answer works out on its own.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer takes
    /// 15% of $480 as $62; `ArithmeticClaimKit` recomputes it as $72, and its feedback gets a rewrite whose
    /// every step holds. The follow-up calls $480 to $540 a 15% increase (it is 12.5%); asked again, the
    /// model repeats it, and the one `ArithmeticLedger` for the conversation marks the repeat, so the app
    /// stops re-asking and shows the note instead.
    static func runArithmeticClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .arithmeticClaimHost, script: arithmeticClaimScript)
            ])
            let ledger = ArithmeticLedger()
            let question = "Our plan costs $480 a year. With a 15% discount, what do we pay per month?"
            print("[arithmetic claim scenario] user: \(question)")
            let first = try await arithmeticTurn(question, router: router, meter: meter)
            print("[arithmetic claim scenario] answer 1: \(first)")
            let report = await ledger.review(first)
            printArithmeticFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await arithmeticTurn(repair, router: router, meter: meter)
            print("[arithmetic claim scenario] answer 2 (after the feedback): \(second)")
            let fixed = await ledger.review(second)
            print("[arithmetic claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); "
                + "the app shows answer 2")

            let followUp = "Next year the list price goes from $480 to $540. How big a rise is that?"
            print("[arithmetic claim scenario] user: \(followUp)")
            let third = try await arithmeticTurn(followUp, router: router, meter: meter)
            print("[arithmetic claim scenario] answer 3: \(third)")
            let rise = await ledger.review(third)
            printArithmeticFindings(rise)

            let retry = followUp + "\n" + third + "\n" + (rise.feedback ?? "")
            let fourth = try await arithmeticTurn(retry, router: router, meter: meter)
            print("[arithmetic claim scenario] answer 4 (after the feedback): \(fourth)")
            let again = await ledger.review(fourth)
            printArithmeticFindings(again)
            if again.repeatedCount > 0 {
                print("[arithmetic claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[arithmetic claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.results) results, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[arithmetic claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[arithmetic claim scenario] FAILED: \(error)")
        }
    }

    private static func printArithmeticFindings(_ report: ArithmeticReport) {
        for finding in report.findings {
            print("[arithmetic claim scenario]   \(finding.severity): \(finding.claim.excerpt) -> "
                + finding.explanation)
        }
        print("[arithmetic claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let arithmeticClaimScript = [
        "15% of $480 is $62, so the year costs $480 - $62 = $418, which is $418 / 12 = $34.83 a month.",
        "15% of $480 is $72, so the year costs $480 - $72 = $408, which is $408 / 12 = $34 a month.",
        "From $480 to $540 is a 15% increase, or $540 / 12 = $45 a month.",
        "Checked again: from $480 to $540 is a 15% increase, so plan for $45 a month."
    ]

    private static func arithmeticTurn(
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
