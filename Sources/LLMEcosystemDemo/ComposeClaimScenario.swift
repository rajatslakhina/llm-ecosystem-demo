import ComposeClaimKit
import EntrypointClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-eleventh scenario's turns bill against.
extension ProviderIdentifier {
    static let composeHost = ProviderIdentifier("compose-host")
}

extension EcosystemDemo {
    /// The hundred-and-eleventh scenario: what an answer says about a Docker Compose project, checked with compose's
    /// own rules for ports, service names, substitution and `depends_on`.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer points the API at
    /// `db:5433`, the port `db` publishes on the host (containers use the container port, `5432`), and says
    /// `depends_on` waits until Postgres is ready (it waits for the container to start). `ComposeClaimKit` flags
    /// both, and its feedback gets a rewrite that holds. The follow-up pins the Postgres tag with `.env`: the answer
    /// writes `${PG_TAG-16}` with `PG_TAG=` in `.env` and says it gives `postgres:16` (without a colon an empty value
    /// stays empty), and says `.env` reaches the container (it feeds substitution only). After the feedback it uses
    /// `${PG_TAG:-16}` and holds. `EntrypointClaimKit` reads the same answers, and one `ComposeLedger` reviews the
    /// conversation.
    static func runComposeClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .composeHost, script: composeScript)])
            let ledger = ComposeLedger()
            let question = "Our API can't reach Postgres under docker compose. How do I set DATABASE_URL, and when "
                + "is the database ready?"
            print("[compose scenario] user: \(question)")
            let first = try await composeTurn(question, router: router, meter: meter)
            print("[compose scenario] answer 1: \(flatCompose(first))")
            let entrypointView = EntrypointClaimChecker().check(first, context: question)
            print("[compose scenario] EntrypointClaimKit on answer 1: \(entrypointView.verdict.rawValue) "
                + "(\(entrypointView.summary))")
            let report = await ledger.review(first, context: question)
            printComposeFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await composeTurn(repair, router: router, meter: meter)
            print("[compose scenario] answer 2 (after the feedback): \(flatCompose(second))")
            printComposeFindings(await ledger.review(second, context: question))

            let followUp = "Pin the Postgres image tag with a .env file."
            print("[compose scenario] user: \(followUp)")
            let third = try await composeTurn(followUp, router: router, meter: meter)
            print("[compose scenario] answer 3: \(flatCompose(third))")
            let pinned = await ledger.review(third, context: followUp)
            printComposeFindings(pinned)

            let retry = followUp + "\n" + third + "\n" + (pinned.feedback ?? "")
            let fourth = try await composeTurn(retry, router: router, meter: meter)
            print("[compose scenario] answer 4 (after the feedback): \(flatCompose(fourth))")
            printComposeFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[compose scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[compose scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[compose scenario] FAILED: \(error)")
        }
    }

    private static func flatCompose(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printComposeFindings(_ report: ComposeReport) {
        for finding in report.findings {
            print("[compose scenario]   \(finding.severity): \(finding.explanation)")
        }
        print("[compose scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let composeScript = [
        """
        ```yaml
        services:
          api:
            build: .
            ports:
              - "8000:8000"
            environment:
              DATABASE_URL: postgres://app:secret@db:5433/app
            depends_on:
              - db
          db:
            image: postgres:16
            ports:
              - "5433:5432"
        ```
        The `api` service connects to Postgres at `db:5433`. `depends_on` makes sure the database is ready before \
        the API starts.
        """,
        """
        ```yaml
        services:
          api:
            build: .
            ports:
              - "8000:8000"
            environment:
              DATABASE_URL: postgres://app:secret@db:5432/app
            depends_on:
              db:
                condition: service_healthy
          db:
            image: postgres:16
            ports:
              - "5433:5432"
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -U app"]
        ```
        The `api` service connects to Postgres at `db:5432`, the container port. From your laptop, open a client on \
        `localhost:5433`. With `condition: service_healthy`, compose starts the API once `pg_isready` passes.
        """,
        """
        ```yaml
        services:
          db:
            image: "postgres:${PG_TAG-16}"
        ```
        Add this to `.env`:

        ```env
        PG_TAG=
        ```
        Because `PG_TAG` is empty, `postgres:${PG_TAG-16}` becomes `postgres:16`. Variables in `.env` are also \
        available inside the container.
        """,
        """
        ```yaml
        services:
          db:
            image: "postgres:${PG_TAG:-16}"
        ```
        Add this to `.env`:

        ```env
        PG_TAG=
        ```
        Because `PG_TAG` is empty, `postgres:${PG_TAG:-16}` becomes `postgres:16`. The `.env` file is only used for \
        substitution in the compose file; set `PG_TAG=16.4` there to pin a minor version.
        """
    ]

    private static func composeTurn(
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
