import AssociationFitKit
import AssociationTransportKit
import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the fifty-ninth scenario bills its measurement against.
extension ProviderIdentifier {
    static let associationTransportHost = ProviderIdentifier("association-transport-host")
}

extension EcosystemDemo {
    /// The fifty-ninth scenario: **scenario 58 chose a structure. This one reads the corpus's own.**
    ///
    /// Every construction in scenarios 50 through 58 starts from a structure somebody named —
    /// independence, uniform association, a diagonal weight — and asks what table carries it.
    /// The corpus has never been asked what structure it already has, because until now nothing
    /// here could measure one, say how precisely it was measured, or carry it somewhere else.
    static func runAssociationTransportScenario(meter: TokenMeter) async {
        print("[association transport scenario] the structure the corpus already has")

        let history = panelHistory()
        guard let observed = transportPanel(history) else {
            print("     no pair of judges gives a square joint panel")
            return
        }

        transportPartA(observed)
        transportPartB(observed)
        transportPartC(observed)
        transportPartD(observed)

        await meter.record(
            TokenUsage(promptTokens: 430, completionTokens: 150),
            for: ProviderIdentifier.associationTransportHost.rawValue
        )
    }

    /// The joint panel of the first two judges: what each pair of verdicts actually was.
    ///
    /// The difference from scenario 58, which took the same two judges' **margins**. Margins say
    /// how often each judge said each thing. This says how often they said them together, and that
    /// is the only place an association lives.
    private static func transportPanel(_ history: ObservationHistory) -> ObservedPanel? {
        let judges = history.judges
        guard judges.count >= 2 else { return nil }
        let size = Verdict.allCases.count
        for left in 0..<(judges.count - 1) {
            for right in (left + 1)..<judges.count {
                var counts = [[Int]](repeating: [Int](repeating: 0, count: size), count: size)
                for observation in history.observations {
                    guard let first = observation.verdicts[judges[left]],
                          let second = observation.verdicts[judges[right]],
                          let row = Verdict.allCases.firstIndex(of: first),
                          let column = Verdict.allCases.firstIndex(of: second) else { continue }
                    counts[row][column] += 1
                }
                guard let panel = try? ObservedPanel(counts: counts),
                      panel.rowMargin.counts != panel.columnMargin.counts else { continue }
                print("     pair \(judges[left]) / \(judges[right])")
                return panel
            }
        }
        return nil
    }

    // MARK: - A: what is actually in the table

    private static func transportPartA(_ panel: ObservedPanel) {
        print("  A. the joint panel, which is where an association lives")
        for line in panel.counts {
            print("     " + line.map { transportWide(String($0), 6) }.joined())
        }
        print("     \(panel.itemCount) items, margins \(panel.rowMargin.counts) "
            + "and \(panel.columnMargin.counts)")
        print("     agreement \(transportDp(panel.agreementRate)), "
            + "smallest cell \(panel.smallestCell), "
            + "\(panel.emptyCells.count) of \(panel.categoryCount * panel.categoryCount) cells empty")
        do {
            _ = try StructureMeasurement.measure(panel, policy: .refuse)
            print("     no empty cell — the structure can be read without a decision")
        } catch {
            print("     read without a decision, it refuses: \(error)")
            print("     which is the honest answer: this corpus has never seen an abstention, so")
            print("     the third category is empty and nothing in the counts says whether that is")
            print("     a rule these judges follow or a case they have not met yet")
        }
    }

    // MARK: - B: the two readings, and what each one can carry

