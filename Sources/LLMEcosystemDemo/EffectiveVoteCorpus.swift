import AbstentionPolicyAnswerability
import AbstentionPolicyKit
import AnswerabilityKit
import EffectiveVoteKit
import Foundation
import MorphologyMatchAnswerability
import MorphologyMatchKit
import SignalDependenceKit
import SourceIndependenceKit
import TemporalValidityKit

/// How one corpus in the forty-ninth scenario was built.
///
/// The label lives here rather than being read back off a judge. `isSafeToAnswer` is a fact about
/// how the corpus was *constructed*, so it cannot be contaminated by what any analyser said about
/// it — which is the only way a measured error correlation between those analysers means anything.
struct PanelSpec {
    let index: Int
    let twoSources: Bool
    let duplicateMirror: Bool
    let staleObservations: Int
    let fullCoverage: Bool
    let phrasing: Int
    /// Whether the corpus carries any observation at all. Without one the temporal analyser
    /// returns `noEvidence`, which becomes an abstention rather than an objection.
    let hasObservations: Bool

    var isSafeToAnswer: Bool {
        twoSources && staleObservations == 0 && fullCoverage && hasObservations
    }

    /// Every combination of the four axes, over two phrasings. Enumerated rather than sampled, so
    /// the panel history is identical on every machine and every run.
    static var all: [PanelSpec] {
        var specs: [PanelSpec] = []
        var index = 0
        for phrasing in 0..<2 {
            for twoSources in [false, true] {
                for duplicateMirror in [false, true] {
                    for stale in 0..<3 {
                        for fullCoverage in [false, true] {
                            for hasObservations in [false, true] {
                                specs.append(
                                    PanelSpec(
                                        index: index,
                                        twoSources: twoSources,
                                        duplicateMirror: duplicateMirror,
                                        staleObservations: stale,
                                        fullCoverage: fullCoverage,
                                        phrasing: phrasing,
                                        hasObservations: hasObservations
                                    )
                                )
                                index += 1
                            }
                        }
                    }
                }
            }
        }
        return specs
    }
}

extension EcosystemDemo {
    static let voteAsOf = Date(timeIntervalSince1970: 1_786_924_800)
    static let voteFresh = Date(timeIntervalSince1970: 1_786_800_000)
    static let voteStale = Date(timeIntervalSince1970: 1_600_000_000)
    static let voteRollback = SubjectKey("rollback-window")
    static let voteHealthCheck = SubjectKey("health-check")

    static let panelJudges: [JudgeIdentity] = ["answerability", "independence", "morphology", "temporal"]

    /// The declared graph scenario 37 uses, expressed as pairwise strengths so it can be held
    /// against measurement. Nothing here is invented for this scenario: both edges are the ones
    /// that scenario already builds.
    static func declaredPanelStrengths() -> [JudgePair: Double] {
        let heuristic = DependenceEdge("answerability", "morphology", mechanism: .sharedHeuristic)
        let sharedInput = DependenceEdge("independence", "temporal", mechanism: .sharedInput)
        return [
            JudgePair("answerability", "morphology"): heuristic.strength,
            JudgePair("independence", "temporal"): sharedInput.strength
        ]
    }

    static func voteCorpus(for spec: PanelSpec) -> AbstentionCorpus {
        let question = spec.phrasing == 0
            ? "how long is the rollback window after a failed health check"
            : "what is the rollback window when a health check fails"
        // When coverage is partial the evidence genuinely omits the health-check aspect, rather
        // than repeating a sentence that already covers it. Without that, the strict gate admits
        // every corpus, its votes never vary, and its measured correlation with anything is just
        // the label inverted - which is the artefact this package refuses to call a measurement.
        let evidence = spec.fullCoverage
            ? [
                EvidenceItem(id: "runbook", text: "The rollback window after a failed health check is two minutes."),
                EvidenceItem(id: "wiki", text: "A failed health check starts a rollback window of two minutes.")
            ]
            : [EvidenceItem(id: "runbook", text: "The rollback window is two minutes.")]
        return AbstentionCorpus(
            question: question,
            evidence: evidence,
            passages: votePassages(for: spec),
            observations: voteObservations(for: spec),
            catalog: VolatilityCatalog([voteRollback: .quarterly, voteHealthCheck: .quarterly])
        )
    }

