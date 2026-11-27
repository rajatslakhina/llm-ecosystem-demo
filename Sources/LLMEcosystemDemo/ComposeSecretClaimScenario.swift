import ComposeSecretClaimKit
import ComposeVolumeClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-sixteenth scenario's turns bill against.
extension ProviderIdentifier {
    static let composeSecretHost = ProviderIdentifier("compose-secret-host")
}

extension EcosystemDemo {
    /// The hundred-and-sixteenth scenario: what an answer says about compose secrets and configs, checked against
    /// what plain `docker compose` (not Swarm) does with them.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The question shows `db` reading its
    /// password through `POSTGRES_PASSWORD_FILE` from the `file:` secret `db_password`, and `web` with an
    /// `environment:` secret `api_key` (`target: api.key`) and the `file:` secret `tls_key` (`mode: 0400`). The
    /// first answer says the secret becomes an environment variable, gives `api_key` the path `/api_key`, says
    /// `mode: 0400` locks `tls_key` down and that compose encrypts secrets; `ComposeSecretClaimKit` flags all four,
    /// and the corrected answer holds. The follow-up asks to use a secret made with `docker secret create`: the
    /// answer writes `external: true` and says `docker compose up` reads it, both wrong; after the feedback the
    /// answer keeps the `file:` source. `ComposeVolumeClaimKit` reads the same answers and stays quiet: none of this
    /// is about volumes. One `SecretLedger` reviews the conversation.
    static func runComposeSecretClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .composeSecretHost,
                                                                     script: composeSecretScript)])
            let ledger = SecretLedger()
            let question = "How do these secrets reach the containers, and is the TLS key private?\n"
                + composeSecretFile
            print("[secret scenario] user: \(flatSecret(question))")
            let first = try await composeSecretTurn(question, router: router, meter: meter)
            print("[secret scenario] answer 1: \(flatSecret(first))")
            let volumeView = VolumeClaimChecker().check(first, context: question)
            print("[secret scenario] ComposeVolumeClaimKit on answer 1: \(volumeView.verdict.rawValue)")
            let report = await ledger.review(first, context: question)
            printSecretFindings(report)

            let repair = question + "\n" + first + "\n" + report.corrections.joined(separator: " ")
            let second = try await composeSecretTurn(repair, router: router, meter: meter)
            print("[secret scenario] answer 2 (after the feedback): \(flatSecret(second))")
            printSecretFindings(await ledger.review(second, context: question))
            let project = SecretClaimChecker().scene(for: second, context: question).project
            let paths = ["db_password", "api_key", "tls_key"].map { key in
                "\(key) -> " + (project?.paths(.secret, key).joined(separator: ", ") ?? "nothing")
            }
            print("[secret scenario] where compose mounts them: \(paths.joined(separator: "; "))")

            let followUp = "Can I use a secret I made with `docker secret create` instead of the file?"
            print("[secret scenario] user: \(followUp)")
            let third = try await composeSecretTurn(followUp, router: router, meter: meter)
            print("[secret scenario] answer 3: \(flatSecret(third))")
            let external = await ledger.review(third, context: followUp)
            printSecretFindings(external)

            let retry = followUp + "\n" + third + "\n" + external.corrections.joined(separator: " ")
            let fourth = try await composeSecretTurn(retry, router: router, meter: meter)
            print("[secret scenario] answer 4 (after the feedback): \(flatSecret(fourth))")
            printSecretFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[secret scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[secret scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[secret scenario] FAILED: \(error)")
        }
    }

    private static func flatSecret(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printSecretFindings(_ report: SecretReport) {
        for finding in report.findings {
            let fix = finding.correction.map { " " + $0 } ?? ""
            print("[secret scenario]   \(flatSecret(finding.claim.sentence)): \(finding.severity).\(fix)")
        }
        print("[secret scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let composeSecretFile = """
    ```yaml
    services:
      db:
        image: postgres:18
        environment:
          POSTGRES_PASSWORD_FILE: /run/secrets/db_password
        secrets:
          - db_password
      web:
        image: nginx:1.27
        secrets:
          - source: api_key
            target: api.key
          - source: tls_key
            mode: 0400
    secrets:
      db_password:
        file: ./db_password.txt
      api_key:
        environment: API_KEY
      tls_key:
        file: ./tls.key
    ```
    """

    private static let composeSecretScript = [
        """
        Compose exposes the secret as an environment variable named `DB_PASSWORD` inside the container. The API \
        key ends up at `/api_key`. With `mode: 0400`, `tls_key` is readable only by its owner. Compose secrets \
        are encrypted at rest on the host.
        """,
        """
        Compose mounts the secret as a file at `/run/secrets/db_password`, and postgres finds it through \
        `POSTGRES_PASSWORD_FILE`. The API key is at `/run/secrets/api.key`. The `tls_key` secret comes from a \
        file, so compose ignores its `mode`. Compose secrets are not encrypted.
        """,
        """
        Yes, mark it external:
        ```yaml
        services:
          db:
            image: postgres:18
            secrets:
              - db_password
        secrets:
          db_password:
            external: true
        ```
        With `external: true`, `docker compose up` reads the secret you made with `docker secret create`.
        """,
        """
        `docker compose up` refuses an `external` secret ("unsupported external secret"), so keep the `file:` \
        source for plain compose.
        """
    ]

    private static func composeSecretTurn(
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
