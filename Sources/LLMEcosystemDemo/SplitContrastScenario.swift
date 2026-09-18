import Foundation
import ProviderGatewayKit
import SequentialContrastKit
import SplitContrastKit
import TokenMeterKit

/// The identifier the sixty-ninth scenario bills its measurement against.
extension ProviderIdentifier {
    static let splitContrastHost = ProviderIdentifier("split-contrast-host")
}

extension EcosystemDemo {
    /// The sixty-ninth scenario: scenario 68 compared two prompt variants by scoring **both** on
    /// every one of 120 attempts, and the pairing was the whole of its advantage. Live traffic is
    /// never paired. A canary routes each request to one variant, so each attempt tells you about
    /// one side only, and the two sides fill up at different speeds.
    ///
    /// `SplitContrastKit` puts a time-uniform interval on the difference anyway, from the
    /// randomisation instead of the pairing, and checks the one assumption that makes it work:
    /// that the split is what the design declared. This scenario replays scenario 68's own panel
    /// through a coin, so the cost of losing the pairing is measured on the same data.
    static func runSplitContrastScenario(meter: TokenMeter) async {
        print("[split contrast scenario] live traffic is never paired. What does losing the pairing cost?")

        await splitContrastPartA()
        await splitContrastPartB()

        await meter.record(
            TokenUsage(promptTokens: 380, completionTokens: 140),
            for: ProviderIdentifier.splitContrastHost.rawValue
        )
    }

    /// The same looks scenarios 67 and 68 print, so the three can be read side by side.
    private static var splitCheckpoints: [Int] { [10, 20, 40, 60, 88, 120] }

    // MARK: - A: scenario 68's panel, with half of every attempt thrown away

    private static func splitContrastPartA() async {
        print("  A. scenario 68's 120 paired attempts, each routed to one variant by a seeded 50/50 coin")
        let paired = pairedPanelStream()
        let routed = liveSplit(of: paired, assignment: 0.5, seed: 69)
        guard let design = try? SplitDesign(assignmentProbability: 0.5, centre: 0.5),
              let monitor = try? SplitContrastMonitor(design: design, referenceDifference: 0) else {
            print("     the monitor could not be built")
            return
        }
        for (index, outcome) in routed.enumerated() {
            await monitor.observe(outcome)
            guard splitCheckpoints.contains(index + 1) else { continue }
            let reading = await monitor.reading()
            print(
                "     after \(String(format: "%3d", index + 1)) attempts"
                    + "   A/B \(reading.counts.aTrials)/\(reading.counts.bTrials)"
                    + "   centred \(splitShow(reading.centred))"
                    + "   per-arm \(splitShow(reading.armwise))"
                    + "   split ok \(reading.assignment.declaredAdmissible)"
            )
        }
        await reportPairingCost(paired: paired, monitor: monitor)
    }

    /// Scenario 68's paired width against both unpaired readings of the same attempts.
    private static func reportPairingCost(paired: [PairedOutcome], monitor: SplitContrastMonitor) async {
        let tally = paired.reduce(ContrastTally.empty) { $0.appending($1) }
        guard let sequence = try? PairedContrastSequence(alpha: 0.05),
              let pairedInterval = try? sequence.interval(for: tally) else {
            print("     the paired reading could not be taken")
            return
        }
        let reading = await monitor.reading()
        print(
            "     scenario 68, both variants on every attempt: [\(splitSigned(pairedInterval.lowerBound)), "
                + "\(splitSigned(pairedInterval.upperBound))]   width \(splitFixed(pairedInterval.width))"
        )
        if let centred = reading.centred {
            print(
                "     live split, centred:   width \(splitFixed(centred.width))"
                    + "   \(String(format: "%.4f", centred.width / pairedInterval.width))x the paired width"
            )
        }
        print(
            "     live split, per-arm:   width \(splitFixed(reading.armwise.width))"
                + "   \(String(format: "%.4f", reading.armwise.width / pairedInterval.width))x the paired width"
        )
        let exclusion = await monitor.firstExclusionTrial
        print("     zero excluded by the centred interval at: \(exclusion.map(String.init) ?? "never, in 120")")
    }

    // MARK: - B: the choice to make before routing, and the assumption it rests on

    private static func splitContrastPartB() async {
        print("  B. by enumeration: which interval to commit to, and what a wrong split does to it")
        let rateA = 79.0 / 120.0
        let rateB = rateA - 10.0 / 120.0
        print(
            "     panel rates A \(splitFixed(rateA))  B \(splitFixed(rateB))"
                + "  difference \(splitSigned(rateA - rateB))"
        )
        for assignment in [0.5, 0.2] {
            guard let design = try? SplitDesign(assignmentProbability: assignment, centre: 0.5),
                  let truth = try? SplitTruth(assignmentProbability: assignment, rateA: rateA, rateB: rateB),
                  let solver = try? SplitExclusionSolver(design: design, horizon: 24) else {
                print("     the width solver could not be built")
                return
            }
            let widths: SplitContrastKit.WidthComparison = solver.widths(truth: truth)
            print(
                "     split \(String(format: "%.2f", assignment)), 24 arrivals:"
                    + "   centred \(splitFixed(widths.centredExpectedWidth))"
                    + "   per-arm \(splitFixed(widths.armwiseExpectedWidth))"
                    + "   ratio \(String(format: "%.4f", widths.ratio))"
            )
        }
        await splitMismatchPricing(pooledRate: (rateA + rateB) / 2)
    }

    /// Declared 50/50, actually 40/60, and no real difference between the variants.
    private static func splitMismatchPricing(pooledRate: Double) async {
        guard let truth = try? SplitTruth(assignmentProbability: 0.4, rateA: pooledRate, rateB: pooledRate) else {
            print("     the mismatched truth could not be built")
            return
        }
        print("     declared 0.50, actually 0.40, both variants at \(splitFixed(pooledRate)), 30 arrivals:")
        for centre in [0.0, 0.5] {
            guard let design = try? SplitDesign(assignmentProbability: 0.5, centre: centre),
                  let profile = try? SplitExclusionSolver(design: design, horizon: 30).profile(truth: truth) else {
                print("     the profile could not be computed")
                return
            }
            print(
                "       centre \(String(format: "%.2f", centre))"
                    + "   phantom difference \(splitSigned(profile.impliedDifference))"
                    + "   centred false-detect \(splitFixed(profile.centredMiscoverage))"
                    + "   per-arm \(String(format: "%.3e", profile.armwiseMiscoverage))"
                    + "   split alarm \(splitFixed(profile.mismatchDetection))"
            )
        }
    }

    // MARK: - Support

    /// Routes each paired attempt to one variant with a seeded coin and keeps only that
    /// variant's outcome — what a live canary would have recorded.
    static func liveSplit(of paired: [PairedOutcome], assignment: Double, seed: UInt64) -> [SplitOutcome] {
        var coin = SplitCoin(seed: seed)
        return paired.map { outcome in
            coin.nextUnit() < assignment
                ? SplitOutcome(arm: .a, succeeded: outcome.systemA)
                : SplitOutcome(arm: .b, succeeded: outcome.systemB)
        }
    }

    private static func splitShow(_ bounds: SplitBounds?) -> String {
        bounds.map { "[\(splitSigned($0.lower)), \(splitSigned($0.upper))]" } ?? "empty"
    }

    private static func splitFixed(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func splitSigned(_ value: Double) -> String {
        String(format: "%+.6f", value)
    }
}

/// SplitMix64, so the coin lands the same way on every run.
private struct SplitCoin {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Double(mixed >> 11) / 9_007_199_254_740_992
    }
}
