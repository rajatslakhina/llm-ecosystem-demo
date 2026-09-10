import ConditioningCostKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit
import UnconditionalExactKit

/// The identifier the sixty-second scenario bills its measurement against.
extension ProviderIdentifier {
    static let unconditionalExactHost = ProviderIdentifier("unconditional-exact-host")
}

extension EcosystemDemo {
    /// The sixty-second scenario: **scenario 61 priced an assumption. This one declines to make it.**
    ///
    /// Scenario 61 showed that every exact interval in this ecosystem conditions on margins the
    /// corpus never fixed, and measured what that costs in coverage. The diagnosis was complete and
    /// the prescription was missing. Barnard's test is the prescription: keep the nuisance parameter
    /// and maximise the null probability over it, which costs computation instead of guarantee.
    ///
    /// It also fixes something scenario 61 recorded as unbounded. Every method of this kind
    /// maximises on a grid, and a grid maximum is a *lower* bound on a supremum — so quoting it as a
    /// p-value errs towards rejecting, which is the one direction a p-value must not err in. The
    /// grid here is uniform in `asin(sqrt(p))`, which bounds the slope by `2 * sqrt(n)` across the
    /// whole closed range, endpoints included, so the remainder is an arithmetic fact rather than a
    /// hope about smoothness.
    static func runUnconditionalExactScenario(meter: TokenMeter) async {
        print("[unconditional exact scenario] the assumption scenario 61 priced, declined")

        unconditionalPartA()
        unconditionalPartB()
        unconditionalPartC()

        await meter.record(
            TokenUsage(promptTokens: 445, completionTokens: 160),
            for: ProviderIdentifier.unconditionalExactHost.rawValue
        )
    }

    /// A twelve-item panel of the shape this series keeps reporting on: two gates, six turns each.
    private static var unconditionalPanel: ArmCounts? {
        try? ArmCounts(successes: 5, trials: 6, otherSuccesses: 1, otherTrials: 6)
    }

    // MARK: - A: one table, three p-values

    private static func unconditionalPartA() {
        print("  A. a twelve-item panel, and the three p-values it can be given")
        guard let panel = unconditionalPanel,
              let test = try? UnconditionalExact(.remainder(1e-5)),
              let free = try? test.pValue(for: panel),
              let restricted = try? test.pValue(for: panel, restriction: .bergerBoos(gamma: 0.001)) else {
            print("     the panel could not be read")
            return
        }
        let conditional = FisherConditional.pValue(for: panel)
        print("     \(unconditionalWide("procedure", 38))\(unconditionalWide("p-value", 12))"
            + "\(unconditionalWide("bracket width", 16))guarantee is about")
        unconditionalRow("unconditional", free.value, free.uncertainty, "this design")
        unconditionalRow("Berger–Boos γ=0.001", restricted.value, restricted.uncertainty, "this design")
        unconditionalRow("Fisher conditional", conditional, 0, "a design nobody ran")
        print("     The conditional p-value holds a column margin at "
            + "\(panel.pooledSuccesses) because it was observed to")
        print("     be \(panel.pooledSuccesses). \(SamplingDesign.rowMarginsFixed.rationale).")
        print("     The unconditional region admits \(free.regionTableCount) of "
            + "\(free.designTableCount) tables and the null likes it most at a shared rate of "
            + UnconditionalFormatting.decimal(free.worstRate) + ".")
    }

    private static func unconditionalRow(_ name: String, _ value: Double, _ width: Double, _ about: String) {
        print("     \(unconditionalWide(name, 38))"
            + "\(unconditionalWide(UnconditionalFormatting.decimal(value, places: 6), 12))"
            + "\(unconditionalWide(UnconditionalFormatting.decimal(width, places: 6), 16))\(about)")
    }

    // MARK: - B: what each test's level actually costs it

    private static func unconditionalPartB() {
        print("  B. what a claimed five percent actually costs each test on that design")
        print("     \(unconditionalWide("procedure", 38))\(unconditionalWide("size", 11))"
            + "\(unconditionalWide("spent", 9))\(unconditionalWide("rejects on", 12))verdict")
        for procedure in unconditionalProcedures {
            guard let certificate = try? SizeCertificate.of(
                procedure: procedure, trials: 6, otherTrials: 6, alpha: 0.05, resolution: 2048
            ) else {
                print("     \(procedure.label): could not be audited")
                continue
            }
            print("     \(unconditionalWide(procedure.label, 38))"
                + "\(unconditionalWide(UnconditionalFormatting.percent(certificate.size.attained), 11))"
                + "\(unconditionalWide(UnconditionalFormatting.percent(certificate.spentShare, places: 1), 9))"
                + "\(unconditionalWide("\(certificate.rejectionTableCount) tables", 12))"
                + unconditionalVerdict(certificate))
        }
        print("     Unspent level is not safety. Coverage above nominal and size below it are one")
        print("     measurement read from two sides, and scenario 61 only ever took the first.")
    }

    private static func unconditionalVerdict(_ certificate: SizeCertificate) -> String {
        if certificate.exceedsItsLevel { return "OVER its level" }
        if certificate.holdsItsLevel { return "holds" }
        return "grid too coarse to say"
    }

    // MARK: - C: what the unspent level would have bought

    private static func unconditionalPartC() {
        print("  C. what the level nobody spent would have bought")
        guard let truth = try? AlternativeTruth(rate: 0.85, otherRate: 0.15) else {
            print("     the alternative could not be stated")
            return
        }
        print("     \(unconditionalWide("procedure", 38))power at "
            + UnconditionalFormatting.decimal(truth.rate, places: 2) + " against "
            + UnconditionalFormatting.decimal(truth.otherRate, places: 2))
        var best = 0.0
        var conditional = 0.0
        for procedure in unconditionalProcedures {
            guard let reading = try? PowerProbe.power(
                of: procedure, trials: 6, otherTrials: 6, alpha: 0.05, at: truth, resolution: 2048
            ) else { continue }
            if procedure == .fisherConditional { conditional = reading.power }
            if procedure == .unconditional(.unrestricted) { best = reading.power }
            print("     \(unconditionalWide(procedure.label, 38))"
                + UnconditionalFormatting.percent(reading.power))
        }
        let gain = (best - conditional) * 100
        print("     Not conditioning on a margin this corpus never fixed is worth "
            + UnconditionalFormatting.decimal(gain, places: 4) + " points")
        print("     of power here, at a level that is still held rather than merely claimed.")
        print("     Scenario 61 said what the assumption cost. This one stops paying it, and the")
        print("     grid error it left unbounded is now a number a caller can name in advance.")
    }

    private static var unconditionalProcedures: [TestProcedure] {
        [
            .unconditional(.unrestricted),
            .unconditional(.bergerBoos(gamma: 0.001)),
            .fisherConditional,
            .asymptoticScore
        ]
    }

    private static func unconditionalWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
