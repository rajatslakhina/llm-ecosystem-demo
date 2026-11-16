import Foundation
import GitignoreClaimKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-seventh scenario's turns bill against.
extension ProviderIdentifier {
    static let gitignoreHost = ProviderIdentifier("gitignore-host")
}

extension EcosystemDemo {
    /// The hundred-and-seventh scenario: what an answer says about .gitignore rules, checked with git's own
    /// matching.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer ignores `logs/`
    /// and then tries to keep `logs/keep.log` with a `!` line, writes `.env   # local secrets` on one line, and
    /// says the entry makes git stop tracking an already committed `.env`. `GitignoreClaimKit` applies git's
    /// rules: nothing below an excluded directory comes back, `#` starts a comment only at the start of a line,
    /// and ignore rules never untrack a tracked file. Its feedback gets a rewrite that holds (`logs/*`, the
    /// comment on its own line, `git rm --cached`). The follow-up says `doc/*.txt` matches
    /// `doc/server/arch.txt`; asked again, the model repeats it, and the conversation's one `IgnoreLedger`
    /// marks the repeat.
    static func runGitignoreClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .gitignoreHost, script: gitignoreScript)
            ])
            let ledger = IgnoreLedger()
            let question = "Ignore our logs folder but keep logs/keep.log in the repo. .env is already committed: "
                + "keep it out of git from now on."
            print("[gitignore scenario] user: \(question)")
            let first = try await ignoreTurn(question, router: router, meter: meter)
            print("[gitignore scenario] answer 1: \(flatIgnore(first))")
            let report = await ledger.review(first, context: question)
            printIgnoreFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await ignoreTurn(repair, router: router, meter: meter)
            print("[gitignore scenario] answer 2 (after the feedback): \(flatIgnore(second))")
            let fixed = await ledger.review(second, context: question)
            print("[gitignore scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "Also ignore the generated docs: every .txt file under doc/, however deep."
            print("[gitignore scenario] user: \(followUp)")
            let third = try await ignoreTurn(followUp, router: router, meter: meter)
            print("[gitignore scenario] answer 3: \(flatIgnore(third))")
            let docs = await ledger.review(third, context: followUp)
            printIgnoreFindings(docs)

            let retry = followUp + "\n" + third + "\n" + (docs.feedback ?? "")
            let fourth = try await ignoreTurn(retry, router: router, meter: meter)
            print("[gitignore scenario] answer 4 (after the feedback): \(flatIgnore(fourth))")
            let again = await ledger.review(fourth, context: followUp)
            printIgnoreFindings(again)
            if again.repeatedCount > 0 {
                print("[gitignore scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[gitignore scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[gitignore scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[gitignore scenario] FAILED: \(error)")
        }
    }

    private static func flatIgnore(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printIgnoreFindings(_ report: IgnoreReport) {
        for finding in report.findings {
            print("[gitignore scenario]   \(finding.severity): \(finding.claim.kind.rawValue) "
                + "`\(finding.claim.subject)` -> \(finding.explanation)")
        }
        print("[gitignore scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let docsClaim = """
        `doc/*.txt` matches `doc/server/arch.txt` as well, so nested text files are covered.
        """

    private static let gitignoreScript = [
        """
        Add this to your `.gitignore`:
        ```gitignore
        logs/
        !logs/keep.log
        .env   # local secrets
        ```
        This ignores everything in `logs/` but keeps `logs/keep.log` tracked. Adding `.env` to the .gitignore \
        also makes git stop tracking it.
        """,
        """
        ```gitignore
        logs/*
        !logs/keep.log
        # local secrets
        .env
        ```
        Now `logs/keep.log` is tracked and `logs/app.log` is ignored. A .gitignore entry does not untrack a file \
        that is already committed, so run `git rm --cached .env` once and commit.
        """,
        "Add `doc/*.txt` to the .gitignore. " + docsClaim,
        "You're right to check. " + docsClaim
    ]

    private static func ignoreTurn(
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
