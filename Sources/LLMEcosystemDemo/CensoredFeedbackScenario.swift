import AbstentionPolicyAnswerability
import AbstentionPolicyKit
import AnswerabilityKit
import CensoredFeedbackConformal
import CensoredFeedbackKit
import ConformalGateKit
import Foundation
import MorphologyMatchAnswerability
import MorphologyMatchKit
import SignalDependenceAbstention
import SignalDependenceKit
import TokenMeterKit

extension EcosystemDemo {
    /// The thirty-ninth scenario: **where did scenario 38's labels come from?**
    ///
    /// Scenario 38 built a calibration set by enumerating every non-empty subset of each corpus at
    /// three instants and grading each one by subtracting two dates. Thirty turns, every one
    /// labelled — a completeness no deployed gate has ever had. In production a label exists only
    /// for a turn that was *answered*: a turn this stack refused was never sent, never verified and
    /// never graded, so it cannot be in the set the gate is calibrated on.
    ///
    /// This scenario asks the arbiter which of those thirty turns it would actually have let
    /// through, deletes the labels it would never have obtained, and re-reads yesterday's
    /// certificate against what is left.
    static func runCensoredFeedbackScenario(meter: TokenMeter) async {
        print("[censored feedback scenario] which of yesterday's labels would this stack ever have had?")
        let gate = ConformalGate(budget: .oneInTwenty)
        let outcome = gate.certify(Self.conformalCalibration())
        print("  certificate     \(outcome.summary)")
        let threshold = outcome.certificate?.threshold

        await Self.censoredNestedPanel(threshold: threshold)
        let audit = await Self.censoredWidePanel(threshold: threshold)
        guard let audit else { return }
        Self.printCensoredQualification(outcome: outcome, audit: audit)
        await Self.spendWithdrawnGate(outcome: outcome, audit: audit, meter: meter)
        print("  A guarantee computed over the traffic a gate admitted is a guarantee about the")
        print("  easy half of its own traffic. The arithmetic is right and the population is wrong.")
    }

    // MARK: - A: the three judges the score is made of

    /// The nested case, and it is not a happy one.
    private static func censoredNestedPanel(threshold: Double?) async {
        print("  A. the three judges scenario 36 ruled on — the same three the score is built from")
        let log = await Self.censoredFeedbackLog(threshold: threshold, wide: false)
        guard let auditor = try? CensoringAuditor(lossBound: 1, budget: 0.05),
              let audit = try? auditor.audit(log) else { return }
        Self.printCensoredCounts(audit)
        print("    Nothing censored, and that is not reassurance. The nonconformity score is")
        print("    computed from these same three readings, so a turn they refuse sits at the top of")
        print("    the scale by construction and the gate would never have answered it either. Every")
        print("    refusal is pinned at zero and none is unknown. A certificate whose admissions are")
        print("    a function of the arbiter's own inputs is measuring itself — scenario 37's")
        print("    finding, one level up, and the reason this demo cannot manufacture censoring.")
    }

    // MARK: - B: a judge the score cannot see

    private static func censoredWidePanel(threshold: Double?) async -> CensoringAudit? {
        print("  B. the same four judges, ruled on after signalDependence merges them")
        let log = await Self.censoredFeedbackLog(threshold: threshold, wide: true)
        guard let auditor = try? CensoringAuditor(lossBound: 1, budget: 0.05),
              let audit = try? auditor.audit(log) else {
            print("    the decision log could not be audited — see CensoringError")
            return nil
        }
        Self.printCensoredCounts(audit)
        for stratum in audit.strata {
            let name = stratum.stratum.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
            print("    \(name)\(stratum.profile.summary)")
        }
        for blind in audit.unknowableStrata {
            print("    blind corpus    '\(blind.stratum.rawValue)' — never once answered, so its bound is the")
            print("                    whole range, and no estimator reaches inside it.")
        }
        print("    The app's real pipeline order: signalDependence merges entangled voices before")
        print("    the arbiter counts them, and admission moves — two more turns answered, and the")
        print("    observed risk falls from 0.2000 to 0.1765 on a population that has not changed.")
        print("    It still censors nothing, and the direction is why: merging can only remove a")
        print("    concurring voice, so it loosens here rather than refusing anything new.")
        print("    Censoring needs a gate that refuses for a reason the score cannot see, and every")
        print("    judge in this panel feeds the score. The app in this series has four such gates")
        print("    and does produce it; this demo, honestly, does not.")
        return audit
    }

    private static func printCensoredCounts(_ audit: CensoringAudit) {
        let profile = audit.profile
        let observed = profile.observedRisk.map { String(format: "%.4f", $0) } ?? "n/a"
        print("    answered        \(profile.observedCount) of \(profile.recordCount)"
            + " — the only turns a label could ever exist for")
        print("    pinned at zero  \(profile.determinedCount) — refused, and above the threshold anyway")
        print("    unlabelled      \(profile.censoredCount) — refused below it: the loss is unknown")
        print("    observed risk   \(observed) — the number a calibration set reports")
        print("    bounds          \(profile.bounds.summary) — what the log actually leaves possible")
        print("    diagnosis       \(profile.diagnosis)")
    }

    // MARK: - C: reading the certificate against the log

