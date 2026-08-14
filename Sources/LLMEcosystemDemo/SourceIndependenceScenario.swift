import EvidenceSensitivityKit
import Foundation
import ProviderGatewayKit
import SourceIndependenceKit
import SourceIndependenceSensitivity
import TokenMeterKit

/// The identifier the thirty-fourth scenario bills its one *authorised* hop against.
extension ProviderIdentifier {
    static let independenceHost = ProviderIdentifier("independence-host")
}

extension EcosystemDemo {
    /// The thirty-fourth scenario: **scenario 33's rule, applied to provenance nobody supplied.**
    ///
    /// Scenario 33 established the rule this ecosystem now spends money by: pay for a verdict only
    /// if it survives its own evidence being taken apart. To apply that rule it needed to know which
    /// document each passage came from, and it knew because `SensitivityPassage` carries a
    /// hand-written `document` field. Its own doc comment says so — *provenance has to be carried
    /// alongside.*
    ///
    /// Carried from where? A real retriever returns URLs. This scenario runs the identical corpus,
    /// question and judge twice, changing nothing but where the document identifier comes from:
    /// once the way a caller without one reaches for the passage id, and once with the key derived
    /// by `SourceIndependenceKit`.
    ///
    /// The first pass earns `robust` and, under scenario 33's rule, **authorises the hop**. Three of
    /// its four passages are one page reached three ways. The rule is sound; the input to it was not.
    static func runSourceIndependenceScenario(meter: TokenMeter) async {
        let question = "how long does a failed deployment take to roll back"
        print("[independence scenario] Q: \(question)")

        let corpus = Self.retrievedWithoutDocumentIDs
        let mapper = IndependenceEvidenceMapper()
        let probe = RollbackProbe()
        let analyzer = SensitivityAnalyzer(policy: .standard)

        print("  A. document id taken from the passage id, the way a caller without one does")
        await Self.judge(
            refs: mapper.naiveEvidenceRefs(for: corpus),
            independence: nil,
            probe: probe,
            analyzer: analyzer,
            meter: meter
        )

        print("  B. document key derived from the locators, lineage and text")
        let report = SourceIndependenceAnalyzer().analyse(corpus)
        if let derived = mapper.evidenceRefs(from: report, passages: corpus) {
            await Self.judge(refs: derived, independence: report, probe: probe, analyzer: analyzer, meter: meter)
        }

        print("  the independence pass reads no model and costs nothing. It is the only thing")
        print("  standing between this ecosystem's own spending rule and a fabricated stability.")
    }

    /// Four passages as a retriever hands them over: no document identifiers, only URLs.
    ///
    /// `r1`, `r2` and `r3` are one page. Nothing in their text says so and nothing in their
    /// identifiers says so — the tracking parameters, the AMP copy and the `index.html` are three
    /// ordinary ways one document ends up in a result set three times.
    private static var retrievedWithoutDocumentIDs: [SourceIndependenceKit.Passage] {
        [
            Passage(
                id: "r1",
                locator: "https://www.example.com/docs/rollback?utm_source=slack&utm_campaign=q3",
                text: "A failed deployment is rolled back automatically within two minutes of the health check failing."
            ),
            Passage(
                id: "r2",
                locator: "http://example.com/docs/rollback/amp#timing",
                text: "The rollback is triggered by the health check rather than by the engineer who is on call."
            ),
            Passage(
                id: "r3",
                locator: "https://example.com/docs/rollback/index.html",
                text: "Operators are paged only in the case where the automatic rollback has itself failed to complete."
            ),
            Passage(
                id: "r4",
                locator: "https://status.example.com/incidents/41",
                text: "Incident 41 was closed once the platform reported the revert as finished."
            )
        ]
    }

    private static func judge(
        refs: [EvidenceRef],
        independence: IndependenceReport?,
        probe: RollbackProbe,
        analyzer: SensitivityAnalyzer,
        meter: TokenMeter
    ) async {
        let documents = refs.orderedDocuments()
        if let independence {
            print("    independence    \(independence.summary)")
            for source in independence.sources where !source.isSinglePassage {
                print("      merged        \(source.summary)")
            }
        } else {
            print("    independence    not asked")
        }
        print("    documents       \(documents.count) — \(documents.joined(separator: ", "))")
        let report = await analyzer.analyse(evidence: refs, using: probe)
        print("    stability       \(Self.independenceStabilityLabel(report.verdict))")
        await Self.spendIfAuthorised(report, meter: meter)
    }

    /// Scenario 33's rule, unchanged: the hop is spent only against a verdict that survived.
    private static func spendIfAuthorised(_ report: SensitivityReport, meter: TokenMeter) async {
        guard let label = report.trustedLabel else {
            print("    cost            $0 — not stable enough to spend on, routed to review")
            return
        }
        let prompt = "Summarise the rollback timing (\(label))"
        do {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .independenceHost, script: [
                    "A failed deployment reverts automatically within two minutes of a failing health check."
                ])
            ])
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: prompt.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.independenceHost.rawValue
            )
            print("    cost            paid — routed via \(response.providerID)")
        } catch {
            print("    cost            hop failed: \(error)")
        }
    }

    private static func independenceStabilityLabel(_ verdict: StabilityVerdict) -> String {
        switch verdict {
        case .robust:
            return "robust — authorised to spend"
        case let .pivotal(items, documents):
            let names = documents.isEmpty ? "none" : documents.joined(separator: ",")
            return "pivotal(\(items.count) passage(s), documents: \(names))"
        case let .knifeEdge(margin):
            return String(format: "knifeEdge(%.2f from the threshold)", margin)
        case .coincidental:
            return "coincidental — holds, but not for the reason it appears to"
        case .undetermined:
            return "undetermined — refused to measure"
        }
    }
}

/// A judge of the shape this ecosystem keeps building: max-pool the strongest passage.
///
/// Max-pooling is precisely why chunking fools it. Three chunks of one page and one chunk of one
/// page produce the identical affirming score, so nothing in the reading distinguishes them.
struct RollbackProbe: VerdictProbing {
    private let affirming: [String: Double] = ["r1": 0.90, "r2": 0.70, "r3": 0.65, "r4": 0.20]

    func reading(over evidence: [EvidenceRef]) -> VerdictReading {
        let best = evidence.compactMap { affirming[$0.id] }.max() ?? 0
        return VerdictReading(label: best >= 0.4 ? "answerable" : "insufficient", affirming: best, denying: 0)
    }
}
