import Foundation
import ProviderGatewayKit
import TokenMeterKit
import VersionRangeClaimKit

/// The identifier the hundred-and-sixth scenario's turns bill against.
extension ProviderIdentifier {
    static let versionRangeHost = ProviderIdentifier("version-range-host")
}

extension EcosystemDemo {
    /// The hundred-and-sixth scenario: what an answer says about version ranges, checked with each package
    /// manager's own rules.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer adds a 0.x
    /// dependency to `package.json` as `^0.2.3` and says npm will pick up minor updates and 0.3.0.
    /// `VersionRangeClaimKit` reads the range the way node-semver does: on 0.x a caret lets only the patch number
    /// move, so both claims are wrong, and its feedback gets a rewrite that holds. The follow-up writes a
    /// `requirements.txt` with `requests^2.31` (pip has no caret) and says `django~=4.2` allows Django 5.0 (it
    /// stops below 5.0); asked again, the model repeats it, and the conversation's one `RangeLedger` marks the
    /// repeat.
    static func runVersionRangeClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .versionRangeHost, script: versionRangeScript)
            ])
            let ledger = RangeLedger()
            let question = "Add tiny-parser 0.2.3 to package.json so we get its updates. What will npm install?"
            print("[version range scenario] user: \(question)")
            let first = try await rangeTurn(question, router: router, meter: meter)
            print("[version range scenario] answer 1: \(flatRange(first))")
            let report = await ledger.review(first)
            printRangeFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await rangeTurn(repair, router: router, meter: meter)
            print("[version range scenario] answer 2 (after the feedback): \(flatRange(second))")
            let fixed = await ledger.review(second)
            print("[version range scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); "
                + "the app shows answer 2")

            let followUp = "Now pin requests 2.31 and Django 4.2 in requirements.txt, allowing safe updates."
            print("[version range scenario] user: \(followUp)")
            let third = try await rangeTurn(followUp, router: router, meter: meter)
            print("[version range scenario] answer 3: \(flatRange(third))")
            let pinned = await ledger.review(third)
            printRangeFindings(pinned)

            let retry = followUp + "\n" + third + "\n" + (pinned.feedback ?? "")
            let fourth = try await rangeTurn(retry, router: router, meter: meter)
            print("[version range scenario] answer 4 (after the feedback): \(flatRange(fourth))")
            let again = await ledger.review(fourth)
            printRangeFindings(again)
            if again.repeatedCount > 0 {
                print("[version range scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[version range scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[version range scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[version range scenario] FAILED: \(error)")
        }
    }

    private static func flatRange(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printRangeFindings(_ report: RangeReport) {
        for finding in report.findings {
            print("[version range scenario]   \(finding.severity): \(finding.claim.excerpt) -> "
                + finding.explanation)
        }
        print("[version range scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let packageJSON = """
        ```json
        {
          "dependencies": {
            "tiny-parser": "^0.2.3"
          }
        }
        ```
        """

    private static let pinnedRequirements = """
        ```text
        requests^2.31
        django~=4.2
        ```
        In pip, `django~=4.2` allows Django 5.0 as well, so you get the next major release automatically.
        """

    private static let versionRangeScript = [
        """
        \(packageJSON)
        With npm, `^0.2.3` allows minor updates, so `npm install` will pick up 0.3.0 when it ships.
        """,
        """
        \(packageJSON)
        With npm, `^0.2.3` allows patch updates only: it picks up 0.2.9 but not 0.3.0. To take 0.3.x as \
        well, use `>=0.2.3 <0.4.0`.
        """,
        pinnedRequirements,
        "Here is the corrected file:\n" + pinnedRequirements
    ]

    private static func rangeTurn(
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
