import CurveDivergenceKit
import DelayCurveKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let curveDivergenceHost = ProviderIdentifier("curve-divergence-host")
}

extension EcosystemDemo {
    /// The forty-fifth scenario: **scenario 44 established that the two classes separate on delay.
    /// This asks where, and whether the answer survives being asked without a horizon.**
    ///
    /// Part C of scenario 44 reached that conclusion through a log-rank statistic and a sweep of
    /// restricted means, and it printed `cancelsAtWidestHorizon` because the sweep needs to be asked
    /// at the right horizon to see what it sees. A supremum does not need to be asked: it takes the
    /// largest disagreement anywhere in the shared window and reports the tick it happened at.
    ///
    /// The interesting outcome is not "the supremum agrees". It is what the two answers are *made
    /// of* — one is an area that can cancel, the other is a height that cannot — and whether this
    /// ecosystem's own panel is a case where that matters.
    static func runCurveDivergenceScenario(meter: TokenMeter) async {
        print("[curve divergence scenario] the classes separate — but where?")
        guard let answered = await Self.delayShapeAnswered() else {
            print("  the ledger could not be built")
            return
        }
        let population = Self.delaySignalPopulation(copies: 40, answered: answered)
        guard let loss = Self.delayCurveSample(population, asOf: Self.delaySignalCutoff, wrong: true),
            let clean = Self.delayCurveSample(population, asOf: Self.delaySignalCutoff, wrong: false)
        else {
            print("  both classes are needed and one is missing")
            return
        }
        let sample = DivergenceSample(first: loss, second: clean)
        let report = await DivergenceAnalyzer().report(for: sample)
        Self.divergencePartA(sample, report: report)
        Self.divergencePartB(report)
        Self.divergencePartC(loss: loss, clean: clean, report: report)
        await meter.record(
            TokenUsage(promptTokens: population.count * 4, completionTokens: population.count * 2),
            for: ProviderIdentifier.curveDivergenceHost.rawValue
        )
    }

    // MARK: - A

    static func divergencePartA(_ sample: DivergenceSample, report: DivergenceReport) {
        print("  A. the window, and what it costs")
        print("     loss  supports to t\(sample.first.supportLimit),"
            + " \(sample.first.returnedCount) labels back")
        print("     clean supports to t\(sample.second.supportLimit),"
            + " \(sample.second.returnedCount) labels back")
        print("     shared window t0-t\(report.sharedSupport),"
            + " truncates an arm: \(report.windowTruncatesAnArm)")
        print("     censoring gap between the classes \(Self.number(report.censoredShareGap * 100, 2))%")
        print("     That last figure is the one to watch. The permutation null assumes the class")
        print("     labels are exchangeable, which is a claim about how the two classes were")
        print("     *observed* and not only about how fast they resolve. Nothing in this panel can")
        print("     tell a slow class from a class read late, so the number is published rather")
        print("     than corrected for.")
    }

    // MARK: - B

    static func divergencePartB(_ report: DivergenceReport) {
        print("  B. the supremum, and the tick nobody chose")
        guard let finding = report.verdict.finding else {
            print("     declined: \(report.verdict.decline.map(String.init(describing:)) ?? "no reason")")
            print("     A refusal here is the package working. It declines when the two classes")
            print("     share no window with labels in it, when a curve is too thin to read, or")
            print("     when the label space is too small for the test level at all.")
            return
        }
        let statistic = finding.statistic
        print("     shape                     \(statistic.shape)")
        print("     sup(loss - clean)         \(statistic.positive.summary)")
        print("     sup(clean - loss)         \(statistic.negative.summary)")
        print("     KS                        \(Self.number(statistic.kolmogorovSmirnov, 4))"
            + "   permutation p \(Self.number(finding.permutation.kolmogorovSmirnovPValue, 4))")
        print("     Kuiper                    \(Self.number(statistic.kuiper, 4))"
            + "   permutation p \(Self.number(finding.permutation.kuiperPValue, 4))")
        print("     \(finding.renyi.summary)")
        print("     smallest p 999 draws can reach"
            + "  \(Self.number(finding.permutation.smallestAttainablePValue, 4))")
        print("     label space smaller than draws  \(finding.permutation.labelSpaceSmallerThanDraws)")
        print("     exchangeability suspect         \(finding.permutation.exchangeabilitySuspect)")
    }

    // MARK: - C

    static func divergencePartC(loss: CurveSample, clean: CurveSample, report: DivergenceReport) {
        print("  C. against the two tests scenario 44 used on the same pair")
        let sweep = HorizonSweep.across(loss, clean)
        print("     log-rank                  \(sweep.logRank.summary)")
        if let widest = sweep.widest {
            print("     RMST at widest horizon    \(widest.summary)")
        }
        print("     horizons that separate    \(sweep.separatingHorizons.count)"
            + " of \(sweep.entries.count)")
        print("     cancels at the widest     \(sweep.cancelsAtWidestHorizon)")
        guard let finding = report.verdict.finding else {
            print("     the supremum declined on this panel, so there is nothing to compare")
            return
        }
        Self.divergenceReading(finding: finding, sweep: sweep)
    }

    static func divergenceReading(finding: DivergenceFinding, sweep: HorizonSweep) {
        let ksP = finding.permutation.kolmogorovSmirnovPValue
        let dominates = finding.statistic.shape.slowerArm != nil
        print("     supremum, one pass        KS p \(Self.number(ksP, 4))")
        if dominates {
            print("     On this panel the two curves do not cross: one class is above the other at")
            print("     every tick in the window. That is the geometry where an area and a height")
            print("     agree, so the log-rank result and the supremum result are the same finding")
            print("     reached twice, and this scenario is not the case the package was built for.")
            print("     Saying so is the point. The cancellation CurveDivergenceKit exists to")
            print("     survive is a real failure of the restricted mean and it is not this panel's")
            print("     failure, and a demo that implied otherwise would be reading its own README")
            print("     back rather than its data.")
        } else {
            print("     The curves cross here, which is exactly the geometry a single area cannot")
            print("     represent — a positive region added to a negative one.")
        }
        // Only the direction that actually has a supremum has a tick worth naming. On a dominance
        // panel the other one is the t0 entry, whose gap is zero by construction, and printing it
        // as though it located something would be the demo inventing a finding.
        let located = finding.statistic.positive.magnitude > finding.statistic.negative.magnitude
            ? finding.statistic.positive
            : finding.statistic.negative
        print("     What the supremum adds regardless: the sweep needed \(sweep.entries.count)")
        print("     horizons asked one at a time to produce its answer, and the supremum names")
        print("     t\(located.time) — where the gap reaches \(Self.number(located.magnitude, 4)) —")
        print("     in a single pass over the same window.")
    }
}
