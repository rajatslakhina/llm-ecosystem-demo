import DockerfileClaimKit
import EntrypointClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-tenth scenario's turns bill against.
extension ProviderIdentifier {
    static let entrypointHost = ProviderIdentifier("entrypoint-host")
}

extension EcosystemDemo {
    /// The hundred-and-tenth scenario: what an answer says a container runs, checked with Docker's rules for
    /// `CMD`, `ENTRYPOINT` and `docker run`.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer says
    /// `docker run api --debug` keeps the `CMD`'s `--port 80` (arguments replace `CMD`) and that
    /// `docker run -it api bash` gives a shell (the `ENTRYPOINT` gets `bash` as an argument). `EntrypointClaimKit`
    /// flags both and its feedback gets a rewrite that holds. The follow-up asks for `tini` as PID 1: the answer
    /// builds a stage on a base stage that set `CMD`, adds `ENTRYPOINT ["tini", "--"]`, and says the base `CMD`
    /// still runs under it (an `ENTRYPOINT` empties an inherited `CMD`); after the feedback it sets `CMD` again and
    /// holds. `DockerfileClaimKit` reads the same answers, and one `EntrypointLedger` reviews the conversation.
    static func runEntrypointClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .entrypointHost, script: entrypointScript)
            ])
            let ledger = EntrypointLedger()
            let question = "How do I turn on --debug when I run our API container, and how do I get a shell in it?"
            print("[entrypoint scenario] user: \(question)")
            let first = try await entrypointTurn(question, router: router, meter: meter)
            print("[entrypoint scenario] answer 1: \(flatEntrypoint(first))")
            let dockerfileView = DockerfileClaimChecker().check(first, context: question)
            print("[entrypoint scenario] DockerfileClaimKit on answer 1: \(dockerfileView.verdict.rawValue) "
                + "(\(dockerfileView.summary))")
            let report = await ledger.review(first, context: question)
            printEntrypointFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await entrypointTurn(repair, router: router, meter: meter)
            print("[entrypoint scenario] answer 2 (after the feedback): \(flatEntrypoint(second))")
            printEntrypointFindings(await ledger.review(second, context: question))

            let followUp = "Run the server under tini so it is PID 1."
            print("[entrypoint scenario] user: \(followUp)")
            let third = try await entrypointTurn(followUp, router: router, meter: meter)
            print("[entrypoint scenario] answer 3: \(flatEntrypoint(third))")
            let staged = await ledger.review(third, context: followUp)
            printEntrypointFindings(staged)

            let retry = followUp + "\n" + third + "\n" + (staged.feedback ?? "")
            let fourth = try await entrypointTurn(retry, router: router, meter: meter)
            print("[entrypoint scenario] answer 4 (after the feedback): \(flatEntrypoint(fourth))")
            printEntrypointFindings(await ledger.review(fourth, context: followUp))
            let fourthDockerfile = DockerfileClaimChecker().check(fourth, context: followUp)
            print("[entrypoint scenario] DockerfileClaimKit on answer 4: \(fourthDockerfile.verdict.rawValue) "
                + "(\(fourthDockerfile.summary))")
            let statistics = await ledger.statistics
            print("[entrypoint scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[entrypoint scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[entrypoint scenario] FAILED: \(error)")
        }
    }

    private static func flatEntrypoint(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printEntrypointFindings(_ report: EntrypointReport) {
        for finding in report.findings {
            print("[entrypoint scenario]   \(finding.severity): \(finding.explanation)")
        }
        print("[entrypoint scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let entrypointScript = [
        """
        ```dockerfile
        FROM python:3.12-slim
        WORKDIR /app
        COPY . .
        ENTRYPOINT ["python", "app.py"]
        CMD ["--port", "80"]
        ```
        Build it with `docker build -t api .`. Then `docker run api --debug` runs `python app.py --port 80 --debug`, \
        and `docker run -it api bash` starts `bash` for a shell.
        """,
        """
        ```dockerfile
        FROM python:3.12-slim
        WORKDIR /app
        COPY . .
        ENTRYPOINT ["python", "app.py"]
        CMD ["--port", "80"]
        ```
        Build it with `docker build -t api .`. Arguments after the image replace CMD, so \
        `docker run api --port 80 --debug` runs `python app.py --port 80 --debug`. For a shell, \
        `docker run -it --entrypoint bash api` starts `bash`; with `--entrypoint`, Docker also clears CMD.
        """,
        """
        ```dockerfile
        FROM python:3.12-slim AS base
        WORKDIR /app
        COPY . .
        CMD ["python", "app.py", "--port", "80"]

        FROM base
        RUN apt-get update && apt-get install -y --no-install-recommends tini
        ENTRYPOINT ["tini", "--"]
        ```
        Build it with `docker build -t api .`. Now `docker run api` runs `tini -- python app.py --port 80`, because \
        setting ENTRYPOINT keeps the CMD from the base stage.
        """,
        """
        ```dockerfile
        FROM python:3.12-slim AS base
        WORKDIR /app
        COPY . .
        CMD ["python", "app.py", "--port", "80"]

        FROM base
        RUN apt-get update && apt-get install -y --no-install-recommends tini
        ENTRYPOINT ["tini", "--"]
        CMD ["python", "app.py", "--port", "80"]
        ```
        Build it with `docker build -t api .`. The ENTRYPOINT empties the CMD inherited from the base stage, so the \
        final stage sets it again: `docker run api` runs `tini -- python app.py --port 80`.
        """
    ]

    private static func entrypointTurn(
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
