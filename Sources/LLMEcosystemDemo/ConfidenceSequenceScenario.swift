import ConfidenceSequenceKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the sixty-seventh scenario bills its measurement against.
extension ProviderIdentifier {
    static let confidenceSequenceHost = ProviderIdentifier("confidence-sequence-host")
}

extension EcosystemDemo {
    /// The sixty-seventh scenario: scenario 66 pointed an SPRT at scenario 65's tidy panel and
    /// got a decision out of it — but only because both hypotheses were named before the first
    /// attempt was read. `SequentialBoundKit` answers "which of these two rates", and its answer
    /// is one of two words. It cannot answer "what is the rate", and a boundary that accepts the
    /// null at 0.60 has said nothing about 0.72.
    ///
    /// `ConfidenceSequenceKit` reads the *same* stream and answers that question instead: a
    /// Robbins beta-mixture martingale whose interval is valid at **every** look, so the whole
    /// 120-reading sequence covers the truth simultaneously with probability `1 - alpha`. No
    /// hypothesis is named up front, and no correction is owed for having looked 120 times.
    static func runConfidenceSequenceScenario(meter: TokenMeter) async {
        print("[confidence sequence scenario] the SPRT said which of two. This one says what the rate is.")

        await confidenceSequencePartA()
        await confidenceSequencePartB()

        await meter.record(
            TokenUsage(promptTokens: 360, completionTokens: 130),
            for: ProviderIdentifier.confidenceSequenceHost.rawValue
        )
    }

    /// The 0.80 target scenario 66's boundary named as its alternative — the rate the panel is
    /// advertised at, and the one this scenario watches leave the interval.
    private static var advertisedRate: Double { 0.80 }
    /// The 0.60 null that same boundary accepted at trial 88.
    private static var sprtNullRate: Double { 0.60 }
    /// Looks worth printing out of the 120 taken: early, at the SPRT's stopping trial, and at the end.
    private static var confidenceCheckpoints: [Int] { [10, 20, 40, 60, 88, 120] }

    // MARK: - A: one interval per look, over the stream scenario 66 already decided on

    private static func confidenceSequencePartA() async {
        print("  A. scenario 65's tidy panel again, one anytime-valid interval per attempt")
        guard let sequence = try? MixtureConfidenceSequence(alpha: 0.05),
              let monitor = try? ConfidenceSequenceMonitor(sequence: sequence, referenceRate: advertisedRate) else {
            print("     the sequence could not be built")
            return
        }
        print(
            "     alpha \(confidenceFixed(sequence.alpha))   uniform Beta(1, 1) prior"
                + "   log evidence threshold \(confidenceFixed(sequence.logEvidenceThreshold))"
        )
        let stream = tidyPanelStream()
        for (index, outcome) in stream.enumerated() {
            guard let interval = try? await monitor.observe(outcome) else {
                print("     the stream could not be folded in at attempt \(index + 1)")
                return
            }
            guard confidenceCheckpoints.contains(index + 1) else { continue }
            printCheckpoint(interval)
        }
        await reportAdmissibility(monitor: monitor)
    }

    private static func printCheckpoint(_ interval: AnytimeInterval) {
        let observed = interval.observedRate.map(confidenceFixed) ?? "  n/a   "
        print(
            "     after \(String(format: "%3d", interval.trials)) attempts"
                + "   [\(confidenceFixed(interval.lowerBound)), \(confidenceFixed(interval.upperBound))]"
                + "   width \(confidenceFixed(interval.width))   observed \(observed)"
        )
    }