    private static func transportPartB(_ panel: ObservedPanel) {
        print("  B. the same panel under both readings of its empty cells")
        let target = transportTarget(panel)
        for policy in [ZeroPolicy.structural, .haldaneAnscombe] {
            guard let structure = try? StructureMeasurement.measure(panel, policy: policy) else {
                print("     \(transportWide(policy.label, 18))could not be measured")
                continue
            }
            let measured = "\(structure.readings.count)/\(structure.blockCount) blocks"
            do {
                let report = try AssociationTransport.carry(
                    structure, onto: target, and: target
                )
                print("     \(transportWide(policy.label, 18))\(transportWide(measured, 14))"
                    + "carried, agreement \(transportDp(report.transportedAgreementRate)) "
                    + "(shift \(transportDp(report.agreementShift)))")
            } catch {
                print("     \(transportWide(policy.label, 18))\(transportWide(measured, 14))"
                    + "refused: \(error)")
            }
        }
        print("     a count of zero read as a rule cannot be seeded at all when a whole category")
        print("     is empty; read as an absence, the same panel transports without complaint")
    }

    // MARK: - C: how precisely this corpus measured its own structure

    private static func transportPartC(_ panel: ObservedPanel) {
        print("  C. the precision behind the number")
        guard let structure = try? StructureMeasurement.measure(panel) else {
            print("     nothing measurable")
            return
        }
        print("     \(transportWide("block", 9))\(transportWide("odds", 11))"
            + "\(transportWide("lower", 11))\(transportWide("upper", 11))"
            + "\(transportWide("covers 1?", 11))items to clear it")
        for reading in structure.readings {
            let needed = reading.itemsRequiredToDistinguish()
            print("     \(transportWide(reading.block.label, 9))"
                + "\(transportWide(transportDp(reading.oddsRatio), 11))"
                + "\(transportWide(transportDp(reading.lower), 11))"
                + "\(transportWide(transportDp(reading.upper), 11))"
                + "\(transportWide(reading.coversIndependence ? "yes" : "no", 11))"
                + (needed.map { "\($0)" } ?? "no size — the ratio is exactly 1"))
        }
        print("     \(structure.distinguishableCount) of \(structure.blockCount) blocks clear "
            + "independence at \(structure.confidence.label) on \(panel.itemCount) items")
        print("     every coefficient scenarios 50-58 publish over this corpus rests on a")
        print("     structure this corpus measured to within a factor of "
            + "\(transportDp(structure.widestIntervalRatio, 1))")
    }

    // MARK: - D: what the correction moved, on a panel that is mostly correction

    private static func transportPartD(_ panel: ObservedPanel) {
        print("  D. the invoice for the half-item that made part C possible")
        guard let structure = try? StructureMeasurement.measure(panel),
              let invoice = structure.invoice else {
            print("     no correction was applied")
            return
        }
        print("     \(invoice.entries.count) of \(structure.blockCount) blocks had a raw ratio to "
            + "compare; \(invoice.inventedBlocks.count) exist only because of the correction")
        for entry in invoice.entries {
            print("     \(transportWide(entry.block.label, 9))"
                + "raw \(transportWide(transportDp(entry.raw), 12))"
                + "corrected \(transportWide(transportDp(entry.corrected), 12))"
                + entry.direction.label)
        }
        print("     largest relative change \(transportDp(invoice.largestRelativeChange)); "
            + "\(invoice.blocksMovedAway.count) moved away, "
            + "\(invoice.blocksUnmoved.count) did not move at all")
        print("     a page quoting these ratios is quoting a prior for "
            + "\(invoice.inventedBlocks.count) of \(structure.blockCount) of them, and a moved")
        print("     number for the rest. Scenario 58 chose its structure and knew it exactly;")
        print("     this one measured the corpus's and now knows what that cost.")
    }

    /// Balanced margins to carry the measured structure onto: the same case mix, evened out.
    private static func transportTarget(_ panel: ObservedPanel) -> FitMargin {
        let size = panel.categoryCount
        let share = panel.itemCount / size
        var counts = [Int](repeating: share, count: size)
        counts[0] += panel.itemCount - share * size
        // Every count is non-negative and they sum to the panel's own item count, which the panel
        // has already established is at least two.
        return (try? FitMargin(counts: counts)) ?? panel.rowMargin
    }

    private static func transportWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func transportDp(_ value: Double, _ places: Int = 4) -> String {
        value.isNaN ? "n/a" : String(format: "%.\(places)f", value)
    }
}
