import ConditioningCostKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// One design the sixty-first scenario prices, named so the table of them is not a tuple.
struct ConditioningCase {
    let label: String
    let frame: TableFrame
    let truth: TruthParameter
}

/// The identifier the sixty-first scenario bills its measurement against.
extension ProviderIdentifier {
    static let conditioningCostHost = ProviderIdentifier("conditioning-cost-host")
}

extension EcosystemDemo {
    /// The sixty-first scenario: **scenario 60 proved its intervals were exact. This one asks what
    /// "exact" was conditional on.**
    ///
    /// Scenario 60 replaced an asymptotic interval with an exact one and showed the asymptotic side
    /// had been too narrow on every small table anyone checked. Exactness there comes from
    /// conditioning on all four margins, which removes the nuisance parameter — and which is only
    /// free when the design fixed those margins. This corpus fixed neither. Nothing in fifty-nine
    /// scenarios stated that assumption, and nothing could price it.
    static func runConditioningCostScenario(meter: TokenMeter) async {
        print("[conditioning cost scenario] what scenario 60's exactness was conditional on")

        conditioningPartA()
        conditioningPartB()
        conditioningPartC()

        await meter.record(
            TokenUsage(promptTokens: 430, completionTokens: 150),
            for: ProviderIdentifier.conditioningCostHost.rawValue
        )
    }

    // MARK: - A: the design nobody declared

    private static func conditioningPartA() {
        print("  A. the design this corpus has, and the one its intervals assumed")
        for design in SamplingDesign.allCases {
            let mark = design.licensesConditioning ? "licensed" : "NOT licensed"
            print("     \(conditioningWide(design.label, 20))\(conditioningWide(mark, 14))\(design.rationale)")
        }
        print("     Each turn in this corpus was judged by two gates. Neither gate's margin was")
        print("     chosen in advance, so the design is total-fixed and conditioning is not licensed.")
    }

    /// How many tables a total-fixed design of `items` items has: the compositions into four parts.
    private static func conditioningTotalFixedTables(_ items: Int) -> Int {
        (items + 1) * (items + 2) * (items + 3) / 6
    }

    // MARK: - B: the corpus block under the design it needs and one it does not

    private static func conditioningPartB() {
        print("  B. the readable block [36, 36; 12, 12], under two designs, same 95% claim")
        let cases = [
            ConditioningCase(
                label: "both margins fixed",
                frame: .bothMarginsFixed(rowTotal: 72, otherRowTotal: 24, columnTotal: 48),
                truth: .oddsRatio(1)
            ),
            ConditioningCase(
                label: "row margins fixed",
                frame: .rowMarginsFixed(rowTotal: 72, otherRowTotal: 24),
                truth: .binomial(p1: 0.5, p2: 0.5)
            )
        ]
        print("     \(conditioningWide("design", 20))\(conditioningWide("tables", 9))"
            + "\(conditioningWide("exact cover", 13))\(conditioningWide("Woolf cover", 13))"
            + "\(conditioningWide("overspend", 13))premium")
        for design in cases {
            guard let cost = try? ConditioningCost.measure(frame: design.frame, truth: design.truth),
                  let exact = cost.reading(.exactConditional),
                  let woolf = cost.reading(.woolf) else {
                print("     \(design.label): could not be priced")
                continue
            }
            print("     \(conditioningWide(design.label, 20))"
                + "\(conditioningWide(String(exact.tableCount), 9))"
                + "\(conditioningWide(CostFormatting.percent(exact.actualCoverage), 13))"
                + "\(conditioningWide(CostFormatting.percent(woolf.actualCoverage), 13))"
                + "\(conditioningWide(CostFormatting.points(cost.guaranteeOverspend), 13))"
                + CostFormatting.ratio(cost.widthPremium))
        }
        let tables = conditioningTotalFixedTables(96)
        print("     Same block, same parameter, same nominal level, two designs, two answers. The")
        print("     design is not an argument to any interval this ecosystem computes.")
        print("     Neither row is the design this corpus has. Enumerating that one — total-fixed")
        print("     over 96 items — is \(tables) tables, which is why this scenario prices the two")
        print("     cheaper designs and leaves the full one to the package's own demo.")
    }

    // MARK: - C: the panels this series actually reports on

    private static func conditioningPartC() {
        print("  C. the same question on a panel the size this series usually has")
        guard let audit = try? DesignAudit.sweep(
            frame: .rowMarginsFixed(rowTotal: 6, otherRowTotal: 6),
            truths: TruthGrid.binomial([0.05, 0.2, 0.5, 0.8, 0.95])
        ) else {
            print("     the sweep could not be run")
            return
        }
        print("     \(conditioningWide("procedure", 20))\(conditioningWide("worst cover", 13))"
            + "\(conditioningWide("among read", 13))declined")
        for procedure in IntervalProcedure.allCases {
            guard let worst = audit.worstCoverage(procedure) else { continue }
            print("     \(conditioningWide(procedure.label, 20))"
                + "\(conditioningWide(CostFormatting.percent(worst.actualCoverage), 13))"
                + "\(conditioningWide(CostFormatting.percent(worst.coverageAmongRead), 13))"
                + CostFormatting.percent(worst.declinedMass))
        }
        print("     held at every point: \(conditioningNames(audit.proceduresHoldingTheirClaim))")
        print("     held among what they read: \(conditioningNames(audit.proceduresHoldingAmongRead))")
        print("     largest chance of a table nothing conditioning will read: "
            + CostFormatting.percent(audit.largestDeclinedMass))
        print("     The exact interval's guarantee is real and it is conditional. The condition is")
        print("     that no margin comes back zero, and on a twelve-item panel that fails often.")
        print("     Scenario 60's intervals are still the right ones to have used. What is new is")
        print("     that the ecosystem can now say what they were conditional on, and how often")
        print("     the condition fails on the panels it actually has.")
    }

    private static func conditioningNames(_ procedures: [IntervalProcedure]) -> String {
        procedures.isEmpty ? "none of them" : procedures.map(\.label).joined(separator: ", ")
    }

    private static func conditioningWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
