import ComposeMergeClaimKit
import ComposeVolumeClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-fifteenth scenario's turns bill against.
extension ProviderIdentifier {
    static let composeVolumeHost = ProviderIdentifier("compose-volume-host")
}

extension EcosystemDemo {
    /// The hundred-and-fifteenth scenario: what an answer says about compose volumes and bind mounts, checked
    /// against what Docker Compose and the engine do with them.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The question shows a `db` service on
    /// the named volume `pgdata` and a `web` service with the usual `.:/app` bind mount and an anonymous
    /// `/app/node_modules` volume, and asks whether `docker compose down` loses the database and why new npm
    /// packages never show up. The first answer says `down` deletes `pgdata` and that `up --build` refreshes the
    /// `node_modules` volume; `ComposeVolumeClaimKit` flags both, and the corrected answer holds. The follow-up asks
    /// to share the database volume with another project: the answer writes `external: true` next to `driver:
    /// local` and says compose creates a missing external volume, both wrong, while its name for the volume holds.
    /// After the feedback the file and the text hold. `ComposeMergeClaimKit` reads the same answers and stays quiet:
    /// none of this is about merging files. One `VolumeLedger` reviews the conversation.
    static func runComposeVolumeClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [ScriptedProvider(identifier: .composeVolumeHost,
                                                                     script: composeVolumeScript)])
            let ledger = VolumeLedger()
            let question = "Does `docker compose down` delete my Postgres data, and why don't new npm packages "
                + "show up after I rebuild?\n" + composeVolumeFile
            print("[volume scenario] user: \(flatVolume(question))")
            let first = try await composeVolumeTurn(question, router: router, meter: meter)
            print("[volume scenario] answer 1: \(flatVolume(first))")
            let mergeView = MergeClaimChecker().check(first, context: question)
            print("[volume scenario] ComposeMergeClaimKit on answer 1: \(mergeView.verdict.rawValue)")
            let report = await ledger.review(first, context: question)
            printVolumeFindings(report)

            let repair = question + "\n" + first + "\n" + report.corrections.joined(separator: " ")
            let second = try await composeVolumeTurn(repair, router: router, meter: meter)
            print("[volume scenario] answer 2 (after the feedback): \(flatVolume(second))")
            printVolumeFindings(await ledger.review(second, context: question))
            let scene = VolumeClaimChecker().scene(for: second, context: question)
            print("[volume scenario] no project name is shown, so `pgdata` is "
                + (scene.volumeName("pgdata") ?? "<project>_pgdata") + "; web mounts "
                + (scene.project?.service("web")?.mounts.map(\.kind.rawValue).joined(separator: " + ") ?? "nothing"))

            let followUp = "Can another compose project use the same database volume?"
            print("[volume scenario] user: \(followUp)")
            let third = try await composeVolumeTurn(followUp, router: router, meter: meter)
            print("[volume scenario] answer 3: \(flatVolume(third))")
            let sharing = await ledger.review(third, context: followUp)
            printVolumeFindings(sharing)

            let retry = followUp + "\n" + third + "\n" + sharing.corrections.joined(separator: " ")
            let fourth = try await composeVolumeTurn(retry, router: router, meter: meter)
            print("[volume scenario] answer 4 (after the feedback): \(flatVolume(fourth))")
            printVolumeFindings(await ledger.review(fourth, context: followUp))
            let statistics = await ledger.statistics
            print("[volume scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[volume scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[volume scenario] FAILED: \(error)")
        }
    }

    private static func flatVolume(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printVolumeFindings(_ report: VolumeReport) {
        for finding in report.findings {
            let fix = finding.correction.map { " " + $0 } ?? ""
            print("[volume scenario]   \(flatVolume(finding.claim.sentence)): \(finding.severity).\(fix)")
        }
        print("[volume scenario] verdict \(report.verdict.rawValue) (\(report.summary))")
    }

    private static let composeVolumeFile = """
    ```yaml
    services:
      db:
        image: postgres:18
        volumes:
          - pgdata:/var/lib/postgresql/data
      web:
        build: .
        volumes:
          - .:/app
          - /app/node_modules
    volumes:
      pgdata:
    ```
    """

    private static let composeVolumeScript = [
        """
        Yes: `docker compose down` deletes the `pgdata` volume, so back it up first. After \
        `docker compose up --build`, the `node_modules` volume gets the new packages from the image, so restart \
        the container.
        """,
        """
        No: named volumes such as `pgdata` survive `docker compose down`. The anonymous volume survives \
        `docker compose up --build`, so it still holds the old packages. Run `docker compose up --build -V` to \
        renew it.
        """,
        """
        Mark it external in both projects:
        ```yaml
        services:
          db:
            image: postgres:18
            volumes:
              - pgdata:/var/lib/postgresql/data
        volumes:
          pgdata:
            external: true
            driver: local
        ```
        With `external: true`, compose creates the volume if it doesn't exist, and `docker volume ls` will list \
        it as `pgdata`.
        """,
        """
        ```yaml
        services:
          db:
            image: postgres:18
            volumes:
              - pgdata:/var/lib/postgresql/data
        volumes:
          pgdata:
            external: true
        ```
        External volumes must exist before `docker compose up`; create it once with \
        `docker volume create pgdata`. `docker compose down -v` never removes an external volume.
        """
    ]

    private static func composeVolumeTurn(
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
