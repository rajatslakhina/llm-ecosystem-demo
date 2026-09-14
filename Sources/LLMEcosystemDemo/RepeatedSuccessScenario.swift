import Foundation
import ProviderGatewayKit
import RepeatedSuccessKit
import TokenMeterKit

/// The identifier the sixty-fifth scenario bills its measurement against.
extension ProviderIdentifier {
    static let repeatedSuccessHost = ProviderIdentifier("repeated-success-host")
}

extension EcosystemDemo {
    /// The sixty-fifth scenario: **every pass rate this demo has ever printed was a
    /// single number, and a single number stops being enough the moment you ask about
    /// more than one attempt.**
    ///
    /// Two eval panels with an identical headline rate give different answers to "does it
    /// succeed on all five attempts", and the pooled rate cannot tell them apart. This
    /// scenario measures the difference rather than describing it, and then shows the
    /// exact bound the earlier statistical packages taught this series to reach for
    /// failing outright when it is pointed at a panel instead of a task.
    static func runRepeatedSuccessScenario(meter: TokenMeter) async {
        print("[repeated success scenario] the pass rate stops being enough at k > 1")

        await repeatedSuccessPartA()
        await repeatedSuccessPartB()
        await repeatedSuccessPartC()

        await meter.record(
            TokenUsage(promptTokens: 380, completionTokens: 140),
            for: ProviderIdentifier.repeatedSuccessHost.rawValue
        )
    }

    // MARK: - Fixtures

    /// Twelve tasks of one difficulty. 79 successes of 120.
    private static func tidyPanel() -> AttemptPanel? {
        buildPanel(prefix: "tidy", successes: [7, 6, 8, 5, 7, 9, 6, 7, 4, 8, 6, 6])
    }

    /// Six the agent nearly always finishes, six it nearly always fails. Also 79 of 120.
    private static func mixedPanel() -> AttemptPanel? {
        buildPanel(prefix: "mixed", successes: [10, 10, 10, 9, 10, 10, 3, 4, 3, 3, 3, 4])
    }

    private static func buildPanel(prefix: String, successes: [Int]) -> AttemptPanel? {
        try? AttemptPanel(successes.enumerated().map { index, count in
            TaskAttempts(identifier: "\(prefix)-\(index + 1)", attempts: 10, successes: count)
        })
    }

    // MARK: - A: one headline rate, two different answers

    private static func repeatedSuccessPartA() async {
        print("  A. two panels, one pass rate, two answers at k = 5")
        guard let tidy = tidyPanel(), let mixed = mixedPanel() else {
            print("     the panels could not be read")
            return
        }
        let tidyRate = RepeatedSuccessFormat.probability(tidy.pooledRate)
        let mixedRate = RepeatedSuccessFormat.probability(mixed.pooledRate)
        print("     tidy panel pooled rate   \(tidyRate)   (\(tidy.totalSuccesses)/\(tidy.totalAttempts))")
        print("     mixed panel pooled rate  \(mixedRate)   (\(mixed.totalSuccesses)/\(mixed.totalAttempts))")

        for (name, panel) in [("tidy ", tidy), ("mixed", mixed)] {
            let estimator = RepeatedSuccessEstimator(panel: panel)
            guard let all = try? await estimator.allSucceed(repetitions: 5) else {
                print("     \(name) all-of-5 could not be estimated")
                continue
            }
            let naive = RepeatedSuccessFormat.probability(all.pooled)
            let honest = RepeatedSuccessFormat.probability(all.unbiased)
            print("     \(name) all-of-5     naive \(naive)   unbiased \(honest)"
                + "   gap \(RepeatedSuccessFormat.signed(all.gap))")
        }
        print("     the naive answer is identical for both panels. The truth is 3.7x apart.")
    }

    // MARK: - B: what the gap is actually measuring

    private static func repeatedSuccessPartB() async {
        print("  B. at k = 2 the gap has a closed form, and the two questions mirror each other")
        for (name, maybePanel) in [("tidy ", tidyPanel()), ("mixed", mixedPanel())] {
            guard let panel = maybePanel else { continue }
            let estimator = RepeatedSuccessEstimator(panel: panel)
            guard let all = try? await estimator.allSucceed(repetitions: 2),
                  let any = try? await estimator.anySucceeds(repetitions: 2),
                  let reading = await estimator.dispersion() else {
                print("     \(name) could not be read")
                continue
            }
            let mirror = abs(all.gap + any.gap)
            let closed = abs(all.gap - reading.excessDispersion)
            print("     \(name) all-of-2 gap \(RepeatedSuccessFormat.signed(all.gap))"
                + "   any-of-2 gap \(RepeatedSuccessFormat.signed(any.gap))")
            print("           closed form  \(RepeatedSuccessFormat.signed(reading.excessDispersion))"
                + "   |sum| \(String(format: "%.2e", mirror))   |diff| \(String(format: "%.2e", closed))")
        }
        print("     dispersion beyond binomial noise, exactly — not an approximation.")
    }

    // MARK: - C: the exact bound, pointed at the wrong thing

    private static func repeatedSuccessPartC() async {
        print("  C. an exact bound that is sound for one task, aimed at a panel")
        guard let mixed = mixedPanel() else { return }
        let estimator = RepeatedSuccessEstimator(panel: mixed)
        guard let any = try? await estimator.anySucceeds(repetitions: 3),
              let bound = try? ReliabilityBound.singleTaskAnyLowerBound(
                  successes: mixed.totalSuccesses,
                  attempts: mixed.totalAttempts,
                  repetitions: 3,
                  level: 0.95
              ),
              let panelBound = try? ReliabilityBound.panelMeanLowerBound(
                  estimate: any.unbiased, taskCount: any.tasksUsed, level: 0.95
              ) else {
            print("     the bounds could not be computed")
            return
        }
        print("     unbiased any-of-3          \(RepeatedSuccessFormat.probability(any.unbiased))")
        print("     95% single-task bound      \(RepeatedSuccessFormat.probability(bound))")
        print("     95% panel bound            \(RepeatedSuccessFormat.probability(panelBound))")
        if bound > any.unbiased {
            let overshoot = RepeatedSuccessFormat.probability(bound - any.unbiased)
            print("     the single-task bound sits \(overshoot) ABOVE the quantity it bounds.")
            print("     a 95% lower bound above its own target is not conservative. It is broken,")
            print("     and it broke in the direction that flatters the system.")
        }
    }
}
