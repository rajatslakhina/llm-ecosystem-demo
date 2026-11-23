import ComposeClaimKit
import ComposeMergeClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-twelfth scenario's turns bill against.
extension ProviderIdentifier {
    static let composeMergeHost = ProviderIdentifier("compose-merge-host")
}

extension EcosystemDemo {
    /// The hundred-and-twelfth scenario: what an answer says about a base compose file and its override together,
    /// checked with compose's merge rules.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer shows
    /// `docker-compose.yml` and `docker-compose.override.yml` and says the API publishes `8081` instead of `8080` and
    /// that `LOG_LEVEL` is gone (compose appends a later file's `ports` and merges `environment` by key).
    /// `ComposeMergeClaimKit` flags both, and its feedback gets a rewrite that holds. The follow-up asks for a
    /// production run: the answer runs `docker compose -f docker-compose.yml` and says `DEBUG` is still `1` (with
    /// `-f`, compose reads only the files named). After the feedback it holds. `ComposeClaimKit` reads the same
    /// answers file by file, and one `MergeLedger` reviews the conversation.
    static func runComposeMergeClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .composeMergeHost,
                                                                     script: composeMergeScript)])
            let ledger = MergeLedger()
            let question = "In development I want the API on port 8081 with debug logging. How do I use a docker "
                + "compose override file for that?"
            print("[compose merge scenario] user: \(question)")
            let first = try await composeMergeTurn(question, router: router, meter: meter)
            print("[compose merge scenario] answer 1: \(flatComposeMerge(first))")
            let fileView = ComposeClaimChecker().check(first, context: question)
            print("[compose merge scenario] ComposeClaimKit on answer 1: \(fileView.verdict.rawValue) "
                + "(\(fileView.summary))")
            let report = await ledger.review(first, context: question)
            printComposeMergeFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await composeMergeTurn(repair, router: router, meter: meter)
            print("[compose merge scenario] answer 2 (after the feedback): \(flatComposeMerge(second))")
            printComposeMergeFindings(await ledger.review(second, context: question))

            let followUp = "How do I run it in production without the development override?"
            print("[compose merge scenario] user: \(followUp)")
            let third = try await composeMergeTurn(followUp, router: router, meter: meter)
            print("[compose merge scenario] answer 3: \(flatComposeMerge(third))")
            let production = await ledger.review(third, context: followUp)
            printComposeMergeFindings(production)

            let retry = followUp + "\n" + third + "\n" + (production.feedback ?? "")
            let fourth = try await composeMergeTurn(retry, router: router, meter: meter)
            print("[compose merge scenario] answer 4 (after the feedback): \(flatComposeMerge(fourth))")
            printComposeMergeFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[compose merge scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[compose merge scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[compose merge scenario] FAILED: \(error)")
        }
    }

    private static func flatComposeMerge(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printComposeMergeFindings(_ report: MergeReport) {
        for finding in report.findings {
            let slip = finding.slip.map { " (\($0.rawValue))" } ?? ""
            print("[compose merge scenario]   \(finding.claim.summary): \(finding.severity)\(slip). "
                + finding.explanation)
        }
        print("[compose merge scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let composeMergeBase = """
    `docker-compose.yml`:
    ```yaml
    services:
      api:
        image: shop-api:1.4
        ports:
          - "8080:8000"
        environment:
          LOG_LEVEL: info
          DEBUG: "0"
    ```

    """

    private static let composeMergeScript = [
        composeMergeBase + """
        `docker-compose.override.yml`:
        ```yaml
        services:
          api:
            ports:
              - "8081:8000"
            environment:
              DEBUG: "1"
        ```
        Run `docker compose up`. With both files, `api` publishes `8081` instead of `8080`, and `LOG_LEVEL` is \
        gone because the override's environment replaces the base one.
        """,
        composeMergeBase + """
        `docker-compose.override.yml`:
        ```yaml
        services:
          api:
            ports:
              - "8081:8000"
            environment:
              DEBUG: "1"
        ```
        Run `docker compose up`. With both files, `api` publishes both `8080` and `8081`, because compose appends \
        the override's ports. `DEBUG` is `1` and `LOG_LEVEL` stays `info` with both files.
        """,
        """
        Run `docker compose -f docker-compose.yml up -d`; the override is still applied, so `DEBUG` stays `1`.
        """,
        """
        Run `docker compose -f docker-compose.yml up -d`: with `-f`, compose reads only the files named, so `DEBUG` \
        is `0` and `api` publishes only `8080`.
        """
    ]

    private static func composeMergeTurn(
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
