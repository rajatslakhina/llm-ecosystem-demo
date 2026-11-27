import ComposeCommandClaimKit
import Foundation
import HealthcheckClaimKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-fourteenth scenario's turns bill against.
extension ProviderIdentifier {
    static let healthcheckHost = ProviderIdentifier("healthcheck-host")
}

extension EcosystemDemo {
    /// The hundred-and-fourteenth scenario: what an answer says about a container healthcheck, checked against
    /// what Docker Compose and the engine do with it.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The question shows an `api` service
    /// whose test is `["CMD", "curl", ..., "||", "exit", "1"]` and asks why the container stays unhealthy and never
    /// restarts. The first answer says Docker runs the test through a shell and restarts unhealthy containers under
    /// `restart: always`; the exec form runs no shell and the engine never restarts for health, so
    /// `HealthcheckClaimKit` flags both, and the rewrite with `CMD-SHELL` holds. The follow-up asks to send an API
    /// token from the service's `environment:`: the answer writes `$API_TOKEN` and says compose fills it from the
    /// container, which compose does not (it substitutes from the shell and `.env` when it reads the file). After
    /// the feedback the file writes `$$API_TOKEN` and holds. `ComposeCommandClaimKit` reads the same answers and
    /// stays quiet: a healthcheck `test:` is not a `command:`. One `HealthLedger` reviews the conversation.
    static func runHealthcheckClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .healthcheckHost,
                                                                     script: healthcheckScript)])
            let ledger = HealthLedger()
            let question = "My `api` container stays unhealthy and Docker never restarts it. Why?\n" + healthcheckFile
            print("[healthcheck scenario] user: \(flatHealthcheck(question))")
            let first = try await healthcheckTurn(question, router: router, meter: meter)
            print("[healthcheck scenario] answer 1: \(flatHealthcheck(first))")
            let commandView = CommandClaimChecker().check(first, context: question)
            print("[healthcheck scenario] ComposeCommandClaimKit on answer 1: \(commandView.verdict.rawValue) "
                + "(\(commandView.summary))")
            let report = await ledger.review(first, context: question)
            printHealthcheckFindings(report)

            let repair = question + "\n" + first + "\n" + report.corrections.joined(separator: " ")
            let second = try await healthcheckTurn(repair, router: router, meter: meter)
            print("[healthcheck scenario] answer 2 (after the feedback): \(flatHealthcheck(second))")
            // ComposeCommandClaimKit 1.0.1 flagged this answer's exec-form sentence; 1.0.2 leaves healthchecks alone.
            let commandOnFix = CommandClaimChecker().check(second, context: question)
            print("[healthcheck scenario] ComposeCommandClaimKit on answer 2: \(commandOnFix.verdict.rawValue) "
                + "(\(commandOnFix.summary))")
            printHealthcheckFindings(await ledger.review(second, context: question))
            let scene = HealthClaimChecker().scene(for: second)
            print("[healthcheck scenario] api's image is unseen, so its effective healthcheck is "
                + (scene.effective("api")?.summary ?? "unknown") + "; compose sets "
                + (scene.project?.service("api")?.healthcheck?.summary ?? "nothing"))

            let followUp = "Can the healthcheck send the API token the service already has in `environment:`?"
            print("[healthcheck scenario] user: \(followUp)")
            let third = try await healthcheckTurn(followUp, router: router, meter: meter)
            print("[healthcheck scenario] answer 3: \(flatHealthcheck(third))")
            let token = await ledger.review(third, context: followUp)
            printHealthcheckFindings(token)

            let retry = followUp + "\n" + third + "\n" + token.corrections.joined(separator: " ")
            let fourth = try await healthcheckTurn(retry, router: router, meter: meter)
            print("[healthcheck scenario] answer 4 (after the feedback): \(flatHealthcheck(fourth))")
            printHealthcheckFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[healthcheck scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[healthcheck scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[healthcheck scenario] FAILED: \(error)")
        }
    }

    private static func flatHealthcheck(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printHealthcheckFindings(_ report: HealthReport) {
        for finding in report.findings {
            let fix = finding.correction.map { " " + $0 } ?? ""
            print("[healthcheck scenario]   \(flatHealthcheck(finding.claim.sentence)): \(finding.severity).\(fix)")
        }
        print("[healthcheck scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let healthcheckFile = """
    ```yaml
    services:
      api:
        image: myorg/api:2.4
        restart: always
        ports:
          - "8080:3000"
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost:3000/health", "||", "exit", "1"]
          interval: 10s
    ```
    """

    private static let healthcheckScript = [
        """
        Your healthcheck is fine: Docker runs the test through a shell, so the `||` works. With `restart: always`, \
        Docker restarts the container when it becomes unhealthy, so give it a minute.
        """,
        """
        The exec form runs `curl` directly, so the `||` reached it as an argument. Use `CMD-SHELL`:
        ```yaml
        services:
          api:
            image: myorg/api:2.4
            restart: always
            ports:
              - "8080:3000"
            healthcheck:
              test: ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
              interval: 10s
        ```
        A `CMD-SHELL` test is run by a shell. Docker never restarts an unhealthy container, even with \
        `restart: always`; it only marks it `unhealthy`.
        """,
        """
        ```yaml
        services:
          api:
            image: myorg/api:2.4
            environment:
              API_TOKEN: example-token
            healthcheck:
              test: ["CMD-SHELL", "curl -f -H 'Authorization: Bearer $API_TOKEN' http://localhost:3000/health"]
        ```
        Compose fills `$API_TOKEN` in the healthcheck from the container's environment.
        """,
        """
        ```yaml
        services:
          api:
            image: myorg/api:2.4
            environment:
              API_TOKEN: example-token
            healthcheck:
              test: ["CMD-SHELL", "curl -f -H 'Authorization: Bearer $$API_TOKEN' http://localhost:3000/health"]
        ```
        Compose substitutes `$API_TOKEN` when it reads the file, so the file writes `$$API_TOKEN` and the \
        container's shell expands it.
        """
    ]

    private static func healthcheckTurn(
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
