import DelayCurveKit
import DelayCurveShape
import DelayShapeKit
import DelayShapeSignal
import Foundation
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let delayCurveHost = ProviderIdentifier("delay-curve-host")
}

extension EcosystemDemo {
    /// The forty-fourth scenario: **scenario 43 answered with a curve it fitted. This checks that
    /// curve against the one the data draws by itself.**
    ///
    /// Scenario 43 selected a Weibull per class and then read survival off it at 6, 10 and 14
    /// elapsed ticks, and closed by saying the two loss curves "cross by 14 ticks". Every one of
    /// those numbers came out of a formula. A formula is total — it answers at 14 ticks whether or
    /// not anything was ever observed at 14 ticks — so the question this scenario exists to ask is
    /// which of scenario 43's numbers the panel could actually have contradicted.
    static func runDelayCurveScenario(meter: TokenMeter) async {
        print("[delay curve scenario] which of scenario 43's numbers did the data pay for?")
        guard let answered = await Self.delayShapeAnswered() else {
            print("  the ledger could not be built")
            return
        }
        let population = Self.delaySignalPopulation(copies: 40, answered: answered)
        guard let settled = await Self.delayShapePanel(over: population, asOf: Self.delayShapeSettledCutoff) else {
            print("  the settled panel could not be built")
            return
        }
        let diagnosis = PanelShapes.diagnose(settled)
        Self.delayCurvePartA(population)
        Self.delayCurvePartB(population, diagnosis: diagnosis)
        Self.delayCurvePartC(population)
        await meter.record(
            TokenUsage(promptTokens: population.count * 5, completionTokens: population.count * 2),
            for: ProviderIdentifier.delayCurveHost.rawValue
        )
    }

    // MARK: - A

    static func delayCurvePartA(_ population: [DelaySignalTurn]) {
        print("  A. the curve the data draws, with no family in it")
        guard let fresh = Self.delayCurveSample(population, asOf: Self.delaySignalCutoff, wrong: nil),
            let settled = Self.delayCurveSample(population, asOf: Self.delayShapeSettledCutoff, wrong: nil)
        else {
            print("     no sample could be built")
            return
        }
        let freshCurve = KaplanMeier.estimate(for: fresh)
        let settledCurve = KaplanMeier.estimate(for: settled)
        print("     settled (t\(Self.delayShapeSettledCutoff))  \(settledCurve.summaryLine)")
        print("     fresh   (t\(Self.delaySignalCutoff))  \(freshCurve.summaryLine)")
        print("     elapsed   settled truth   fresh curve")
        for tick in [6, 10, 14, 16, 20] {
            let truth = settledCurve.survival(at: tick).map { Self.number($0, 4) } ?? "undefined"
            let observed = freshCurve.survival(at: tick).map { Self.number($0, 4) } ?? "undefined"
            print("       \(Self.pad(tick, 7))   \(Self.curvePad(truth, 13))   \(observed)")
        }
        print("     The fresh panel stops at t\(freshCurve.supportLimit). Scenario 43 quoted survival at 14")
        let margin = freshCurve.supportLimit - 14
        print("     elapsed ticks for both classes; this panel has \(margin) tick(s) of data past 14,")
        print("     which is the margin every one of those figures was resting on.")
    }

    // MARK: - B

