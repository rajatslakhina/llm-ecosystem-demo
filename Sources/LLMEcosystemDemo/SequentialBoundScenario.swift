import Foundation
import ProviderGatewayKit
import SequentialBoundKit
import TokenMeterKit

/// The identifier the sixty-sixth scenario bills its measurement against.
extension ProviderIdentifier {
    static let sequentialBoundHost = ProviderIdentifier("sequential-bound-host")
}

extension EcosystemDemo {
    /// The sixty-sixth scenario: every exact test this series has built — Fisher, Barnard's
    /// unconditional test, the total-fixed design, Clopper-Pearson — answers one question,
    /// once. Consult the same interval every day, the way a CI pipeline checks today's eval
    /// pass rate against yesterday's, and the false-alarm rate it promised at construction is
    /// no longer the one being paid. `SequentialBoundKit` is built for the repeated look: a
    /// boundary valid at any stopping time, and an exact audit of what its own `alpha`/`beta`
    /// are actually worth once Wald's overshoot approximation is accounted for by full
    /// enumeration rather than trusted at face value.
    static func runSequentialBoundScenario(meter: TokenMeter) async {
        print("[sequential bound scenario] does the boundary hold the error rate it claims?")

        await sequentialBoundPartA()
        await sequentialBoundPartB()

        await meter.record(
            TokenUsage(promptTokens: 340, completionTokens: 120),
            for: ProviderIdentifier.sequentialBoundHost.rawValue
        )
    }

    // MARK: - A: the exact audit against Wald's own closed-form approximation

    private static func sequentialBoundPartA() async {
        print("  A. auditing Wald's boundary instead of trusting alpha/beta at face value")
        guard let boundary = try? SPRTBoundary(nullRate: 0.6, alternativeRate: 0.8, alpha: 0.05, beta: 0.05) else {
            print("     the boundary could not be built")
            return
        }
        guard let exact = try? OperatingCharacteristicSolver.solve(boundary: boundary, horizon: 200) else {
            print("     the exact operating characteristics could not be solved")
            return
        }
        print(
            "     nominal alpha 0.050000   exact Type-I  \(String(format: "%.6f", exact.exactTypeIError))"
                + "   continuation \(String(format: "%.6f", exact.continuationUnderNull))"
        )
        print(
            "     nominal beta  0.050000   exact Type-II \(String(format: "%.6f", exact.exactTypeIIError))"
                + "   continuation \(String(format: "%.6f", exact.continuationUnderAlternative))"
        )
        printWaldComparison(boundary: boundary, exact: exact)
    }

    /// Wald's own classical ASN formula — `E[N|theta] = [P(accept null|theta)*lowerLogBound +
    /// P(accept alt|theta)*upperLogBound] / E[Z|theta]`, reading the two acceptance
    /// probabilities off the *nominal* alpha/beta rather than the exact ones — under the null
    /// that is `(1-alpha, alpha)`, under the alternative `(beta, 1-beta)`. `E[Z|theta]` is the
    /// per-step log-likelihood drift under the rate in question.
    /// `OperatingCharacteristicSolver` deliberately does not expose this: it is the closed-form
    /// approximation the exact enumeration exists to check, not a reading worth reusing.
    private static func printWaldComparison(boundary: SPRTBoundary, exact: ExactOperatingCharacteristics) {
        let successZ = boundary.logLikelihoodIncrement(forSuccess: true)
        let failureZ = boundary.logLikelihoodIncrement(forSuccess: false)
        let waldNull = waldASN(underNull: true, boundary: boundary, successZ: successZ, failureZ: failureZ)
        let waldAlt = waldASN(underNull: false, boundary: boundary, successZ: successZ, failureZ: failureZ)
        print(
            "     Wald ASN | null \(String(format: "%.6f", waldNull))"
                + "   exact \(String(format: "%.6f", exact.expectedSampleSizeUnderNull))"
                + "   gap \(String(format: "%+.6f", exact.expectedSampleSizeUnderNull - waldNull))"
        )
        print(
            "     Wald ASN | alt  \(String(format: "%.6f", waldAlt))"
                + "   exact \(String(format: "%.6f", exact.expectedSampleSizeUnderAlternative))"
                + "   gap \(String(format: "%+.6f", exact.expectedSampleSizeUnderAlternative - waldAlt))"
        )
    }

    private static func waldASN(
        underNull: Bool, boundary: SPRTBoundary, successZ: Double, failureZ: Double
    ) -> Double {
        let rate = underNull ? boundary.nullRate : boundary.alternativeRate
        let meanZ = rate * successZ + (1 - rate) * failureZ
        guard meanZ != 0 else { return .infinity }
        let acceptNullProbability = underNull ? (1 - boundary.alpha) : boundary.beta
        let acceptAlternativeProbability = underNull ? boundary.alpha : (1 - boundary.beta)
        let numerator = acceptNullProbability * boundary.lowerLogBound
            + acceptAlternativeProbability * boundary.upperLogBound
        return numerator / meanZ
    }

    // MARK: - B: the live monitor, watching a real eval panel instead of a synthetic draw

    private static func sequentialBoundPartB() async {
        print("  B. the live monitor watching scenario 65's own tidy panel, one attempt at a time")
        guard let boundary = try? SPRTBoundary(nullRate: 0.6, alternativeRate: 0.8, alpha: 0.05, beta: 0.05) else {
            print("     the boundary could not be built")
            return
        }
        let monitor = SPRTMonitor(boundary: boundary)
        let stream = tidyPanelStream()

        var decision = SPRTDecision.continueSampling
        for outcome in stream {
            decision = await monitor.record(success: outcome)
            if decision != .continueSampling { break }
        }
        let trials = await monitor.trialCount
        let successes = await monitor.successCount
        print("     stream: \(stream.count) attempts total, \(stream.filter { $0 }.count) successes (pooled 0.658333)")
        report(decision: decision, trials: trials, successes: successes, streamCount: stream.count)
    }

    private static func report(decision: SPRTDecision, trials: Int, successes: Int, streamCount: Int) {
        switch decision {
        case .continueSampling:
            print(
                "     after all \(trials) attempts the boundary still has not decided —"
                    + " a fixed read of the whole panel was not enough either"
            )
        case .acceptNull, .acceptAlternative:
            let saved = streamCount - trials
            print(
                "     decided \(decision) after \(trials) of \(streamCount) attempts (\(successes) successes) —"
                    + " \(saved) attempts a full-panel read would still have spent"
            )
        }
    }

    /// The same twelve-task, 79-of-120 tidy panel scenario 65 builds — flattened task-by-task
    /// into a 0/1 stream in the recorded order, so this scenario watches a real eval panel
    /// rather than a synthetic Bernoulli draw.
    private static func tidyPanelStream() -> [Bool] {
        let taskSuccesses = [7, 6, 8, 5, 7, 9, 6, 7, 4, 8, 6, 6]
        var stream: [Bool] = []
        for successes in taskSuccesses {
            stream.append(contentsOf: Array(repeating: true, count: successes))
            stream.append(contentsOf: Array(repeating: false, count: 10 - successes))
        }
        return stream
    }
}