    private static func votePassages(for spec: PanelSpec) -> [SourceIndependenceKit.Passage] {
        var passages = [
            Passage(
                id: "runbook",
                locator: "https://example.com/docs/rollback",
                text: "The rollback window after a failed health check is two minutes."
            )
        ]
        if spec.twoSources {
            passages.append(
                Passage(
                    id: "sre",
                    locator: "https://sre.example.com/runbooks/rollback",
                    text: "A failed health check opens a rollback window of two minutes."
                )
            )
        }
        if spec.duplicateMirror {
            passages.append(
                Passage(
                    id: "mirror",
                    locator: "https://example.com/docs/rollback?utm_source=newsletter",
                    text: "The rollback window after a failed health check is two minutes."
                )
            )
        }
        return passages
    }

    private static func voteObservations(for spec: PanelSpec) -> [EvidenceObservation] {
        guard spec.hasObservations else { return [] }
        return [
            EvidenceObservation(
                id: "runbook",
                subject: voteRollback,
                observedAt: spec.staleObservations >= 1 ? voteStale : voteFresh
            ),
            EvidenceObservation(
                id: "sre",
                subject: voteHealthCheck,
                observedAt: spec.staleObservations >= 2 ? voteStale : voteFresh
            )
        ]
    }

    /// Runs the four judges scenario 37 counts, and turns each reading into one vote.
    ///
    /// The mapping keeps `unavailable` as an abstention rather than folding it into a `deny`. A
    /// judge that could not form a view has not objected, and counting it as an objection would
    /// invent agreement with every judge that did.
    static func panelObservation(for spec: PanelSpec) -> PanelObservation {
        let corpus = voteCorpus(for: spec)
        let strict = AnswerabilityEngine().assess(Question(corpus.question), against: corpus.evidence)
        let lenient = AnswerabilityEngine(policy: .lenient, matcher: MorphologyEvidenceMatcher())
            .assess(Question(corpus.question), against: corpus.evidence)
        let independence = SourceIndependenceAnalyzer().analyse(corpus.passages)
        let temporal = TemporalValidityAnalyzer(catalog: corpus.catalog)
            .assess(corpus.observations, asOf: voteAsOf)

        let verdicts: [JudgeIdentity: Verdict] = [
            "answerability": vote(for: AnswerabilitySignalMapper().signal(for: strict).reading),
            "morphology": vote(for: AnswerabilitySignalMapper().signal(for: lenient).reading),
            "independence": vote(for: independenceReading(independence)),
            "temporal": vote(for: voteTemporalReading(temporal))
        ]
        return PanelObservation(
            id: String(format: "corpus-%02d", spec.index),
            verdicts: verdicts,
            truth: spec.isSafeToAnswer ? .affirm : .deny
        )
    }

    static func panelHistory() -> ObservationHistory {
        ObservationHistory(PanelSpec.all.map(panelObservation(for:)))
    }

    private static func vote(for reading: SignalReading) -> Verdict {
        if reading.isClear { return .affirm }
        if reading.isRefusal || reading.concernSeverity != nil { return .deny }
        return .abstain
    }

    private static func independenceReading(_ report: IndependenceReport) -> SignalReading {
        report.mergedPassageCount > 0
            ? .concern(.low, "\(report.mergedPassageCount) merged into \(report.establishedSourceCount)")
            : .clear
    }

    private static func voteTemporalReading(_ assessment: TemporalAssessment) -> SignalReading {
        switch assessment.standing {
        case .current: return .clear
        case let .mixed(entitled, stale): return .concern(.low, "\(stale) of \(entitled + stale) stale")
        case let .whollyStale(count): return .refuse("all \(count) passages are stale")
        case let .undetermined(reason): return .unavailable("\(reason)")
        case .noEvidence: return .unavailable("no observations offered")
        }
    }
}
