import Foundation
import PackageClaimKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the ninety-seventh scenario's turns bill against.
extension ProviderIdentifier {
    static let packageClaimHost = ProviderIdentifier("package-claim-host")
}

extension EcosystemDemo {
    /// The ninety-seventh scenario: the packages an answer tells someone to install.
    ///
    /// `ProviderGatewayKit` carries three turns and `TokenMeterKit` meters them. The first answer's
    /// `pip install` names a package that does not exist (`reqeusts`) and pins a `tenacity` that was never
    /// released; `PackageClaimKit` finds both against a registry snapshot, and its feedback gets a rewrite
    /// that installs. The third answer names a package first published six days ago, which is a note for
    /// the user, not a re-prompt. One `PackageVetter` serves the conversation, so names it has already
    /// looked up are answered from memory.
    static func runPackageClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .packageClaimHost, script: packageClaimScript)
            ])
            let vetter = PackageVetter(registry: StaticRegistry(packageSnapshot))
            let now = (try? Date("2026-10-29T00:00:00Z", strategy: .iso8601)) ?? Date()
            let question = "What do I install to call a flaky REST API from my FastAPI service, with retries?"
            print("[package claim scenario] user: \(question)")
            let first = try await packageClaimTurn(question, router: router, meter: meter)
            let report = await vetter.review(first, now: now)
            print("[package claim scenario] answer 1: \(first.replacingOccurrences(of: "\n", with: " ⏎ "))")
            printPackageFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await packageClaimTurn(repair, router: router, meter: meter)
            let fixed = await vetter.review(second, now: now)
            print("[package claim scenario] answer 2 (after the feedback): "
                + second.replacingOccurrences(of: "\n", with: " ⏎ "))
            print("[package claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); "
                + "the app shows answer 2")

            let followUp = "And for JWT auth?"
            print("[package claim scenario] user: \(followUp)")
            let third = try await packageClaimTurn(followUp, router: router, meter: meter)
            let fresh = await vetter.review(third, now: now)
            print("[package claim scenario] answer 3: \(third)")
            printPackageFindings(fresh)
            print("[package claim scenario] session: \(await vetter.reviews) reviews, \(await vetter.lookups) registry "
                + "lookups, \(await vetter.cacheHits) answered from memory")
            print("[package claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[package claim scenario] FAILED: \(error)")
        }
    }

    private static func printPackageFindings(_ report: PackageReport) {
        for finding in report.findings {
            print("[package claim scenario]   \(finding.severity): \(finding.sentence)")
        }
        print("[package claim scenario] verdict \(report.verdict.rawValue); note: \(report.note ?? "-")")
        print("[package claim scenario] feedback: \(report.feedback ?? "-")")
    }

    /// First-publish dates and latest versions as PyPI and npm returned them on 2026-10-29, version lists
    /// cut to what the turns use. `fastapi-jwt-shield` is made up: it stands for a name an attacker
    /// registered after models started suggesting it.
    private static var packageSnapshot: [PackageFacts] {
        func day(_ text: String) -> Date { (try? Date(text + "T00:00:00Z", strategy: .iso8601)) ?? .distantPast }
        return [
            PackageFacts(ecosystem: .pypi, name: "fastapi", firstPublished: day("2018-12-08"),
                         latestVersion: "0.162.0", versions: ["0.162.0"]),
            PackageFacts(ecosystem: .pypi, name: "requests", firstPublished: day("2011-02-14"),
                         latestVersion: "2.34.2", versions: ["2.32.3", "2.34.2"]),
            PackageFacts(ecosystem: .pypi, name: "tenacity", firstPublished: day("2016-08-25"),
                         latestVersion: "9.2.1", versions: ["9.2.1"]),
            PackageFacts(ecosystem: .pypi, name: "pyjwt", firstPublished: day("2011-02-24"),
                         latestVersion: "2.15.1", versions: ["2.15.1"]),
            PackageFacts(ecosystem: .pypi, name: "fastapi-jwt-shield", firstPublished: day("2026-10-23"),
                         latestVersion: "0.0.1", versions: ["0.0.1"]),
            PackageFacts(ecosystem: .npm, name: "lodash", firstPublished: day("2012-04-23"),
                         latestVersion: "4.18.1", versions: ["4.17.21", "4.18.1"])
        ]
    }

    private static let packageClaimScript = [
        "Install the client and a retry library:\n```bash\npip install fastapi reqeusts tenacity==9.3.0\n```",
        "Corrected:\n```bash\npip install fastapi requests tenacity==9.2.1\n```",
        "Use PyJWT, or the FastAPI wrapper: `pip install pyjwt fastapi-jwt-shield`."
    ]

    private static func packageClaimTurn(
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
