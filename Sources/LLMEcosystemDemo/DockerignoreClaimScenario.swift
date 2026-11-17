import DockerignoreClaimKit
import Foundation
import GitignoreClaimKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-eighth scenario's turns bill against.
extension ProviderIdentifier {
    static let dockerignoreHost = ProviderIdentifier("dockerignore-host")
}

extension EcosystemDemo {
    /// The hundred-and-eighth scenario: what an answer says about .dockerignore rules, checked with Docker's own
    /// matching.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer writes the
    /// .dockerignore the way it would write a .gitignore: `node_modules` and `*.log`, said to match in every
    /// package; `.env   # local secrets` on one line; a `.dockerignore` per service folder. `GitignoreClaimKit`
    /// finds no claim of its own to check there (another tool's file); `DockerignoreClaimKit` checks them: Docker
    /// matches from the root of the build context, `#` starts a comment only at the start of a line, and only the root
    /// file is read. Its feedback gets a rewrite that holds. The follow-up keeps one file inside `node_modules`
    /// with `!**/keep.txt`; the team builds with the classic builder, which never searches the excluded folder for
    /// a wildcard exception, so the conversation's one `DockerignoreLedger` (pinned to `.classic`) flags it, and
    /// the literal `!node_modules/pkg/keep.txt` it suggests holds.
    static func runDockerignoreClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .dockerignoreHost, script: dockerignoreScript)
            ])
            let ledger = DockerignoreLedger(checker: DockerignoreClaimChecker(policy: .classic))
            let question = "Write a .dockerignore for our monorepo: keep every package's node_modules, the log "
                + "files and .env out of the image."
            print("[dockerignore scenario] user: \(question)")
            let first = try await dockerignoreTurn(question, router: router, meter: meter)
            print("[dockerignore scenario] answer 1: \(flatDockerignore(first))")
            let gitView = IgnoreClaimChecker().check(first, context: question)
            print("[dockerignore scenario] GitignoreClaimKit on answer 1: \(gitView.verdict.rawValue) "
                + "(\(gitView.summary))")
            let report = await ledger.review(first, context: question)
            printDockerignoreFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await dockerignoreTurn(repair, router: router, meter: meter)
            print("[dockerignore scenario] answer 2 (after the feedback): \(flatDockerignore(second))")
            let fixed = await ledger.review(second, context: question)
            printDockerignoreFindings(fixed)

            let followUp = "One package needs node_modules/pkg/keep.txt in the image. Keep that file."
            print("[dockerignore scenario] user: \(followUp)")
            let third = try await dockerignoreTurn(followUp, router: router, meter: meter)
            print("[dockerignore scenario] answer 3: \(flatDockerignore(third))")
            let keep = await ledger.review(third, context: followUp)
            printDockerignoreFindings(keep)
            let unpinned = DockerignoreClaimChecker().check(third, context: followUp)
            print("[dockerignore scenario] with the builder unknown: \(unpinned.verdict.rawValue) "
                + "(\(unpinned.summary))")

            let retry = followUp + "\n" + third + "\n" + (keep.feedback ?? "")
            let fourth = try await dockerignoreTurn(retry, router: router, meter: meter)
            print("[dockerignore scenario] answer 4 (after the feedback): \(flatDockerignore(fourth))")
            let literal = await ledger.review(fourth, context: followUp)
            printDockerignoreFindings(literal)
            let statistics = await ledger.statistics
            print("[dockerignore scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[dockerignore scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[dockerignore scenario] FAILED: \(error)")
        }
    }

    private static func flatDockerignore(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printDockerignoreFindings(_ report: DockerignoreReport) {
        for finding in report.findings {
            print("[dockerignore scenario]   \(finding.severity): \(finding.claim.kind.rawValue) "
                + "`\(finding.claim.subject)` -> \(finding.explanation)")
        }
        print("[dockerignore scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let dockerignoreScript = [
        """
        Add this to your `.dockerignore`:
        ```
        node_modules
        *.log
        .env   # local secrets
        ```
        This excludes `node_modules` in every package, so `packages/api/node_modules/react/index.js` is never \
        sent, and `*.log` matches log files at any depth. Put a `.dockerignore` in each service folder too, for \
        example `packages/api/.dockerignore`.
        """,
        """
        Docker matches every pattern from the root of the build context, so say where:
        ```dockerignore
        **/node_modules
        **/*.log
        # local secrets
        .env
        ```
        Now `packages/api/node_modules/react/index.js` and `packages/web/debug.log` are left out. Docker reads \
        only the `.dockerignore` at the root of the build context, not `packages/api/.dockerignore`.
        """,
        """
        Add an exception after the `**/node_modules` line:
        ```dockerignore
        **/node_modules
        !**/keep.txt
        ```
        Now `node_modules/pkg/keep.txt` is sent with the build context.
        """,
        """
        Name the file literally, so the builder searches the folder:
        ```dockerignore
        **/node_modules
        !node_modules/pkg/keep.txt
        ```
        Now `node_modules/pkg/keep.txt` is sent and `node_modules/pkg/index.js` is still left out.
        """
    ]

    private static func dockerignoreTurn(
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
