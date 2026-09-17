import Foundation
import ProviderGatewayKit
import SequentialContrastKit
import TokenMeterKit

/// The identifier the sixty-eighth scenario bills its measurement against.
extension ProviderIdentifier {
    static let sequentialContrastHost = ProviderIdentifier("sequential-contrast-host")
}

extension EcosystemDemo {
    /// The sixty-eighth scenario: scenarios 65, 66 and 67 all read the same tidy panel and all
    /// asked about **one** rate. Scenario 66 asked which of two named rates it was; scenario 67
    /// asked what it is. Neither can answer the question an eval actually gets asked, which is
    /// whether the *other* prompt variant is better.
    ///
    /// `SequentialContrastKit` reads a second variant scored on the identical twelve tasks and
    /// puts a time-uniform interval on the difference. The point it makes here is not that the
    /// interval is narrower. It is that the two marginal intervals overlap for the entire run,
    /// and reading that overlap as "no difference yet" throws away the only evidence there is.
    static func runSequentialContrastScenario(meter: TokenMeter) async {
        print("[sequential contrast scenario] one rate was never the question. Which variant is better?")

        await sequentialContrastPartA()
        await sequentialContrastPartB()

        await meter.record(
            TokenUsage(promptTokens: 380, completionTokens: 140),
            for: ProviderIdentifier.sequentialContrastHost.rawValue
        )
    }

    /// Looks worth printing out of the 120 taken, matching scenario 67's checkpoints exactly so
    /// the two scenarios can be read side by side.
    private static var contrastCheckpoints: [Int] { [10, 20, 40, 60, 88, 120] }

    // MARK: - A: the same panel, now with a second variant scored on every task

    private static func sequentialContrastPartA() async {
        print("  A. variant B on the identical twelve tasks, one paired reading per attempt")
        let stream = pairedPanelStream()
        let matchesScenario65 = stream.map(\.systemA) == tidyPanelStream()
        print(
            "     variant A's half of this stream is identical to scenarios 65-67's: \(matchesScenario65)"
                + "   items \(stream.count)"
        )
        guard let monitor = try? ContrastMonitor(alpha: 0.05, referenceDifference: 0) else {
            print("     the monitor could not be built")
            return
        }
        for (index, outcome) in stream.enumerated() {
            guard (try? await monitor.observe(outcome)) != nil else {
                print("     the stream could not be folded in at attempt \(index + 1)")
                return
            }
            guard contrastCheckpoints.contains(index + 1) else { continue }
            await printContrastCheckpoint(monitor: monitor, attempts: index + 1)
        }
        await reportContrastVerdict(monitor: monitor)
    }

    private static func printContrastCheckpoint(monitor: ContrastMonitor, attempts: Int) async {
        guard let paired = try? await monitor.pairedInterval(),
              let unpaired = try? await monitor.unpairedInterval() else {
            print("     the readings could not be taken at attempt \(attempts)")
            return
        }
        let gain = unpaired.width / paired.width
        print(
            "     after \(String(format: "%3d", attempts)) attempts"
                + "   paired [\(contrastSigned(paired.lowerBound)), \(contrastSigned(paired.upperBound))]"
                + "   unpaired [\(contrastSigned(unpaired.lowerBound)), \(contrastSigned(unpaired.upperBound))]"
                + "   gain \(String(format: "%.4f", gain))x"
        )
    }

    /// The reading the unpaired construction structurally cannot produce, and the margins that
    /// explain why it cannot.
    private static func reportContrastVerdict(monitor: ContrastMonitor) async {
        let tally = await monitor.tally
        guard let paired = try? await monitor.pairedInterval(),
              let unpaired = try? await monitor.unpairedInterval(),
              let discordance = try? await monitor.paired.discordanceBounds(for: tally),
              let win = try? await monitor.paired.winBounds(for: tally) else {
            print("     the final readings could not be taken")
            return
        }
        print("     tally \(tally)")
        print(
            "     agreement \(contrastFixed(tally.agreementRate ?? 0))"
                + "   observed difference \(contrastSigned(tally.observedDifference ?? 0))"
                + "   discordance \(discordance)"
        )
        print("     who won the \(tally.discordantTrials) they disagreed on: \(win)")
        print(
            "     paired excludes zero \(paired.excludesZero)"
                + "   unpaired excludes zero \(unpaired.excludesZero)"
        )
        if let exclusion = await monitor.firstExclusionTrial {
            print(
                "     \"the two variants are the same\" stopped being admissible at attempt \(exclusion),"
                    + " and no correction is owed for the \(exclusion) looks it took to get there"
            )
        } else {
            print("     \"the two variants are the same\" is still admissible after 120 attempts")
        }
    }

    // MARK: - B: what the pairing bought, enumerated rather than simulated