    /// The complementary reading: the trial the advertised rate stopped being admissible, and the
    /// band that is still admissible once the SPRT has already stopped.
    private static func reportAdmissibility(monitor: ConfidenceSequenceMonitor) async {
        guard let final = try? await monitor.interval() else {
            print("     the final interval could not be read")
            return
        }
        if let exclusion = await monitor.firstExclusionTrial {
            print(
                "     advertised \(confidenceFixed(advertisedRate)) left the interval at trial \(exclusion)"
                    + " and no correction is owed for the \(exclusion) looks it took to get there"
            )
        } else {
            print("     advertised \(confidenceFixed(advertisedRate)) is still admissible after 120 attempts")
        }
        let nullVerdict = final.contains(sprtNullRate) ? "still admissible" : "excluded"
        print(
            "     the SPRT accepted the null \(confidenceFixed(sprtNullRate)) at trial 88;"
                + " it is \(nullVerdict) here — and so is every rate up to \(confidenceFixed(final.upperBound))."
        )
        print("     accepting a null is not a measurement of the rate. The interval is.")
    }

    // MARK: - B: what the anytime guarantee actually costs, enumerated rather than simulated

    private static func confidenceSequencePartB() async {
        print("  B. the price of looking 120 times, by enumeration rather than simulation")
        let pooled = 79.0 / 120.0
        guard let sequence = try? MixtureConfidenceSequence(alpha: 0.05) else {
            print("     the sequence could not be built")
            return
        }
        let solver = ExclusionSolver(sequence: sequence)
        guard let miscoverage = try? solver.profile(referenceRate: pooled, trueRate: pooled, horizon: 120),
              let detection = try? solver.profile(referenceRate: advertisedRate, trueRate: pooled, horizon: 120),
              let anytimeWidth = try? solver.expectedIntervalWidth(trials: 120, trueRate: pooled) else {
            print("     the exact profile could not be solved")
            return
        }
        printMiscoverage(miscoverage, alpha: sequence.alpha)
        printDetection(detection)
        printWidthPremium(anytimeWidth: anytimeWidth, pooled: pooled, alpha: sequence.alpha)
    }

    private static func printMiscoverage(_ profile: ExactExclusionProfile, alpha: Double) {
        let spent = profile.exclusionProbability / alpha
        print(
            "     exact miscoverage over all 120 looks, truth \(confidenceFixed(profile.trueRate))"
                + "   \(confidenceFixed(profile.exclusionProbability))"
                + "   nominal alpha \(confidenceFixed(alpha))   \(String(format: "%.2f%%", spent * 100)) of budget"
        )
    }

    private static func printDetection(_ profile: ExactExclusionProfile) {
        let expected = profile.expectedFirstExclusionTrial.map { String(format: "%.4f", $0) } ?? "never"
        print(
            "     detecting advertised \(confidenceFixed(profile.referenceRate)) is wrong within 120"
                + "   \(confidenceFixed(profile.exclusionProbability))"
                + "   expected first exclusion trial \(expected)"
        )
    }

    /// The comparison the package deliberately refuses to ship: a fixed-sample Wald width,
    /// `2 * z * sqrt(p(1-p)/n)`, valid at exactly one sample size and at exactly one look.
    private static func printWidthPremium(anytimeWidth: Double, pooled: Double, alpha: Double) {
        let quantile = normalUpperQuantile(tail: alpha / 2)
        let wald = 2 * quantile * (pooled * (1 - pooled) / 120).squareRoot()
        print("     expected anytime width at 120 trials     \(confidenceFixed(anytimeWidth))")
        print(
            "     Wald fixed-sample width (z \(confidenceFixed(quantile)))"
                + "    \(confidenceFixed(wald))"
        )
        print(
            "     premium \(String(format: "%+.6f", anytimeWidth - wald))"
                + "   ratio \(String(format: "%.4f", anytimeWidth / wald))x"
                + " — the price of 120 looks instead of one"
        )
    }

    /// The two-sided normal quantile, bisected out of `erfc` rather than pasted in as a constant,
    /// so the Wald width above is derived here and not borrowed from a package that declines to
    /// compute it.
    private static func normalUpperQuantile(tail: Double) -> Double {
        var low = 0.0
        var high = 10.0
        for _ in 0..<200 {
            let mid = 0.5 * (low + high)
            if erfc(mid / 2.0.squareRoot()) / 2 > tail {
                low = mid
            } else {
                high = mid
            }
        }
        return 0.5 * (low + high)
    }

    private static func confidenceFixed(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