    static func delayCurvePartB(_ population: [DelaySignalTurn], diagnosis: PanelShapeDiagnosis) {
        print("  B. scenario 43 read survival off its fitted families at 6, 10 and 14 elapsed ticks")
        print("     Every label is in on this read, so both curves are complete distributions and")
        print("     each one is the answer rather than an estimate of it. family / curve:")
        print("     class     support        t6              t10             t14")
        for label in [true, false] {
            let name = label ? "loss   " : "no loss"
            guard let sample = Self.delayCurveSample(population, asOf: Self.delayShapeSettledCutoff, wrong: label),
                let shape = diagnosis.classReports[label ? .loss : .noLoss]?.shape
            else {
                print("     \(name):   no shape or no sample to compare")
                continue
            }
            let curve = KaplanMeier.estimate(for: sample)
            let cells = [6, 10, 14].map { tick -> String in
                let fitted = Self.number(shape.survival(after: Double(tick)), 4)
                let observed = curve.survival(at: tick).map { Self.number($0, 4) } ?? "undefined"
                return Self.curvePad("\(fitted) / \(observed)", 16)
            }
            print("     \(name)   t\(Self.curvePad(String(curve.supportLimit), 10))\(cells.joined())")
        }
        print("     The loss row is close everywhere and the fit deserves the credit scenario 43")
        print("     gave it. The clean row is the one worth reading: no clean answer in this")
        print("     population ever took more than 8 ticks — 2 + 7 + 0 and jitter did not reach")
        print("     further — so the curve is at exactly 0.0000 from t9 onward, and that is a")
        print("     measurement rather than a floor. At t10 the fitted Weibull still assigns clean")
        print("     answers 0.0013 of being outstanding. It is a small number and it is not a gap")
        print("     the family is filling: the data there is not missing, it is zero.")
        print("     Scenario 43 closed by saying its two loss curves — the Weibull it chose and the")
        print("     exponential it rejected — cross by 14 ticks. Both are formulas, and at t14 the")
        print("     loss class still has data: the curve reads 0.2167 against the Weibull's 0.1637.")
        print("     So the crossing is real and the empirical value sits above both of them. Where")
        print("     scenario 43 had to argue from the shape of two fits, this reads the answer.")
    }

    // MARK: - C

    static func delayCurvePartC(_ population: [DelaySignalTurn]) {
        print("  C. does the delay separate the two classes without assuming a shape?")
        guard let loss = Self.delayCurveSample(population, asOf: Self.delaySignalCutoff, wrong: true),
            let clean = Self.delayCurveSample(population, asOf: Self.delaySignalCutoff, wrong: false)
        else {
            print("     both classes are needed and one is missing")
            return
        }
        let sweep = HorizonSweep.across(loss, clean)
        print("     log-rank                  \(sweep.logRank.summary)")
        if let widest = sweep.widest {
            print("     RMST at widest horizon    \(widest.summary)")
        }
        if let strongest = sweep.strongest {
            print("     RMST at its best          \(strongest.summary)")
        }
        print("     horizons that separate    \(sweep.separatingHorizons.count) of \(sweep.entries.count)")
        print("     cancels at the widest     \(sweep.cancelsAtWidestHorizon)")
        print("     DelaySignalKit's whole correction rests on the two classes returning at")
        print("     different speeds, and it establishes that by fitting a rate to each. This")
        print("     establishes it without fitting anything — the same conclusion reached a second")
        print("     way, which is worth more than the same conclusion reached twice the first way.")
    }

    // MARK: - Support

    /// The panel as a product-limit sample: what came back, and what is still waiting.
    ///
    /// Built straight from the turns rather than converted from `DelayPanel`, because a
    /// `CurveSample` needs no per-observation observation limit and inventing one to make a
    /// conversion typecheck would be a fabrication with a cast around it.
    /// Right-pads a rendered cell so the table lines up. The existing `pad` takes an `Int`.
    static func curvePad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func delayCurveSample(
        _ population: [DelaySignalTurn],
        asOf cutoff: Int,
        wrong: Bool?
    ) -> CurveSample? {
        var observations: [CurveObservation] = []
        for turn in population {
            if let wrong, turn.wasWrong != wrong {
                continue
            }
            let elapsed = cutoff - turn.admittedAt
            guard elapsed >= 1 else { continue }
            observations.append(
                turn.delay <= elapsed ? .returned(afterTicks: turn.delay) : .outstanding(forTicks: elapsed)
            )
        }
        return try? CurveSample(observations)
    }
}
