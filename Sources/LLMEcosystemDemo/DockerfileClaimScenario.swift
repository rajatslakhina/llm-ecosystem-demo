import DockerfileClaimKit
import DockerignoreClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-ninth scenario's turns bill against.
extension ProviderIdentifier {
    static let dockerfileHost = ProviderIdentifier("dockerfile-host")
}

extension EcosystemDemo {
    /// The hundred-and-ninth scenario: what an answer says about a Dockerfile, checked with a model of how Docker
    /// reads it.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer reads its own
    /// Dockerfile like a shell script: `COPY src /app` said to keep the `src` folder, `RUN cd /app` on a line of its
    /// own, an `ARG` declared above `FROM` and used in a `RUN`, `$PORT` in an exec-form `CMD`, and
    /// `COPY package.json package-lock.json .` (several sources to `.`, which stops the classic builder).
    /// `DockerignoreClaimKit` finds no .dockerignore claim in it; `DockerfileClaimKit` flags each line and the
    /// sentence, and its feedback gets a rewrite that holds. The follow-up asks for a multi-stage build that keeps
    /// `NODE_ENV=production`: the answer says the build stage's `ENV` is still set in a final stage built from a
    /// fresh image (wrong), then builds the final stage `FROM` the build stage (holds). One `DockerfileLedger`
    /// reviews the conversation; the first answer is also judged with the builder pinned to `.classic`.
    static func runDockerfileClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .dockerfileHost, script: dockerfileScript)
            ])
            let ledger = DockerfileLedger()
            let question = "Write a Dockerfile for our Node API (code in src/, entry src/index.js, port from $PORT) "
                + "and say where the code ends up in the image."
            print("[dockerfile scenario] user: \(question)")
            let first = try await dockerfileTurn(question, router: router, meter: meter)
            print("[dockerfile scenario] answer 1: \(flatDockerfile(first))")
            let ignoreView = DockerignoreClaimChecker().check(first, context: question)
            print("[dockerfile scenario] DockerignoreClaimKit on answer 1: \(ignoreView.verdict.rawValue) "
                + "(\(ignoreView.summary))")
            let report = await ledger.review(first, context: question)
            printDockerfileFindings(report)
            let classic = DockerfileClaimChecker(policy: .classic).check(first, context: question)
            print("[dockerfile scenario] with the classic builder named: \(classic.verdict.rawValue) "
                + "(\(classic.summary))")

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await dockerfileTurn(repair, router: router, meter: meter)
            print("[dockerfile scenario] answer 2 (after the feedback): \(flatDockerfile(second))")
            printDockerfileFindings(await ledger.review(second, context: question))

            let followUp = "Make it multi-stage and keep NODE_ENV=production in the final image."
            print("[dockerfile scenario] user: \(followUp)")
            let third = try await dockerfileTurn(followUp, router: router, meter: meter)
            print("[dockerfile scenario] answer 3: \(flatDockerfile(third))")
            let stages = await ledger.review(third, context: followUp)
            printDockerfileFindings(stages)

            let retry = followUp + "\n" + third + "\n" + (stages.feedback ?? "")
            let fourth = try await dockerfileTurn(retry, router: router, meter: meter)
            print("[dockerfile scenario] answer 4 (after the feedback): \(flatDockerfile(fourth))")
            printDockerfileFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[dockerfile scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[dockerfile scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[dockerfile scenario] FAILED: \(error)")
        }
    }

    private static func flatDockerfile(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printDockerfileFindings(_ report: DockerfileReport) {
        for finding in report.findings {
            print("[dockerfile scenario]   \(finding.severity): \(finding.claim.kind.rawValue) "
                + "`\(finding.claim.subject)` -> \(finding.explanation)")
        }
        print("[dockerfile scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let dockerfileScript = [
        """
        ```dockerfile
        ARG APP_VERSION=1.4.2
        FROM node:20-slim
        RUN mkdir -p /app
        RUN cd /app
        COPY package.json package-lock.json .
        RUN npm ci
        COPY src /app
        RUN echo "$APP_VERSION" > /app/VERSION
        ENV PORT=3000
        CMD ["node", "src/index.js", "--port", "$PORT"]
        ```
        `COPY src /app` keeps the folder, so `src/index.js` ends up at `/app/src/index.js`.
        """,
        """
        ```dockerfile
        ARG APP_VERSION=1.4.2
        FROM node:20-slim
        ARG APP_VERSION
        WORKDIR /app
        COPY package.json package-lock.json ./
        RUN npm ci
        COPY src ./src
        RUN echo "$APP_VERSION" > /app/VERSION
        ENV PORT=3000
        CMD ["sh", "-c", "node src/index.js --port $PORT"]
        ```
        `WORKDIR /app` creates `/app`, and `src/index.js` ends up at `/app/src/index.js`.
        """,
        """
        ```dockerfile
        FROM node:20 AS build
        ENV NODE_ENV=production
        WORKDIR /app
        COPY package.json package-lock.json ./
        RUN npm ci
        COPY src ./src
        FROM node:20-slim
        WORKDIR /app
        COPY --from=build /app /app
        CMD ["node", "src/index.js"]
        ```
        `ENV NODE_ENV` from the build stage is still set in the final stage, and `src/index.js` lands at \
        `/app/src/index.js`.
        """,
        """
        ```dockerfile
        FROM node:20-slim AS build
        ENV NODE_ENV=production
        WORKDIR /app
        COPY package.json package-lock.json ./
        RUN npm ci
        COPY src ./src
        FROM build
        CMD ["node", "src/index.js"]
        ```
        The final stage is built `FROM build`, so `ENV NODE_ENV` from the build stage is still set in the final \
        stage, and `src/index.js` lands at `/app/src/index.js`.
        """
    ]

    private static func dockerfileTurn(
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
