import AssociationTransportKit
import EffectiveVoteKit
import ExactAssociationKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the sixtieth scenario bills its measurement against.
extension ProviderIdentifier {
    static let exactAssociationHost = ProviderIdentifier("exact-association-host")
}

extension EcosystemDemo {
    /// The sixtieth scenario: **scenario 59 quoted intervals. This one asks what they were worth.**
    ///
    /// Scenario 59 measured the corpus's own structure and put a Woolf interval around every block
    /// of it. Woolf's standard error is a normal approximation on the log scale, valid in the limit
    /// of large counts, and this corpus has ninety-six items with five of its nine cells empty.
    /// Nothing in this ecosystem has ever said what that approximation costs here, because until
    /// now nothing here could compute the interval it approximates.
    static func runExactAssociationScenario(meter: TokenMeter) async {
        print("[exact association scenario] what scenario 59's intervals were worth")

        guard let observed = exactPanel(panelHistory()) else {
            print("     no pair of judges gives a square joint panel")
            return
        }

        exactPartA(observed)
        exactPartB(observed)
        exactPartC(observed)

        await meter.record(
            TokenUsage(promptTokens: 415, completionTokens: 145),
            for: ProviderIdentifier.exactAssociationHost.rawValue
        )
    }

    /// The same joint panel scenario 59 reads, chosen the same way.
    private static func exactPanel(_ history: ObservationHistory) -> ObservedPanel? {
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
                return panel
            }
        }
        return nil
    }

    // MARK: - A: how many of these blocks are estimable at all

    private static func exactPartA(_ panel: ObservedPanel) {
        print("  A. how many of this corpus's blocks have an odds ratio to estimate")
        guard let audit = try? ExactAssociation.audit(panel) else {
            print("     the panel could not be audited")
            return
        }
        print("     \(panel.itemCount) items, \(audit.blockCount) blocks, "
            + "\(audit.readings.count) readable, \(audit.degenerateBlocks.count) pinned by margins")
        for block in audit.degenerateBlocks {
            print("     \(exactWide(block.label, 9))margins allow exactly one table — nothing to estimate")
        }
        for reading in audit.readings {
            print("     \(exactWide(reading.position?.label ?? "", 9))"
                + "exact \(exactWide(Formatting.interval(reading.exact), 24))"
                + "\(reading.supportSize) tables allowed")
        }
        print("     scenario 59 reported an odds ratio for every one of these blocks. Three of them")
        print("     have a zero margin, so their counts are determined and no method can read an")
        print("     association off them. Those ratios were made by the half-item correction.")
    }

    // MARK: - B: the same block under both methods

    private static func exactPartB(_ panel: ObservedPanel) {
        print("  B. the readable block, exactly and asymptotically, both on the raw counts")
        guard let structure = try? StructureMeasurement.measure(panel, policy: .structural),
              let audit = try? ExactAssociation.audit(structure) else {
            print("     nothing to compare")
            return
        }
        if audit.comparisons.isEmpty {
            print("     no block is readable by both methods")
            return
        }
        print("     \(exactWide("block", 9))\(exactWide("Woolf", 24))"
            + "\(exactWide("exact", 24))\(exactWide("wider by", 10))verdict")
        for comparison in audit.comparisons {
            print("     \(exactWide(comparison.position.label, 9))"
                + "\(exactWide(Formatting.interval(comparison.asymptotic), 24))"
                + "\(exactWide(Formatting.interval(comparison.exact), 24))"
                + "\(exactWide(Formatting.decimal(comparison.understatement, places: 3), 10))"
                + (comparison.verdictAgrees ? "agree" : "DISAGREE"))
        }
        print("     \(audit.disagreementCount) of \(audit.comparisons.count) comparisons disagree; "
            + "\(audit.inventedCount) rest on a corrected count")
        print("     read structurally, no half-item is added anywhere, so this row is method")
        print("     against method rather than method against repair")
        print("     widest understatement \(Formatting.decimal(audit.widestUnderstatement, places: 3))")
    }

    // MARK: - C: what this corpus can actually distinguish

    private static func exactPartC(_ panel: ObservedPanel) {
        print("  C. the tests, and what the guarantee costs")
        guard let audit = try? ExactAssociation.audit(panel) else {
            print("     nothing to test")
            return
        }
        print("     \(exactWide("block", 9))\(exactWide("cond. MLE", 12))"
            + "\(exactWide("Fisher p", 12))\(exactWide("mid-p", 12))"
            + "\(exactWide("mid-p CI", 24))exact/mid-p")
        for reading in audit.readings {
            print("     \(exactWide(reading.position?.label ?? "", 9))"
                + "\(exactWide(reading.estimate.label, 12))"
                + "\(exactWide(Formatting.decimal(reading.fisherP, places: 6), 12))"
                + "\(exactWide(Formatting.decimal(reading.midPValue, places: 6), 12))"
                + "\(exactWide(Formatting.interval(reading.midP), 24))"
                + Formatting.decimal(reading.conservatism, places: 3))
        }
        print("     \(audit.distinguishableCount) of \(audit.blockCount) blocks clear independence")
        print("     Every coefficient scenarios 50-59 publish over this corpus is computed on a")
        print("     panel that cannot distinguish a single one of its blocks from independence —")
        print("     and three of the four were never estimable in the first place.")
    }

    private static func exactWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