    private static func sequentialContrastPartB() async {
        print("  B. what recording the pairing was worth, by enumeration rather than simulation")
        let tally = Self.panelTally()
        guard let joint = observedJoint(from: tally),
              let solver = try? ContrastExclusionSolver(alpha: 0.05) else {
            print("     the joint could not be formed")
            return
        }
        guard let miscoverage = try? solver.pairedProfile(
                  referenceDifference: joint.difference, joint: joint, horizon: 120
              ),
              let detection = try? solver.pairedProfile(
                  referenceDifference: 0, joint: joint, horizon: 120
              ),
              let unpairedDetection = try? solver.unpairedProfile(
                  referenceDifference: 0, joint: joint, horizon: 120
              ),
              let widths = try? solver.widthComparison(trials: 120, joint: joint) else {
            print("     the exact profiles could not be solved")
            return
        }
        printContrastMiscoverage(miscoverage, alpha: 0.05)
        printContrastDetection(detection, label: "paired  ")
        printContrastDetection(unpairedDetection, label: "unpaired")
        printContrastWidths(widths, joint: joint)
    }

    /// The joint the observed panel implies, which is the distribution the exact solver walks.
    private static func observedJoint(from tally: ContrastTally) -> PairedJointDistribution? {
        let total = Double(tally.trials)
        return try? PairedJointDistribution(
            bothSucceed: Double(tally.bothSucceeded) / total,
            onlyASucceeds: Double(tally.onlyASucceeded) / total,
            onlyBSucceeds: Double(tally.onlyBSucceeded) / total
        )
    }

    private static func printContrastMiscoverage(_ profile: ExactContrastProfile, alpha: Double) {
        let spent = profile.exclusionProbability / alpha
        print(
            "     exact miscoverage over all 120 looks, truth \(contrastSigned(profile.trueDifference))"
                + "   \(contrastFixed(profile.exclusionProbability))"
                + "   nominal \(contrastFixed(alpha))   \(String(format: "%.2f%%", spent * 100)) of budget"
                + "   \(profile.measuresMiscoverage ? "(miscoverage)" : "(detection)")"
        )
    }

    private static func printContrastDetection(_ profile: ExactContrastProfile, label: String) {
        let expected = profile.expectedFirstExclusionTrial.map { String(format: "%.4f", $0) } ?? "never"
        print(
            "     \(label) detection that zero is wrong within 120"
                + "   \(contrastFixed(profile.exclusionProbability))"
                + "   expected first exclusion attempt \(expected)"
        )
    }

    private static func printContrastWidths(_ widths: WidthComparison, joint: PairedJointDistribution) {
        print("     expected paired width at 120 attempts     \(contrastFixed(widths.pairedWidth))")
        print("     expected unpaired width, identical data   \(contrastFixed(widths.unpairedWidth))")
        print(
            "     pairing gain \(String(format: "%.4f", widths.pairingGain))x"
                + " at agreement \(contrastFixed(joint.agreementRate))"
                + " — the unpaired column cannot see that agreement, which is why it pays for it"
        )
    }

    // MARK: - The paired panel

    /// Per task: how many of the ten attempts both variants got, how many only A got, how many
    /// only B got, and how many neither got.
    ///
    /// The first two columns sum, task by task, to scenario 65's own success counts, so variant
    /// A's half of this stream is the identical 79-of-120 sequence scenarios 65, 66 and 67 all
    /// read. That is the only thing that makes this scenario a comparison rather than a new
    /// experiment.
    struct TaskCells {
        let both: Int
        let onlyA: Int
        let onlyB: Int
        let neither: Int
    }

    private static var panelCells: [TaskCells] {
        [
            TaskCells(both: 6, onlyA: 1, onlyB: 0, neither: 3),
            TaskCells(both: 5, onlyA: 1, onlyB: 0, neither: 4),
            TaskCells(both: 7, onlyA: 1, onlyB: 0, neither: 2),
            TaskCells(both: 4, onlyA: 1, onlyB: 1, neither: 4),
            TaskCells(both: 6, onlyA: 1, onlyB: 0, neither: 3),
            TaskCells(both: 8, onlyA: 1, onlyB: 0, neither: 1),
            TaskCells(both: 5, onlyA: 1, onlyB: 0, neither: 4),
            TaskCells(both: 6, onlyA: 1, onlyB: 0, neither: 3),
            TaskCells(both: 3, onlyA: 1, onlyB: 1, neither: 5),
            TaskCells(both: 7, onlyA: 1, onlyB: 0, neither: 2),
            TaskCells(both: 5, onlyA: 1, onlyB: 0, neither: 4),
            TaskCells(both: 5, onlyA: 1, onlyB: 0, neither: 4)
        ]
    }

    /// The paired stream, task by task, in the order the panel was recorded.
    static func pairedPanelStream() -> [PairedOutcome] {
        var stream: [PairedOutcome] = []
        for cells in panelCells {
            stream.append(contentsOf: Array(
                repeating: PairedOutcome(systemA: true, systemB: true), count: cells.both
            ))
            stream.append(contentsOf: Array(
                repeating: PairedOutcome(systemA: true, systemB: false), count: cells.onlyA
            ))
            stream.append(contentsOf: Array(
                repeating: PairedOutcome(systemA: false, systemB: true), count: cells.onlyB
            ))
            stream.append(contentsOf: Array(
                repeating: PairedOutcome(systemA: false, systemB: false), count: cells.neither
            ))
        }
        return stream
    }

    private static func panelTally() -> ContrastTally {
        pairedPanelStream().reduce(ContrastTally.empty) { $0.appending($1) }
    }

    private static func contrastFixed(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func contrastSigned(_ value: Double) -> String {
        String(format: "%+.6f", value)
    }
}
