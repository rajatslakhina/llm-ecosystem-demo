import EffectiveComparisonKit
import EffectiveVoteKit
import Foundation
import ObservedNullKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the fifty-fourth scenario bills its resampling against.
extension ProviderIdentifier {
    static let observedNullHost = ProviderIdentifier("observed-null-host")
}

extension EcosystemDemo {
    /// The fifty-fourth scenario: **scenario 53 measured the panel's shape. This one stops
    /// assuming the shape and resamples the panel.**
    ///
    /// Scenario 53 corrected the family of comparisons for its dependence, deriving that
    /// dependence from `PanelDesign` — panel geometry says two comparisons sharing a judge are
    /// correlated at exactly one half, and the structural source buys full credit because a
    /// derived design is not a guess.
    ///
    /// It is not a guess about the *design*. It is still a claim about a *distribution*, and
    /// two assumptions ride underneath it: that the family's null is Gaussian, and that a
    /// correlation of one half is something these judges' agreement rates can actually produce.
    /// This panel has observations. Both can be checked instead of assumed, and one of them
    /// fails.
    static func runObservedNullScenario(meter: TokenMeter) async {
        print("[observed null scenario] the null scenario 53 drew from, resampled instead")

        let history = panelHistory()
        guard let panel = observedPanel(from: history) else { return }
        let family = AgreementFamily(observations: panel)
        guard let ledger = try? ObservedNullLedger(family: family, level: 0.05) else { return }

        nullPartA(family)
        await nullPartB(family, ledger)
        await nullPartC(family, ledger)
        await nullPartD(family, ledger)

        await meter.record(
            TokenUsage(promptTokens: 520, completionTokens: 150),
            for: ProviderIdentifier.observedNullHost.rawValue
        )
    }

