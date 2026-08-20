import AbstentionPolicyKit
import AnswerabilityKit
import ConformalGateAbstention
import ConformalGateKit
import Foundation
import SourceIndependenceKit
import TemporalValidityKit
import TokenMeterKit

extension EcosystemDemo {
    /// The thirty-eighth scenario: **every gate in the last two scenarios has a number in it.**
    ///
    /// Scenario 36 abstained because two judges concurred. Scenario 37 asked whether those judges
    /// were separate. Neither asked the question underneath both: *what error rate does the
    /// concurrence count of 2 actually hold?* It was picked because it seemed reasonable, and
    /// thirty-seven scenarios later nothing here can say what it buys.
    ///
    /// Split conformal risk control answers that from outcomes, or refuses to answer it at all —
    /// and the first thing it does with this demo's own corpora is refuse, because two labelled
    /// turns cannot certify anything.
    static func runConformalGateScenario(meter: TokenMeter) async {
        print("[conformal gate scenario] what does the threshold actually hold?")
        let gate = ConformalGate(budget: .oneInTwenty)

        print("  A. the two corpora this demo has been judging all along")
        let asBuilt = Self.conformalAsBuilt()
        print("    labelled turns  \(asBuilt.count)")
        print("    outcome         \(gate.certify(asBuilt).summary)")
        print("    Thirty-seven scenarios of judging, and not one certifiable threshold in it.")

        let calibration = Self.conformalCalibration()
        await Self.certifyPanel(gate: gate, calibration: calibration)
        Self.stratifyPanel(gate: gate, calibration: calibration)
        await Self.rulePanelWithGate(gate: gate, calibration: calibration, meter: meter)
        print("  A threshold nobody derived is not a stricter gate. It is a gate with no promise behind it.")
    }

    // MARK: - B and C: certifying the panel's own threshold

    private static func certifyPanel(gate: ConformalGate, calibration: [CalibrationPoint]) async {
        print("  B. the same judges, over every subset of each corpus, asked at three instants")
        let wrong = calibration.filter(\.wasWrong).count
        print("    labelled turns  \(calibration.count), of which \(wrong) were wrong to answer")
        let curve = gate.riskCoverageCurve(calibration)
        guard let certificate = gate.certify(calibration).certificate else {
            print("    outcome         \(gate.certify(calibration).summary)")
            return
        }
        print("    certificate     \(certificate.summary)")
        print("    guarantee       \(certificate.guarantee)")
        let ungated = curve.riskWithoutGate.map { Self.conformalPercent($0) } ?? "n/a"
        let selective = certificate.observedSelectiveRisk.map { Self.conformalPercent($0) } ?? "n/a"
        print("    answering all   selective risk \(ungated)")
        print("    behind the gate selective risk \(selective) — observed, NOT certified")
        let cost = curve.coverageCost.map { Self.conformalPercent($0) } ?? "n/a"
        print("    price           \(cost) of turns given up")
    }

    private static func stratifyPanel(gate: ConformalGate, calibration: [CalibrationPoint]) {
        print("  C. the same budget, promised per corpus instead of on average")
        let result = gate.certifyStratified(calibration)
        for stratum in result.strata {
            let name = stratum.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
            print("    \(name)\(result.perStratum[stratum]?.summary ?? "")")
        }
        for breach in result.breaches {
            print("    breach          \(breach.summary)")
            if breach.wrongAnsweredCount == 0 {
                print("      a perfect record, and still a breach: \(breach.size) turns cannot promise")
                print("      one-in-twenty however clean they are. The unseen draw costs more than the budget.")
            }
        }
        let everywhere = result.conjunctiveThreshold.map { String(format: "%.3f", $0) } ?? "none"
        print("    holds in every corpus: \(everywhere)")
        print("    Per-slice control costs a full calibration set per slice, not one between them.")
    }

    // MARK: - D: the gate as one more voice

    private static func rulePanelWithGate(
        gate: ConformalGate,
        calibration: [CalibrationPoint],
        meter: TokenMeter
    ) async {
        print("  D. the certified gate, standing beside the judges it was derived from")
        let outcome = gate.certify(calibration)
        let arbiter = AbstentionArbiter(policy: .standard)
        let mapper = ConformalSignalMapper()

        for corpus in [("strong", Self.strongCorpus), ("weak", Self.weakCorpus)] {
            let signals = Self.conformalSignals(for: corpus.1, asOf: Self.conformalInstants[0])
            let score = Self.conformalScore(signals)
            let withGate = signals + [mapper.signal(id: corpus.0, score: score, under: outcome)]
            let ruling = arbiter.rule(on: withGate)
            let reading = mapper.reading(forScore: score, under: outcome).summary
            print("    \(corpus.0) corpus — score \(String(format: "%.2f", score)), gate says \(reading)")
            print("      \(ruling.decision.summary)")
            if corpus.0 == "strong" {
                await Self.spendIfAnswerable(ruling, meter: meter, label: "rollback timing")
            }
        }
    }
}