    private static func printCensoredQualification(outcome: CertificationOutcome, audit: CensoringAudit) {
        print("  C. yesterday's certificate, read against the log it would really have had")
        let support = CertificateQualifier().qualify(outcome, against: audit)
        print("    support         \(support.summary)")
        print("    enforce on it   \(support.allowsEnforcement)")
        print("    price of knowing  \(audit.exploration.summary)")
        print("    The bias here runs the other way and the audit catches it just the same. Nothing")
        print("    was censored, and the promise still does not hold: scenario 38 calibrated over")
        print("    every subset including the turns this stack refuses, and those turns are the easy")
        print("    ones. The certified bound of 0.0323 was computed on a population that contains")
        print("    thirteen turns the arbiter would never have sent. Restricted to the turns it")
        print("    would, the labelled loss alone is 0.1000 — double the budget, with no unknowns")
        print("    in it at all. A calibration set is not made honest by being complete.")
    }

    // MARK: - D: what withdrawing enforcement actually does

    private static func spendWithdrawnGate(
        outcome: CertificationOutcome,
        audit: CensoringAudit,
        meter: TokenMeter
    ) async {
        print("  D. the strong corpus, with the gate's enforcement withdrawn")
        let support = CertificateQualifier().qualify(outcome, against: audit)
        let signals = Self.conformalSignals(for: Self.strongCorpus, asOf: Self.conformalInstants[0])
        let ruling = AbstentionArbiter(policy: .standard).rule(on: signals)
        print("    judges          \(ruling.decision.summary)")
        let standing = support.allowsEnforcement ? "enforced" : "withdrawn — its promise is unsupported"
        print("    conformal gate  \(standing)")
        await Self.spendIfAnswerable(ruling, meter: meter, label: "rollback timing")
        print("    This is the one stage here whose effect is to stop a gate refusing, and it is")
        print("    allowed to only because the refusals it withdraws rested on nothing.")
    }

    // MARK: - Building the log

    /// One `FeedbackRecord` per turn scenario 38 calibrated on, with the label removed wherever
    /// this stack would never have obtained one.
    ///
    /// The three arms are derived rather than declared. A turn the arbiter answered is
    /// `.observed`. A turn it refused whose score sits *above* the certified threshold is
    /// `.determined(0)` — the gate would not have answered it either, so it cannot contribute to
    /// "answered and wrong" whatever the answer would have been. A turn it refused whose score sits
    /// *below* the threshold is the one that costs.
    static func censoredFeedbackLog(threshold: Double?, wide: Bool) async -> [FeedbackRecord] {
        var records: [FeedbackRecord] = []
        for (name, corpus) in Self.conformalCorpora {
            for subset in Self.conformalSubsets(of: corpus.passages.map(\.id)) {
                for (index, instant) in Self.conformalInstants.enumerated() {
                    let retained = corpus.retaining(subset)
                    let scored = Self.conformalSignals(for: retained, asOf: instant)
                    let judged = wide ? scored + [Self.censoredMorphologySignal(for: retained)] : scored
                    let admitted = wide ? await Self.censoredMergedPanel(judged, corpus: retained) : judged
                    let ruling = AbstentionArbiter(policy: .standard).rule(on: admitted)
                    records.append(
                        FeedbackRecord(
                            id: "\(name)-\(subset.sorted().joined(separator: "+"))-t\(index)",
                            admissionProbability: ruling.isAbstention ? 0 : 1,
                            observation: Self.censoredObservation(
                                ruling: ruling,
                                score: Self.conformalScore(scored),
                                threshold: threshold,
                                wasWrong: Self.conformalAnsweringWasWrong(retained, asOf: instant)
                            ),
                            stratum: CensoredFeedbackKit.Stratum(name)
                        )
                    )
                }
            }
        }
        return records
    }

    /// The fourth judge, built exactly as scenario 31 wires it: the same engine, a lenient policy
    /// and a morphological matcher. Nothing about it reaches the nonconformity score.
    /// The merge scenario 37 performs, on the graph it declares: answerability and morphology are
    /// the same engine with a different matcher, and the independence/temporal edge is measured off
    /// the corpus rather than written down.
    private static func censoredMergedPanel(
        _ signals: [AbstentionSignal],
        corpus: AbstentionCorpus
    ) async -> [AbstentionSignal] {
        var edges = [DependenceEdge("answerability", "morphology", mechanism: .sharedHeuristic)]
        let passageIDs = Set(corpus.passages.map(\.id))
        let observationIDs = Set(corpus.observations.map(\.id))
        let shared = passageIDs.intersection(observationIDs)
        if !shared.isEmpty {
            let overlap = Double(shared.count) / Double(passageIDs.union(observationIDs).count)
            edges.append(DependenceEdge("independence", "temporal", mechanism: .sharedInput, strength: overlap))
        }
        return await AbstentionSignalReducer().reduce(signals, using: DependenceGraph(edges: edges)).signals
    }

    private static func censoredMorphologySignal(for corpus: AbstentionCorpus) -> AbstentionSignal {
        let lenient = AnswerabilityEngine(policy: .lenient, matcher: MorphologyEvidenceMatcher())
        let report = lenient.assess(Question(corpus.question), against: corpus.evidence)
        return AnswerabilitySignalMapper(
            origin: SignalOrigin("morphology"),
            blockingExpression: .concern(.moderate)
        ).signal(for: report)
    }

    private static func censoredObservation(
        ruling: AbstentionRuling,
        score: Double,
        threshold: Double?,
        wasWrong: Bool
    ) -> LossObservation {
        guard ruling.isAbstention else { return .observed(wasWrong ? 1 : 0) }
        guard let threshold, score <= threshold else { return .determined(0) }
        return .censored
    }
}
