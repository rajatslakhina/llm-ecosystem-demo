import ConditioningCostKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit
import TotalFixedExactKit
import UnconditionalExactKit

/// The identifier the sixty-third scenario bills its measurement against.
extension ProviderIdentifier {
    static let totalFixedExactHost = ProviderIdentifier("total-fixed-exact-host")
}

extension EcosystemDemo {
    /// The sixty-third scenario: **scenario 62 stopped conditioning. It still stopped one parameter
    /// short.**
    ///
    /// Barnard's test keeps the nuisance parameter a *row-fixed* design leaves and maximises over
    /// it. A panel of turns cross-classified by two gates fixes neither margin, so its independence
    /// null leaves **two** free parameters and the honest supremum is over a square. Scenario 62's
    /// own output said so and did nothing about it, which is the gap this one closes.
    ///
    /// The tempting shortcut — read the panel as row-fixed and call the answer conservative — is
    /// measured here and found unavailable. It moves in both directions.
    static func runTotalFixedExactScenario(meter: TokenMeter) async {
        print("[total-fixed exact scenario] the parameter scenario 62 left out")

        totalFixedPartA()
        totalFixedPartB()
        totalFixedPartC()

        await meter.record(
            TokenUsage(promptTokens: 470, completionTokens: 168),
            for: ProviderIdentifier.totalFixedExactHost.rawValue
        )
    }

    /// The same twelve-item panel scenario 62 reported on, read as the design it actually was.
    private static var totalFixedPanel: CrossTable? {
        try? CrossTable(a: 5, b: 1, c: 1, d: 5)
    }

    private static var totalFixedTest: TotalFixedExact? {
        try? TotalFixedExact(.enclosure(1e-9), budget: 20_000)
    }

    // MARK: - A: one panel, three designs, three answers

    private static func totalFixedPartA() {
        print("  A. the panel scenario 62 read, read again with nothing held fixed")
        guard let panel = totalFixedPanel,
              let test = totalFixedTest,
              let arms = try? panel.arms(),
              let rowFixed = try? UnconditionalExact(.remainder(1e-5)),
              let barnard = try? rowFixed.pValue(for: arms),
              let reading = try? test.pValue(for: panel) else {
            print("     the panel could not be read")
            return
        }
        let conditional = FisherConditional.pValue(for: arms)
        print("     \(totalFixedWide("procedure", 30))\(totalFixedWide("p-value", 12))"
            + "\(totalFixedWide("fixed", 7))\(totalFixedWide("params", 8))at 5%")
        totalFixedRow("total-fixed unconditional", reading.value, 0, 2, reading.rejects(at: 0.05))
        totalFixedRow("row-fixed Barnard", barnard.value, 1, 1, barnard.value <= 0.05)
        totalFixedRow("Fisher conditional", conditional, 2, 0, conditional <= 0.05)
        print("     \(SamplingDesign.totalFixed.label): "
            + "\(SamplingDesign.totalFixed.rationale).")
        print("     The ordering admits \(reading.admittedTableCount) of "
            + "\(reading.designTableCount) tables, and the null likes it most at a row rate of "
            + TotalFixedFormatting.decimal(reading.worstRowRate, places: 4))
        print("     and a column rate of "
            + TotalFixedFormatting.decimal(reading.worstColumnRate, places: 4)
            + ". Both are estimated, neither was chosen.")
    }

    private static func totalFixedRow(
        _ name: String,
        _ value: Double,
        _ fixed: Int,
        _ params: Int,
        _ rejects: Bool
    ) {
        print("     \(totalFixedWide(name, 30))"
            + "\(totalFixedWide(TotalFixedFormatting.decimal(value), 12))"
            + "\(totalFixedWide("\(fixed)", 7))\(totalFixedWide("\(params)", 8))"
            + (rejects ? "rejects" : "does not reject"))
    }

    // MARK: - B: the row-fixed reading is not a bound