    /// The panel as a grid of "was this judge right on this item", which is the same basis
    /// `EffectiveVoteKit` counts agreement on. A judge that was never wrong is refused rather
    /// than carried, because its agreement rate has no variance to resample.
    private static func observedPanel(from history: ObservationHistory) -> PanelObservations? {
        let judges = history.judges
        let rows = history.observations.map { observation in
            judges.map { observation.verdicts[$0] == observation.truth }
        }
        do {
            return try PanelObservations(judgeIdentifiers: judges.map(\.description), grades: rows)
        } catch let error as ObservedNullError {
            print("     no resampling here: \(error.description)")
            print("     \(error.remedy)")
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - A: the page, as the panel actually graded it

    private static func nullPartA(_ family: AgreementFamily) {
        let panel = family.observations
        print("  A. the page, from the grades rather than from the geometry")
        print("     \(panel.judgeCount) judges, \(panel.itemCount) items, "
            + "\(family.size) pairwise readings")
        for judge in 0..<panel.judgeCount {
            print("     \(nullWide(panel.judgeIdentifiers[judge]))"
                + "correct on \(widthDp(panel.rate(ofJudge: judge)))")
        }
        let largest = family.largestPair
        print("     largest reading \(widthDp(family.largestReading)) at "
            + "\(panel.judgeIdentifiers[largest.low]) x \(panel.judgeIdentifiers[largest.high])")
        print("     it agreed \(widthDp(family.agreementRate(for: largest))) against a chance "
            + "rate of \(widthDp(family.independenceRate(for: largest)))")
    }

    // MARK: - B: two nulls for one page

    private static func nullPartB(_ family: AgreementFamily, _ ledger: ObservedNullLedger) async {
        print("  B. the fitted null, and the resampled one")
        guard let copula = try? GaussianCopulaNullEstimator(),
              let fitted = try? await ledger.threshold(from: copula),
              let resampled = try? await ledger.threshold(from: ObservedNullEstimator.standard) else {
            print("     this page has a pair that never disagreed, so no matrix can be fitted to it")
            print("     the bootstrap needs no matrix and would still answer")
            return
        }
        for (label, priced) in [("Gaussian copula", fitted), ("item bootstrap", resampled)] {
            print("     \(nullWide(label))ceiling \(widthDp(priced.ceiling.value))"
                + "   m_eff \(widthDp(priced.effectiveCount))"
                + "   survivors \(priced.survivors(in: family).count)/\(family.size)")
        }
        let ratio = fitted.perComparison / resampled.perComparison
        print("     the fitted threshold is \(widthDp(ratio))x the resampled one, "
            + (ratio > 1 ? "which publishes more" : "which publishes less"))
    }

    // MARK: - C: the readings this page can actually produce

    private static func nullPartC(_ family: AgreementFamily, _ ledger: ObservedNullLedger) async {
        print("  C. \(family.observations.itemCount) items is a coarse lattice")
        let grid = await ledger.attainableGrid()
        guard let loose = try? ObservedNullLedger(family: family, level: 0.05, snapsToGrid: false),
              let raw = try? await loose.ceiling(from: ObservedNullEstimator.standard),
              let snapped = try? await ledger.ceiling(from: ObservedNullEstimator.standard) else {
            return
        }
        print("     \(nullWide("attainable readings"))\(grid.count)")
        print("     \(nullWide("bootstrap ceiling, raw"))\(widthDp(raw.value))")
        print("     \(nullWide("snapped to the grid"))\(widthDp(snapped.value))"
            + "   moved \(widthDp(snapped.snapDistance))")
        if let gap = grid.gap(around: raw.value) {
            print("     it sat inside \(show(gap)), a gap of "
                + "\(widthDp(gap.upperBound - gap.lowerBound)) that selects one set of readings")
        } else {
            print("     the raw quantile was already a reading this panel can produce")
        }
    }

    // MARK: - D: the correlation scenario 53 spent, checked against these judges

    private static func nullPartD(_ family: AgreementFamily, _ ledger: ObservedNullLedger) async {
        print("  D. can these judges produce the correlation the design assumes?")
        var structural = Array(
            repeating: Array(repeating: 0.0, count: family.size),
            count: family.size
        )
        var overlapping = 0
        for row in 0..<family.size {
            structural[row][row] = 1
            for column in 0..<family.size where column != row {
                let shares = family.pairs[row].overlaps(family.pairs[column])
                structural[row][column] = shares ? 0.5 : 0
                if shares, column > row { overlapping += 1 }
            }
        }
        print("     \(nullWide("overlapping entries at 1/2"))\(overlapping)")
        do {
            let offending = try await ledger.unattainableEntries(in: structural)
            print("     \(nullWide("unattainable for this panel"))\(offending.count)")
            if let worst = offending.max(by: { $0.excess < $1.excess }) {
                print("     worst excess \(widthDp(worst.excess)) at \(worst.pair) — a "
                    + "correlation matrix has no marginals in it to object")
            } else {
                print("     every one of them is reachable here, so the structural matrix stands")
            }
        } catch let error as ObservedNullError {
            print("     the question cannot be asked on this page: \(error.description)")
            print("     a bound needs two marginals with variance, and this pair has none —")
            print("     the same degeneracy that leaves the fitted route with no matrix at all")
        } catch {
            print("     the audit failed: \(error)")
        }
        for scheme in [ResamplingScheme.judgeLabelPermutation, .itemPermutation] {
            guard let estimator = try? ObservedNullEstimator(scheme: scheme, draws: 2_000) else {
                continue
            }
            do {
                _ = try await ledger.threshold(from: estimator)
                print("     \(scheme.label): spent without refusal")
            } catch let error as ObservedNullError {
                print("     \(nullWide(scheme.label))refused — \(error.description)")
            } catch {
                continue
            }
        }
    }

    /// The same 30-wide column the neighbouring scenarios lay their numbers against.
    private static func nullWide(_ text: String) -> String {
        text.padding(toLength: 30, withPad: " ", startingAt: 0)
    }
}
