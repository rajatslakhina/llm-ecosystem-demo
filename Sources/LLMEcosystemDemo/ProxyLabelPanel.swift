import EffectiveVoteKit
import Foundation
import ProxyLabelKit

/// Scenario 49's panel with its construction label replaced by one a running system could
/// actually have derived.
///
/// Both the flipped history and the labels that produced it are kept, because the whole point is
/// to hold the two against each other: the history is what `EffectiveVoteKit` would have measured,
/// and the labels are what `ProxyLabelKit` prices.
struct ProxyLabelledPanel {
    let history: ObservationHistory
    let proposals: [LabelProposal]
    /// Items where the downstream outcome disagreed with how the corpus was built.
    let flippedItems: Int
    /// The construction label per item, kept only so the audit has something to check against.
    let constructionTruth: [ItemID: Verdict]

    /// A hand-checked subset: the first `limit` proposals, with the construction label as truth.
    ///
    /// A real audit is somebody reading items. Here it is the construction label, which is the
    /// only honest stand-in — and it is deliberately a *subset*, because pricing a proxy against
    /// every item would mean already having the labels the proxy exists to replace.
    func auditSample(limit: Int) -> AuditSample {
        let entries = proposals.prefix(limit).compactMap { proposal -> AuditedLabel? in
            guard let truth = constructionTruth[proposal.item] else { return nil }
            guard let verdict = verdicts[proposal.item]?[proposal.judge], verdict.isCast else { return nil }
            let erred = verdict != truth
            return AuditedLabel(
                judge: proposal.judge,
                item: proposal.item,
                proxy: proposal.label,
                truth: erred ? .incorrect : .correct
            )
        }
        return AuditSample(entries: Array(entries))
    }

    /// Each judge's verdict, kept so the audit can work out whether that judge actually erred.
    let verdicts: [ItemID: [JudgeID: Verdict]]
}

extension EcosystemDemo {
    /// Replaces each item's construction label with one derived from a downstream outcome that is
    /// wrong `flipRate` of the time.
    ///
    /// The flip is applied to the **item**, not to a judge, because that is how a real outcome
    /// arrives: one later contradiction is evidence about the answer, and every judge that ruled
    /// on that answer inherits it at once.
    static func proxyLabelledHistory(
        from source: ObservationHistory,
        flipRate: Double,
        seed: UInt64 = 20_260_902
    ) -> ProxyLabelledPanel {
        var rng = ProxyFlipSequence(seed: seed)
        var observations: [PanelObservation] = []
        var judgements: [Judgement] = []
        var signals: [OutcomeSignal] = []
        var constructionTruth: [ItemID: Verdict] = [:]
        var verdicts: [ItemID: [JudgeID: Verdict]] = [:]
        var flipped = 0

        for observation in source.observations {
            guard let truth = observation.truth, truth.isCast else { continue }
            let item = ItemID(observation.id)
            constructionTruth[item] = truth
            let flip = rng.nextUnit() < flipRate
            if flip { flipped += 1 }
            let reported: Verdict = flip ? (truth == .affirm ? .deny : .affirm) : truth

            observations.append(
                PanelObservation(id: observation.id, verdicts: observation.verdicts, truth: reported)
            )
            signals.append(
                OutcomeSignal(
                    item: item,
                    kind: .laterContradiction,
                    scope: .item,
                    indicatesFailure: reported == .deny
                )
            )
            for judge in observation.judges {
                guard let verdict = observation.verdict(of: judge), verdict.isCast else { continue }
                let judgeID = JudgeID(judge.rawValue)
                verdicts[item, default: [:]][judgeID] = verdict
                judgements.append(Judgement(judge: judgeID, item: item, affirmed: verdict == .affirm))
            }
        }

        return ProxyLabelledPanel(
            history: ObservationHistory(observations),
            proposals: ContradictionLabeler().propose(judgements: judgements, signals: signals),
            flippedItems: flipped,
            constructionTruth: constructionTruth,
            verdicts: verdicts
        )
    }
}

/// A deterministic sequence, so the fiftieth scenario prints the same numbers everywhere.
struct ProxyFlipSequence {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= (z >> 31)
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
