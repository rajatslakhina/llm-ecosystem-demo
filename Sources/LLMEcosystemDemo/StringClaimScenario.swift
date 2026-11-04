import Foundation
import ProviderGatewayKit
import StringClaimKit
import TokenMeterKit

/// The identifier the hundred-and-first scenario's turns bill against.
extension ProviderIdentifier {
    static let stringClaimHost = ProviderIdentifier("string-claim-host")
}

extension EcosystemDemo {
    /// The hundred-and-first scenario: what an answer says about strings, run character by character.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer counts two
    /// r's in "strawberry" and gives the base64 of "hello" with the newline `echo` sends; its own terminal
    /// transcript is right, which is how the newline got in. `StringClaimKit` runs every claim and names
    /// both slips, and its feedback gets a rewrite that holds. The follow-up asks for a SHA-256 and gets the
    /// digest of "hello\n"; asked again, the model repeats it, and the one `StringLedger` for the
    /// conversation marks the repeat, so the app stops re-asking and shows the note instead.
    static func runStringClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .stringClaimHost, script: stringClaimScript)
            ])
            let ledger = StringLedger()
            let question = "How many r's are in \"strawberry\", and what is \"hello\" in base64?"
            print("[string claim scenario] user: \(question)")
            let first = try await stringTurn(question, router: router, meter: meter)
            print("[string claim scenario] answer 1: \(flat(first))")
            let report = await ledger.review(first)
            printStringFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await stringTurn(repair, router: router, meter: meter)
            print("[string claim scenario] answer 2 (after the feedback): \(flat(second))")
            let fixed = await ledger.review(second)
            print("[string claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "And the SHA-256 of \"hello\"?"
            print("[string claim scenario] user: \(followUp)")
            let third = try await stringTurn(followUp, router: router, meter: meter)
            print("[string claim scenario] answer 3: \(flat(third))")
            let digest = await ledger.review(third)
            printStringFindings(digest)

            let retry = followUp + "\n" + third + "\n" + (digest.feedback ?? "")
            let fourth = try await stringTurn(retry, router: router, meter: meter)
            print("[string claim scenario] answer 4 (after the feedback): \(flat(fourth))")
            let again = await ledger.review(fourth)
            printStringFindings(again)
            if again.repeatedCount > 0 {
                print("[string claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[string claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[string claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[string claim scenario] FAILED: \(error)")
        }
    }

    private static func flat(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printStringFindings(_ report: StringReport) {
        for finding in report.findings {
            let excerpt = flat(finding.claim.excerpt)
            print("[string claim scenario]   \(finding.severity): \(excerpt) -> " + finding.explanation)
        }
        print("[string claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let stringClaimScript = [
        """
        There are 2 r's in "strawberry". "hello" in base64 is aGVsbG8K:
        ```bash
        $ echo hello | base64
        aGVsbG8K
        ```
        """,
        """
        There are 3 r's in "strawberry". "hello" in base64 is aGVsbG8=; `echo` adds a newline, so leave it out:
        ```bash
        $ echo -n hello | base64
        aGVsbG8=
        ```
        """,
        """
        The SHA-256 of "hello" is 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03.
        """,
        """
        Checked again: the SHA-256 of "hello" is 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03.
        """
    ]

    private static func stringTurn(
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
