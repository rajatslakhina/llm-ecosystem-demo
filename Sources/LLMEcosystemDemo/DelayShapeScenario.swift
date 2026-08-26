import ConformalGateKit
import DelayShapeKit
import DelayShapeSignal
import DelaySignalKit
import LabelReturnKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let delayShapeHost = ProviderIdentifier("delay-shape-host")
}

extension EcosystemDemo {
    /// The forty-third scenario: **scenario 42 named the reason its correction fell short, and then
    /// guessed the shape wrong.**
    ///
    /// Its closing paragraph says the delay rule "is close to two-point, and an exponential fitted
    /// to it keeps a tail the real delays do not have". The first half is the right diagnosis. The
    /// second half is a guess, and the point of this scenario is that a guess about a distribution
    /// is a thing you can simply measure instead.
    static func runDelayShapeScenario(meter: TokenMeter) async {
        print("[delay shape scenario] what shape is scenario 42's delay, actually?")
        guard let answered = await Self.delayShapeAnswered() else {
            print("  the ledger could not be built")
            return
        }
        let population = Self.delaySignalPopulation(copies: 40, answered: answered)
        // Two estimators over the same turns, because one cannot be read twice going backwards —
        // and going backwards is exactly what this needs. The shape is learned where the labels
        // are and spent where they are not.
        guard let settled = await Self.delayShapePanel(over: population, asOf: Self.delayShapeSettledCutoff),
            let fresh = await Self.delayShapePanel(over: population, asOf: Self.delaySignalCutoff)
        else {
            print("  the panels could not be built")
            return
        }
        let diagnosis = PanelShapes.diagnose(settled)
        Self.delayShapePartA(settled, diagnosis)
        Self.delayShapePartB(diagnosis, fresh: fresh)
        await Self.delayShapePartC(panel: fresh, diagnosis: diagnosis, population: population)
        await meter.record(
            TokenUsage(promptTokens: settled.admittedCount * 7, completionTokens: settled.admittedCount * 3),
            for: ProviderIdentifier.delayShapeHost.rawValue
        )
    }

    // MARK: - A

    static func delayShapePartA(_ panel: DelayPanel, _ diagnosis: PanelShapeDiagnosis) {
        print("  A. the ranking, per class, on a settled read of the same turns")
        print("     delay = 2 + floor(score x 8) + (wasWrong ? 6 : 0) + jitter(0..5), "
            + "cut at t\(Self.delayShapeSettledCutoff)")
        print("     Scenario 42's own cutoff, t\(Self.delaySignalCutoff), has 29 loss labels back "
            + "against a minimum of 30.")
        print("     That is the package's own tension and not a fixture accident: a panel early enough")
        print("     for the correction to be worth anything is a panel too early to identify the slow")
        print("     class's shape from. So the shape is learned here and spent in part C.")
        for label in LabelClass.allCases {
            guard let report = diagnosis.classReports[label], let ranking = report.ranking else {
                let returned = panel.returned(label).count
                let verdict = diagnosis.classReports[label]?.verdict.description ?? "no sample"
                print("     \(label): \(returned) labels back — \(verdict)")
                continue
            }
            print("     \(label): \(report.returnedCount) labels back, "
                + "observed mean \(Self.number(report.naiveMeanDelay, 2)) ticks")
            for line in ranking.table {
                print("       \(line)")
            }
            print("       \(report.verdict)")
        }
    }

    // MARK: - B

    static func delayShapePartB(_ diagnosis: PanelShapeDiagnosis, fresh: DelayPanel) {
        print("  B. so scenario 42's guess was wrong, and wrong in the direction that matters")
        print("     It said two-point. Two-point delays have a hazard that spikes and stops — the")
        print("     natural fits for that are a shift with a short tail, or a mixture with one fast")
        print("     component and one slow one. Neither wins here.")
        print("     assumption: \(diagnosis.assumption)")
        print("     the panel this is about to be spent on: t\(Self.delaySignalCutoff), "
            + "\(fresh.returned.count)/\(fresh.admittedCount) in, "
            + "\(Self.number(fresh.censoredShare * 100, 2))% still outstanding")
        guard let loss = diagnosis.classReports[.loss]?.shape,
            let noLoss = diagnosis.classReports[.noLoss]?.shape,
            let lossExponential = diagnosis.classReports[.loss]?.ranking?.exponential.shape,
            let noLossExponential = diagnosis.classReports[.noLoss]?.ranking?.exponential.shape
        else {
            print("     (both classes must be diagnosed to show the tails — read the ranking above)")
            return
        }
        if case let .weibull(shape, _) = loss {
            print("     A Weibull with shape \(Self.number(shape, 3)) has a hazard that RISES with age: the longer a")
            print("     label has been outstanding, the likelier it arrives in the next tick. Memoryless is")
            print("     wrong here in the opposite direction from the guess.")
        }
        print("     And the cost is not in the means, it is in the ratio at the cutoff. An outstanding")
        print("     request is attributed to a class by how plausible its silence is under each, so what")
        print("     matters is P(still waiting) side by side:")
        print("       elapsed   loss: fitted / exponential      no loss: fitted / exponential")
        for elapsed in [6.0, 10.0, 14.0] {
            let lossCell = "\(Self.number(loss.survival(after: elapsed), 4)) / "
                + Self.number(lossExponential.survival(after: elapsed), 4)
            let noLossCell = "\(Self.number(noLoss.survival(after: elapsed), 4)) / "
                + Self.number(noLossExponential.survival(after: elapsed), 4)
            print("       \(Self.pad(Int(elapsed), 7))   \(lossCell)                  \(noLossCell)")
        }
        print("     Through most of that window the exponential under-states how long losses take and")
        print("     over-states how long clean answers take, both at once, so an old unanswered request")
        print("     looks less like a loss than it is. The two loss curves do cross by 14 ticks — a")
        print("     rising hazard eventually overtakes a constant one — but almost nothing on this panel")
        print("     is that old, and where the outstanding column actually sits the gap runs one way.")
        print("     The responsibility assigned to the loss class is too small and the correction stops")
        print("     early. Scenario 42 measured that shortfall correctly and only mis-named its cause.")
    }

