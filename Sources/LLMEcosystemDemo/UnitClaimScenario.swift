import Foundation
import ProviderGatewayKit
import TokenMeterKit
import UnitClaimKit

/// The identifier the ninety-ninth scenario's turns bill against.
extension ProviderIdentifier {
    static let unitClaimHost = ProviderIdentifier("unit-claim-host")
}

extension EcosystemDemo {
    /// The ninety-ninth scenario: unit conversions an answer makes on its own.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer converts
    /// an American recipe for a metric kitchen and weighs two cups of flour as if they were water;
    /// `UnitClaimKit` names the slip, notes that 250 ml holds only for a metric cup, and its feedback gets a
    /// rewrite that holds. The follow-up converts a 10°C rise as if it were a reading (50°F instead of
    /// 18°F); asked again, the model repeats it, and the one `ConversionLedger` for the conversation marks
    /// the repeat, so the app stops re-asking and shows the note instead.
    static func runUnitClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .unitClaimHost, script: unitClaimScript)
            ])
            let ledger = ConversionLedger()
            let question = "My American recipe says 2 cups of flour, 1 cup of milk and an oven at 350°F. "
                + "What is that in grams, millilitres and Celsius?"
            print("[unit claim scenario] user: \(question)")
            let first = try await unitTurn(question, router: router, meter: meter)
            print("[unit claim scenario] answer 1: \(first)")
            let report = await ledger.review(first)
            printUnitFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await unitTurn(repair, router: router, meter: meter)
            print("[unit claim scenario] answer 2 (after the feedback): \(second)")
            let fixed = await ledger.review(second)
            print("[unit claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "The forecast says tomorrow will be 10°C warmer than today. How much is that in Fahrenheit?"
            print("[unit claim scenario] user: \(followUp)")
            let third = try await unitTurn(followUp, router: router, meter: meter)
            print("[unit claim scenario] answer 3: \(third)")
            let rise = await ledger.review(third)
            printUnitFindings(rise)

            let retry = followUp + "\n" + third + "\n" + (rise.feedback ?? "")
            let fourth = try await unitTurn(retry, router: router, meter: meter)
            print("[unit claim scenario] answer 4 (after the feedback): \(fourth)")
            let again = await ledger.review(fourth)
            printUnitFindings(again)
            if again.repeatedCount > 0 {
                print("[unit claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[unit claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.conversions) conversions, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[unit claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[unit claim scenario] FAILED: \(error)")
        }
    }

    private static func printUnitFindings(_ report: ConversionReport) {
        for finding in report.findings {
            print("[unit claim scenario]   \(finding.severity): \(finding.claim.excerpt) -> " + finding.explanation)
        }
        print("[unit claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let unitClaimScript = [
        "Use 2 cups of flour (500 g) and 1 cup of milk (250 ml), and bake at 350°F (175°C).",
        "Use 2 cups of flour (250 g) and 1 cup of milk (240 ml), and bake at 350°F (175°C).",
        "Tomorrow will be 10°C (50°F) warmer than today.",
        "Checked again: tomorrow will be 10°C (50°F) warmer than today."
    ]

    private static func unitTurn(
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
