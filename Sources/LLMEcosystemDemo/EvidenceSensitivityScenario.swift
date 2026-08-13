import AnswerabilityKit
import EvidenceSensitivityAnswerability
import EvidenceSensitivityKit
import Foundation
import MorphologyMatchAnswerability
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the thirty-third scenario bills its one *stable* hop against.
extension ProviderIdentifier {
    static let sensitivityHost = ProviderIdentifier("sensitivity-host")
}

/// A retrieved passage and the document it was cut from.
///
/// A named type rather than a tuple because the document is the whole point of this scenario,
/// and `$0.1` at a call site is exactly how provenance gets dropped by accident.
struct SensitivityPassage {
    let id: String
    let document: String
    let text: String
}

extension EcosystemDemo {
    /// The thirty-third scenario: **an admission is not the same as a stable admission.**
    ///
    /// Scenario 31 put `AnswerabilityKit` in front of the money. Scenario 32 found the gate's
    /// refusals were only as good as its matcher's recall, and swapping in `MorphologyMatchKit`
    /// turned a wrong refusal into a correct admission. Both end with the gate saying yes, and
    /// neither asks the follow-up: **yes on the strength of what?**
    ///
    /// Two retrieval outcomes, same question, same gate, same matcher. In A the answer survives
    /// losing any passage *and* any document. In B retrieval happened to return only chunks of the
    /// runbook, the gate reports the identical `answerable` at the identical strength, and the only
    /// thing separating the two is provenance the gate never looks at.
    ///
    /// The cost line is scenario 32's mirror. There a false refusal was free, so the meter made an
    /// over-refusing gate look cheap. Here the hop is spent **only** on `robust`, so the meter
    /// records not "an answer" but "an answer worth paying for".
    static func runEvidenceSensitivityScenario(meter: TokenMeter) async {
        let question = "which requests were retried"
        print("[sensitivity scenario] Q: \(question)")
        let analyzer = SensitivityAnalyzer(policy: .standard)

        print("  A. retrieval returned three passages from two documents")
        await Self.assess(question: question, corpus: Self.broadCorpus, analyzer: analyzer, meter: meter)

        print("  B. same question, same gate — retrieval returned the runbook only")
        await Self.assess(question: question, corpus: Self.thinCorpus, analyzer: analyzer, meter: meter)

        await Self.describeTally(analyzer)
    }

    /// Scenario 32's corpus, with the provenance a passage list leaves out.
    ///
    /// The first two entries are chunks of one runbook. Nothing in the evidence *text* says so,
    /// which is the whole problem: provenance has to be carried alongside, or a gate counts chunks
    /// and calls it corroboration.
    private static var broadCorpus: [SensitivityPassage] {
        [
            SensitivityPassage(
                id: "doc-retry-policy",
                document: "runbook",
                text: "Retry policies apply to idempotent request handlers only."
            ),
            SensitivityPassage(
                id: "doc-retry-client",
                document: "runbook",
                text: "The client retries a request when the provider returns 429."
            ),
            SensitivityPassage(
                id: "doc-retry-budget",
                document: "deadlines",
                text: "Each retry spends from the same deadline budget as the first."
            )
        ]
    }

    /// The same question on a thinner day. Both passages are the runbook.
    private static var thinCorpus: [SensitivityPassage] {
        Array(broadCorpus.prefix(2))
    }

    private static func refs(_ corpus: [SensitivityPassage]) -> [EvidenceRef] {
        corpus.map { EvidenceRef(id: $0.id, documentID: $0.document) }
    }

    /// The gate exactly as scenario 32 left it: lenient policy, morphology matcher.
    private static func probe(
        question: String,
        corpus: [SensitivityPassage]
    ) -> AnswerabilityVerdictProbe {
        AnswerabilityVerdictProbe(
            engine: AnswerabilityEngine(policy: .lenient, matcher: MorphologyEvidenceMatcher()),
            question: Question(question),
            corpus: corpus.map { EvidenceItem(id: $0.id, text: $0.text) }
        )
    }

    private static func assess(
        question: String,
        corpus: [SensitivityPassage],
        analyzer: SensitivityAnalyzer,
        meter: TokenMeter
    ) async {
        let judge = Self.probe(question: question, corpus: corpus)
        let evidence = Self.refs(corpus)
        let reading = judge.reading(over: evidence)
        let documents = Set(corpus.map(\.document)).sorted().joined(separator: ",")
        print(String(format: "    gate verdict    %@ (affirm %.2f / deny %.2f) over %d passage(s) from %@",
                     reading.label, reading.affirming, reading.denying, corpus.count, documents))

        let report = await analyzer.analyse(evidence: evidence, using: judge)
        Self.describeStability(report)
        await Self.spendOnlyIfStable(report, meter: meter)
    }

    private static func describeStability(_ report: SensitivityReport) {
        print("    stability       \(Self.stabilityLabel(report.verdict))")
        let items = report.itemPivots.isEmpty ? "none" : report.itemPivots.joined(separator: ",")
        let documents = report.documentPivots
            .map { $0.isEmpty ? "none" : $0.joined(separator: ",") } ?? "not asked (one document)"
        print("    pivots          passages: \(items)   documents: \(documents)")
        print(String(format: "    margin %.2f, judge re-run %d times to find out",
                     report.supportMargin, report.probeCount))
    }

    /// The hop, spent only against a verdict that survived its own evidence being taken apart.
    private static func spendOnlyIfStable(_ report: SensitivityReport, meter: TokenMeter) async {
        guard let label = report.trustedLabel else {
            print("    cost            $0 — not stable enough to spend on, routed to review")
            return
        }
        let prompt = "Summarise the retry behaviour (\(label))"
        do {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .sensitivityHost, script: [
                    "Idempotent request handlers are retried after a 429, within the original deadline budget."
                ])
            ])
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: prompt.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.sensitivityHost.rawValue
            )
            print("    cost            paid — routed via \(response.providerID)")
        } catch {
            print("    cost            hop failed: \(error)")
        }
    }

    private static func describeTally(_ analyzer: SensitivityAnalyzer) async {
        let stats = await analyzer.statistics()
        let rate = stats.trustworthyRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("  measured \(stats.measured), refused \(stats.undetermined), worth paying for: \(rate)")
    }

    private static func stabilityLabel(_ verdict: StabilityVerdict) -> String {
        switch verdict {
        case .robust:
            return "robust"
        case let .pivotal(items, documents):
            return "pivotal(\(items.count) passage(s), \(documents.count) document(s))"
        case let .knifeEdge(margin):
            return String(format: "knifeEdge(%.2f from the threshold)", margin)
        case let .coincidental(reason):
            return "coincidental(\(Self.coincidenceLabel(reason)))"
        case .undetermined:
            return "undetermined — refused to measure"
        }
    }

    private static func coincidenceLabel(_ reason: CoincidenceReason) -> String {
        switch reason {
        case let .offsettingWeakness(affirming, denying):
            return String(format: "two weak sides: %.2f vs %.2f", affirming, denying)
        case let .singleDocumentCorroboration(documentID, passages):
            return "\(passages) passages, all from \(documentID)"
        }
    }
}
