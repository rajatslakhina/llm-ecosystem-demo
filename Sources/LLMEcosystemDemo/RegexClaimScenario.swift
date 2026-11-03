import Foundation
import ProviderGatewayKit
import RegexClaimKit
import TokenMeterKit

/// The identifier the hundredth scenario's turns bill against.
extension ProviderIdentifier {
    static let regexClaimHost = ProviderIdentifier("regex-claim-host")
}

extension EcosystemDemo {
    /// The hundredth scenario: the regular expressions an answer gives, and what it says they match.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer gives a ZIP
    /// code regex with no anchors and says it rejects `123456`; `RegexClaimKit` runs every example and the
    /// commented line of code, finds that the pattern matches inside longer input, and names the slip. Its
    /// feedback gets an anchored rewrite that holds. The follow-up strips dashes with `replace(/-/, "")` and
    /// claims every dash is gone; asked again, the model repeats it, and the one `RegexLedger` for the
    /// conversation marks the repeat, so the app stops re-asking and shows the note instead.
    static func runRegexClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .regexClaimHost, script: regexClaimScript)
            ])
            let ledger = RegexLedger()
            let question = "Give me a JavaScript regex that validates a US ZIP code (12345 or 12345-6789), "
                + "with examples."
            print("[regex claim scenario] user: \(question)")
            let first = try await regexTurn(question, router: router, meter: meter)
            print("[regex claim scenario] answer 1: \(oneLine(first))")
            let report = await ledger.review(first)
            printRegexFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await regexTurn(repair, router: router, meter: meter)
            print("[regex claim scenario] answer 2 (after the feedback): \(oneLine(second))")
            let fixed = await ledger.review(second)
            print("[regex claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "How do I turn 2026-11-03 into 20261103 in JavaScript?"
            print("[regex claim scenario] user: \(followUp)")
            let third = try await regexTurn(followUp, router: router, meter: meter)
            print("[regex claim scenario] answer 3: \(oneLine(third))")
            let dashes = await ledger.review(third)
            printRegexFindings(dashes)

            let retry = followUp + "\n" + third + "\n" + (dashes.feedback ?? "")
            let fourth = try await regexTurn(retry, router: router, meter: meter)
            print("[regex claim scenario] answer 4 (after the feedback): \(oneLine(fourth))")
            let again = await ledger.review(fourth)
            printRegexFindings(again)
            if again.repeatedCount > 0 {
                print("[regex claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[regex claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[regex claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[regex claim scenario] FAILED: \(error)")
        }
    }

    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printRegexFindings(_ report: RegexReport) {
        for finding in report.findings {
            let subject = finding.claim?.subject ?? finding.pattern.description
            print("[regex claim scenario]   \(finding.severity): \(subject) -> " + finding.explanation)
        }
        print("[regex claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let regexClaimScript = [
        """
        Use `/\\d{5}(-\\d{4})?/`. It matches `12345` and `12345-6789` but not `1234` or `123456`.
        ```js
        /\\d{5}(-\\d{4})?/.test("12345-678") // false
        ```
        """,
        """
        Use `/^\\d{5}(-\\d{4})?$/`. It matches `12345` and `12345-6789` but not `1234` or `123456`.
        ```js
        /^\\d{5}(-\\d{4})?$/.test("12345-678") // false
        ```
        """,
        """
        ```js
        "2026-11-03".replace(/-/, "") // "20261103"
        ```
        """,
        """
        Checked again:
        ```js
        "2026-11-03".replace(/-/, "") // "20261103"
        ```
        """
    ]

    private static func regexTurn(
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