    // MARK: - C

    static func delayShapePartC(
        panel: DelayPanel,
        diagnosis: PanelShapeDiagnosis,
        population: [DelaySignalTurn]
    ) async {
        print("  C. spending it on scenario 42's own panel: same arithmetic, three delay models")
        let truth = Double(population.filter(\.wasWrong).count) / Double(population.count)
        guard
            let lossReport = diagnosis.classReports[.loss],
            let noLossReport = diagnosis.classReports[.noLoss],
            let selectedLoss = lossReport.shape,
            let selectedNoLoss = noLossReport.shape,
            let exponentialLoss = lossReport.ranking?.exponential.shape,
            let exponentialNoLoss = noLossReport.ranking?.exponential.shape,
            let selected = try? ShapedRisk.correct(
                panel: panel,
                lossShape: selectedLoss,
                noLossShape: selectedNoLoss
            ),
            let assumed = try? ShapedRisk.correct(
                panel: panel,
                lossShape: exponentialLoss,
                noLossShape: exponentialNoLoss
            )
        else {
            print("     both classes must be diagnosed before a shape can be spent — nothing to compare")
            return
        }
        print("     truth                      \(Self.number(truth, 4))")
        print("     naive (labels returned)    \(Self.number(selected.naive, 4))  "
            + "off by \(Self.number(abs(selected.naive - truth), 4))")
        print("     shapes the evidence chose  \(Self.number(selected.corrected, 4))  "
            + "off by \(Self.number(abs(selected.corrected - truth), 4))")
        print("     exponentials it rejected   \(Self.number(assumed.corrected, 4))  "
            + "off by \(Self.number(abs(assumed.corrected - truth), 4))")
        switch (try? DelaySignalEstimator.decide(panel: panel, settings: .standard)) ?? .declined(.nothingAdmitted) {
        case let .corrected(risk):
            print("     DelaySignalKit joint EM    \(Self.number(risk.corrected, 4))  "
                + "off by \(Self.number(abs(risk.corrected - truth), 4))")
        case let .declined(reason):
            print("     DelaySignalKit joint EM    declined — \(reason)")
        }
        print("     Scenario 42 closed about a quarter of its gap and said so. That was the shape")
        print("     costing it three quarters of what was available, and finding out took one")
        print("     measurement rather than one adjective.")
    }

    /// Late enough that every delay this rule can produce is in: the slowest is
    /// `2 + 7 + 6 + 5 = 20` ticks on an admission no later than tick 19.
    static let delayShapeSettledCutoff = 60

    static func delayShapePanel(over turns: [DelaySignalTurn], asOf tick: Int) async -> DelayPanel? {
        guard let estimator = await Self.delaySignalEstimator(over: turns) else {
            return nil
        }
        return try? await estimator.panel(asOf: DelaySignalKit.LogicalTime(tick))
    }

    /// The turns this stack answered, recovered the same way scenario 42 recovers them, so both
    /// scenarios are looking at the same population rather than at two that resemble each other.
    static func delayShapeAnswered() async -> Set<String>? {
        let gate = ConformalGate(budget: .oneInTwenty)
        guard let certificate = gate.certify(Self.conformalCalibration()).certificate else {
            return nil
        }
        let fingerprint = GateFingerprint(identifier: "conformal-gate", threshold: certificate.threshold)
        guard let built = await Self.labelReturnLedger(threshold: certificate.threshold, gate: fingerprint) else {
            return nil
        }
        return Set(built.admissions.map(\.id))
    }
}