    private static func totalFixedPartB() {
        print("  B. reading a total-fixed panel as row-fixed is not conservative")
        guard let test = totalFixedTest,
              let rowFixed = try? UnconditionalExact(.remainder(1e-5)) else {
            print("     the comparison could not be set up")
            return
        }
        print("     \(totalFixedWide("panel", 16))\(totalFixedWide("total-fixed", 14))"
            + "\(totalFixedWide("row-fixed", 13))\(totalFixedWide("ratio", 10))direction")
        for cells in [(9, 1, 3, 7), (10, 2, 3, 5)] {
            guard let table = try? CrossTable(a: cells.0, b: cells.1, c: cells.2, d: cells.3),
                  let arms = try? table.arms(),
                  let here = try? test.pValue(for: table),
                  let there = try? rowFixed.pValue(for: arms) else { continue }
            let ratio = here.value / there.value
            print("     \(totalFixedWide(TotalFixedFormatting.table(table), 16))"
                + "\(totalFixedWide(TotalFixedFormatting.decimal(here.value), 14))"
                + "\(totalFixedWide(TotalFixedFormatting.decimal(there.value), 13))"
                + "\(totalFixedWide(TotalFixedFormatting.decimal(ratio, places: 4), 10))"
                + (ratio > 1 ? "larger" : "smaller"))
        }
        print("     One panel moves up when the second parameter is admitted and the other moves")
        print("     down, so there is no direction in which the cheaper reading is safe.")
    }

    // MARK: - C: what the certificate costs, and why it is affordable at all

    private static func totalFixedPartC() {
        print("  C. what a certified supremum over a square costs")
        guard let panel = totalFixedPanel else { return }
        guard let intervals = try? UniformGrid.intervalsNeeded(forRemainder: 1e-4, total: panel.total),
              let gridCost = try? UniformGrid.evaluationCount(intervals: intervals) else { return }
        print("     uniform grid, remainder 1e-4:   "
            + "\(TotalFixedFormatting.count(intervals)) per side, "
            + "\(TotalFixedFormatting.count(gridCost)) evaluations")
        if let first = try? TotalFixedExact(.lipschitz(1e-4), budget: 50_000),
           let firstOrder = try? first.pValue(for: panel) {
            print("     Lipschitz branch and bound:     "
                + "\(TotalFixedFormatting.count(firstOrder.maximum.evaluationCount)) evaluations, "
                + "reached \(TotalFixedFormatting.decimal(firstOrder.maximum.remainder, places: 8))"
                + (firstOrder.maximum.converged ? "" : " — budget exhausted"))
        }
        for precision in [1e-4, 1e-9] {
            guard let test = try? TotalFixedExact(.enclosure(precision), budget: 20_000),
                  let reading = try? test.pValue(for: panel) else { continue }
            print("     Bernstein enclosure "
                + totalFixedWide(TotalFixedFormatting.decimal(precision, places: 9), 13)
                + "\(TotalFixedFormatting.count(reading.maximum.evaluationCount)) subdivisions, "
                + "remainder \(TotalFixedFormatting.decimal(reading.maximum.remainder, places: 12))")
        }
        if let coarse = try? TotalFixedExact(.enclosure(1e9), budget: 4),
           let bound = try? coarse.pValue(for: panel) {
            print("     The enclosure's zero-work upper bound is "
                + TotalFixedFormatting.decimal(bound.maximum.certified)
                + ", which by Vandermonde's")
            print("     identity is the worst conditional rejection probability over every margin")
            print("     the panel might have shown. True and checkable, and too loose to quote.")
        }
        totalFixedLevels()
    }

    private static func totalFixedLevels() {
        guard let test = totalFixedTest, let space = try? TableSpace(total: 12) else { return }
        guard let truth = try? JointTruth(rowRate: 0.5, rate: 0.85, otherRate: 0.15) else { return }
        print("     and on that design, at a claimed five percent:")
        print("     \(totalFixedWide("procedure", 30))\(totalFixedWide("size", 11))"
            + "\(totalFixedWide("spends", 10))\(totalFixedWide("holds", 7))power")
        let procedures: [TotalFixedProcedure] = [
            .conditional, .asymptoticScore, .unconditional(restriction: .unrestricted)
        ]
        for procedure in procedures {
            guard let mask = try? LevelAudit.rejectionMask(
                of: procedure, total: 12, alpha: 0.05, test: test
            ), let certificate = try? LevelAudit.certificate(
                of: procedure, total: 12, alpha: 0.05, rejecting: mask, test: test
            ) else {
                print("     \(procedure.label): could not be audited")
                continue
            }
            let power = PowerProbe.power(rejecting: mask, space: space, under: truth)
            print("     \(totalFixedWide(procedure.label, 30))"
                + "\(totalFixedWide(TotalFixedFormatting.decimal(certificate.size.attained), 11))"
                + "\(totalFixedWide(TotalFixedFormatting.percent(certificate.spentShare, places: 2), 10))"
                + "\(totalFixedWide(certificate.holdsItsLevel ? "yes" : "NO", 7))"
                + TotalFixedFormatting.decimal(power))
        }
        print("     Only one of the three both holds the level it claims and spends it.")
    }

    private static func totalFixedWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
