import ComposeCommandClaimKit
import EntrypointClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-thirteenth scenario's turns bill against.
extension ProviderIdentifier {
    static let composeCommandHost = ProviderIdentifier("compose-command-host")
}

extension EcosystemDemo {
    /// The hundred-and-thirteenth scenario: what an answer says a compose service runs, checked against compose's
    /// own reading of `command:` and `entrypoint:`.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The question shows a service with
    /// `command: npm install && npm start` that never starts its server. The first answer says compose runs
    /// `command` through a shell, so both parts run; compose runs no shell and stops at `&&`, so only
    /// `npm install` runs. `ComposeCommandClaimKit` flags both claims, and its feedback gets a rewrite with a
    /// `sh -c` list that holds. The follow-up asks for `tini`: the answer sets `entrypoint:` and says the image's
    /// `CMD` still runs after it (an entrypoint set in compose drops it). After the feedback it holds.
    /// `EntrypointClaimKit` reads the same answers as Dockerfile and `docker run` claims, and one `CommandLedger`
    /// reviews the conversation.
    static func runComposeCommandClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .composeCommandHost,
                                                                     script: composeCommandScript)])
            let ledger = CommandLedger()
            let question = "My `web` service installs its dependencies but the server never starts. Why?\n"
                + composeCommandFile
            print("[compose command scenario] user: \(flatComposeCommand(question))")
            let first = try await composeCommandTurn(question, router: router, meter: meter)
            print("[compose command scenario] answer 1: \(flatComposeCommand(first))")
            let imageView = EntrypointClaimChecker().check(first, context: question)
            print("[compose command scenario] EntrypointClaimKit on answer 1: \(imageView.verdict.rawValue) "
                + "(\(imageView.summary))")
            let report = await ledger.review(first, context: question)
            printComposeCommandFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await composeCommandTurn(repair, router: router, meter: meter)
            print("[compose command scenario] answer 2 (after the feedback): \(flatComposeCommand(second))")
            printComposeCommandFindings(await ledger.review(second, context: question))

            let followUp = "Can I run it under tini so signals reach node?"
            print("[compose command scenario] user: \(followUp)")
            let third = try await composeCommandTurn(followUp, router: router, meter: meter)
            print("[compose command scenario] answer 3: \(flatComposeCommand(third))")
            let tini = await ledger.review(third, context: followUp)
            printComposeCommandFindings(tini)

            let retry = followUp + "\n" + third + "\n" + (tini.feedback ?? "")
            let fourth = try await composeCommandTurn(retry, router: router, meter: meter)
            print("[compose command scenario] answer 4 (after the feedback): \(flatComposeCommand(fourth))")
            printComposeCommandFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[compose command scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[compose command scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[compose command scenario] FAILED: \(error)")
        }
    }

    private static func flatComposeCommand(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printComposeCommandFindings(_ report: CommandReport) {
        for finding in report.findings {
            let slip = finding.slip.map { " (\($0.rawValue))" } ?? ""
            print("[compose command scenario]   \(flatComposeCommand(finding.claim.sentence)): "
                + "\(finding.severity)\(slip). " + finding.explanation)
        }
        print("[compose command scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let composeCommandFile = """
    ```yaml
    services:
      web:
        image: node:20-alpine
        working_dir: /app
        command: npm install && npm start
    ```
    """

    private static let composeCommandDockerfile = """
    ```dockerfile
    FROM node:20-alpine
    RUN apk add --no-cache tini
    WORKDIR /app
    COPY . .
    CMD ["node", "server.js"]
    ```

    """

    private static let composeCommandScript = [
        """
        Compose runs `command` through a shell, so `web` runs `npm install && npm start`. The server starts once \
        the install finishes; check `docker compose logs web` for a crash after that.
        """,
        """
        Compose does not run a `command` string through a shell: it splits it into words and stops at `&&`, so \
        the old file ran only `npm install`. Start a shell yourself:
        ```yaml
        services:
          web:
            image: node:20-alpine
            working_dir: /app
            command: ["sh", "-c", "npm install && npm start"]
        ```
        Now `web` runs `npm install && npm start` inside `sh -c`.
        """,
        composeCommandDockerfile + """
        ```yaml
        services:
          web:
            build: .
            entrypoint: ["/sbin/tini", "--"]
        ```
        Setting `entrypoint` keeps the image's `CMD`, so `web` runs `/sbin/tini -- node server.js`.
        """,
        composeCommandDockerfile + """
        ```yaml
        services:
          web:
            build: .
            entrypoint: ["/sbin/tini", "--"]
            command: ["node", "server.js"]
        ```
        Setting `entrypoint` drops the image's `CMD`, so the file repeats it in `command`: `web` runs \
        `/sbin/tini -- node server.js`.
        """
    ]

    private static func composeCommandTurn(
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
