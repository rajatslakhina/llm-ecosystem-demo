import AbstentionPolicyAnswerability
import AbstentionPolicyKit
import AnswerabilityKit
import ConformalGateKit
import Foundation
import SourceIndependenceKit
import TemporalValidityKit

extension EcosystemDemo {
    /// Three instants at which the same corpus is a different turn.
    ///
    /// Time is the one axis on which these corpora genuinely vary: the temporal judge reads the
    /// same passages differently as their observations age past a quarterly window. Asking the
    /// same question at a later instant is not a synthetic variation — it is the case this stack
    /// has been building gates for since scenario 35.
    static let conformalInstants: [Date] = [
        Date(timeIntervalSince1970: 1_786_850_000),
        Date(timeIntervalSince1970: 1_790_000_000),
        Date(timeIntervalSince1970: 1_795_000_000)
    ]

    /// Ninety days, restated here as arithmetic rather than read off a judge.
    private static let conformalWindow: TimeInterval = 90 * 24 * 60 * 60

    /// The two corpora, at one instant. What thirty-seven scenarios of judging actually labelled.
    static func conformalAsBuilt() -> [CalibrationPoint] {
        Self.conformalCorpora.map { name, corpus in
            Self.conformalPoint(id: "\(name)-full", corpus: corpus, stratum: name, asOf: conformalInstants[1])
        }
    }

    /// Every non-empty subset of each corpus, asked at each instant.
    ///
    /// A subset is a real turn: retrieval returning two of three passages is the ordinary case,
    /// not a contrivance. Each one is put through the same three analysers the rest of this demo
    /// uses, and nothing about the score is written by hand.
    static func conformalCalibration() -> [CalibrationPoint] {
        var points: [CalibrationPoint] = []
        for (name, corpus) in Self.conformalCorpora {
            for subset in Self.conformalSubsets(of: corpus.passages.map(\.id)) {
                for (index, instant) in conformalInstants.enumerated() {
                    let label = subset.sorted().joined(separator: "+")
                    points.append(
                        Self.conformalPoint(
                            id: "\(name)-\(label)-t\(index)",
                            corpus: corpus.retaining(subset),
                            stratum: name,
                            asOf: instant
                        )
                    )
                }
            }
        }
        return points
    }

    private static var conformalCorpora: [(String, AbstentionCorpus)] {
        [("strong", Self.strongCorpus), ("weak", Self.weakCorpus)]
    }

    private static func conformalSubsets(of ids: [String]) -> [Set<String>] {
        guard !ids.isEmpty else { return [] }
        return (1..<(1 << ids.count)).map { mask in
            Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        }
    }

    private static func conformalPoint(
        id: String,
        corpus: AbstentionCorpus,
        stratum: String,
        asOf: Date
    ) -> CalibrationPoint {
        CalibrationPoint(
            id: id,
            score: Self.conformalScore(Self.conformalSignals(for: corpus, asOf: asOf)),
            wasWrong: Self.conformalAnsweringWasWrong(corpus, asOf: asOf),
            stratum: Stratum(stratum)
        )
    }

    /// Ground truth, and the reason it is computed here rather than asked of a judge.
    ///
    /// Answering is wrong when no retained observation is demonstrably current — the turn would
    /// state a figure from evidence entirely out of date, or from no evidence at all. That is
    /// decided by subtracting two dates, not by `TemporalValidityAnalyzer`, which is one of the
    /// three judges being calibrated. A calibration set graded by the gate it is protecting
    /// certifies nothing: it measures the gate's agreement with itself, which is 100% by
    /// construction.
    static func conformalAnsweringWasWrong(_ corpus: AbstentionCorpus, asOf: Date) -> Bool {
        let ages = corpus.observations.compactMap(\.observedAt).map { asOf.timeIntervalSince($0) }
        return !ages.contains { $0 <= Self.conformalWindow }
    }

    /// The three judges this demo already owns, at a given instant.
    static func conformalSignals(for corpus: AbstentionCorpus, asOf: Date) -> [AbstentionSignal] {
        let report = AnswerabilityEngine().assess(Question(corpus.question), against: corpus.evidence)
        let independence = SourceIndependenceAnalyzer().analyse(corpus.passages)
        let assessment = TemporalValidityAnalyzer(catalog: corpus.catalog)
            .assess(corpus.observations, asOf: asOf)
        return [
            AnswerabilitySignalMapper().signal(for: report),
            AbstentionSignal(
                origin: SignalOrigin("independence"),
                reading: independence.mergedPassageCount > 0
                    ? .concern(.low, "\(independence.mergedPassageCount) merged into "
                        + "\(independence.establishedSourceCount)")
                    : .clear
            ),
            AbstentionSignal(origin: SignalOrigin("temporal"), reading: Self.conformalTemporal(assessment))
        ]
    }

    /// A nonconformity score, derived from what the judges returned and nothing else.
    ///
    /// Higher is more suspect, which is the direction every conformal result is stated in. A
    /// refusal is the top of the scale; `unavailable` sits above a low concern because a judge
    /// that could not rule tells you less than one that ruled and found something small.
    static func conformalScore(_ signals: [AbstentionSignal]) -> Double {
        guard !signals.isEmpty else { return 1 }
        let total = signals.reduce(0.0) { $0 + Self.conformalWeight($1.reading) }
        return total / Double(signals.count)
    }

    private static func conformalWeight(_ reading: SignalReading) -> Double {
        if reading.isRefusal { return 1.0 }
        if reading.isUnavailable { return 0.6 }
        if let severity = reading.concernSeverity { return 0.4 + 0.1 * Double(severity.rawValue) }
        return 0.0
    }

    private static func conformalTemporal(_ assessment: TemporalAssessment) -> SignalReading {
        switch assessment.standing {
        case .current: return .clear
        case .mixed(let entitled, let stale): return .concern(.low, "\(stale) of \(entitled + stale) stale")
        case .whollyStale(let count): return .refuse("all \(count) passages are stale")
        case .undetermined(let reason): return .unavailable("\(reason)")
        case .noEvidence: return .unavailable("no observations offered")
        }
    }

    static func conformalPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

extension AbstentionCorpus {
    /// The same turn with only some of its passages retrieved — the ordinary case, not a fault.
    func retaining(_ ids: Set<String>) -> AbstentionCorpus {
        AbstentionCorpus(
            question: question,
            evidence: evidence.filter { ids.contains($0.id) },
            passages: passages.filter { ids.contains($0.id) },
            observations: observations.filter { ids.contains($0.id) },
            catalog: catalog
        )
    }
}
