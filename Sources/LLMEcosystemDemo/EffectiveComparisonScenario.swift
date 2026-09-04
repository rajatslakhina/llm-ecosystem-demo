import EffectiveComparisonKit
import EffectiveVoteKit
import FamilyErrorKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the fifty-third scenario bills its calibration against.
extension ProviderIdentifier {
    static let effectiveComparisonHost = ProviderIdentifier("effective-comparison-host")
}

extension EcosystemDemo {
    /// The fifty-third scenario: **scenario 52 divided by six, and six was the wrong number
    /// in the other direction.**
    ///
    /// Scenario 52 counted the page — six pairs, published at a nominal 95% apiece — and
    /// corrected for it under Benjamini-Yekutieli, paying `H(6) = 2.45` because a panel's
    /// overlapping pairs do not satisfy positive regression dependence. That price is for
    /// *arbitrary* dependence. This panel's dependence is not arbitrary and is not a matter
    /// of opinion: twelve of the fifteen pairings share a judge, and the shape fixes how much
    /// that costs.
    ///
    /// `EffectiveComparisonKit` measures it. The scenario also records the distinction the
    /// package exists for, because it is the one that would have quietly gone wrong here: the
    /// spectral estimators return the panel's **rank**, a multiplicity threshold needs its
    /// **tail count**, and on this panel the rank is the smaller and therefore the flattering
    /// number.
    static func runEffectiveComparisonScenario(meter: TokenMeter) async {
        print("[effective comparison scenario] the denominator scenario 52 assumed, measured")

        let constructed = panelHistory()
        let proxied = proxyLabelledHistory(from: constructed, flipRate: 0.12)
        let estimate = EffectiveVoteEstimator(basis: .errorAgreement)
            .estimate(proxied.history, stratum: .all)
        let judges = estimate.nominalJudges

        guard let design = try? PanelDesign(judgeCount: judges),
              let matrix = try? design.correlationMatrix() else {
            print("     a panel of \(judges) has no family of comparisons to calibrate")
            return
        }

        comparisonPartA(design, matrix)
        comparisonPartB(design, matrix)
        await comparisonPartC(estimate.measuredAssociations, judgeCount: judges, matrix: matrix)
        await comparisonPartD(matrix)

        await meter.record(
            TokenUsage(promptTokens: 540, completionTokens: 160),
            for: ProviderIdentifier.effectiveComparisonHost.rawValue
        )
    }

    // MARK: - A: the two numbers everybody calls the same thing

    private static func comparisonPartA(_ design: PanelDesign, _ matrix: CorrelationMatrix) {
        print("  A. rank and tail, on the panel scenario 52 corrected")
        print("     \(design.judgeCount) judges -> \(design.comparisonCount) comparisons, "
            + "\(design.overlappingPairings)/\(design.totalPairings) pairings share a judge "
            + "(\(String(format: "%.2f", design.overlapDensity * 100))%)")
        let estimators: [any EffectiveCountEstimator] = [
            CheverudNyholt(), LiJi(), Galwey(), MeanCorrelation()
        ]
        for estimator in estimators {
            guard let count = try? estimator.checkedEstimate(for: matrix) else { continue }
            print("     \(wide(estimator.name))\(widthDp(count.value))   [\(count.question.rawValue)]")
        }
        guard let reading = try? PermutationEffectiveCount.standard.reading(for: matrix) else { return }
        print("     \(wide("Permutation"))\(widthDp(reading.count.value))   "
            + "[\(reading.count.question.rawValue)]   ceiling |z| \(widthDp(reading.ceiling))")
        print("     the rank is what the design has (\(design.designRank) judge effects). the tail")
        print("     count is what a threshold is a statement about, and only it may be spent.")
    }

    // MARK: - B: what scenario 52 paid, and what the shape actually costs

    private static func comparisonPartB(_ design: PanelDesign, _ matrix: CorrelationMatrix) {
        print("  B. what Benjamini-Yekutieli charged, and what the dependence is worth")
        guard let tail = try? PermutationEffectiveCount.standard.estimate(for: matrix),
              let budget = try? MultiplicityBudget(count: tail) else { return }
        print("     Sidak over \(design.comparisonCount) comparisons          "
            + "\(exponent(budget.sidakThreshold))")
        print("     Sidak over \(widthDp(tail.value)) effective       "
            + "\(exponent(budget.effectiveThreshold))   (\(widthDp(budget.loosening))x looser)")
        print("     critical |z| a reading must clear  \(widthDp(budget.criticalValue))")
        print("     Benjamini-Yekutieli multiplier     \(widthDp(budget.yekutieliMultiplier))x")
        print("     this panel's measured multiplier   \(widthDp(budget.effectiveMultiplier))x")
        print("     BY prices the worst dependence a family of \(design.comparisonCount) could have.")
        print("     Scenario 52 was right to reach for it and had nothing to measure with.")
    }

    // MARK: - C: re-pricing the family scenario 52 published

    private static func comparisonPartC(
        _ measured: [PairwiseAssociation],
        judgeCount: Int,
        matrix: CorrelationMatrix
    ) async {
        print("  C. the same findings, corrected for the shape instead of the worst case")
        guard let family = familyOfPairs(measured, judgeCount: judgeCount) else {
            print("     no pair produced a usable coefficient, so there is nothing to re-price")
            return
        }
        let ledger = EffectiveComparisonLedger(
            matrix: matrix, source: .structural(judgeCount: judgeCount)
        )
        for finding in family.findings {
            await ledger.record(finding.key, probability: finding.pValue)
        }
        guard let verdict = try? await ledger.verdict(at: FamilyErrorKit.ConfidenceLevel.ninetyFive.alpha)
        else {
            print("     the ledger declined to spend this denominator")
            return
        }
        let yekutieli = BenjaminiYekutieli().adjust(family)
        for adjusted in yekutieli {
            let mine = verdict.budget.adjusted(adjusted.rawPValue)
            print("     \(wide(adjusted.key))raw \(exponent(adjusted.rawPValue))"
                + "   BY \(widthDp(adjusted.adjustedPValue))   m_eff \(widthDp(mine))")
        }
        let byCount = yekutieli.filter { $0.survives(at: .ninetyFive) }.count
        print("     published under BY                 \(byCount) of \(family.size)")
        print("     published under m_eff \(widthDp(verdict.count.published))         "
            + "\(verdict.survivors.count) of \(family.size)")
        print("     bought by measuring the shape      \(verdict.bought.count)"
            + "  (over Sidak on the whole family)")
        print("     unreported comparisons entering at p = 1: \(family.unreportedCount)")
    }

    /// The shared `pad` is exactly 28 wide and `answerability x independence` is exactly 28
    /// characters, which closed the gap between the key and its number. Widened here rather
    /// than changing a helper eleven other scenarios have already laid their columns against.
    private static func wide(_ text: String) -> String {
        text.padding(toLength: 30, withPad: " ", startingAt: 0)
    }

    // MARK: - D: the refusals, which are the point

    private static func comparisonPartD(_ matrix: CorrelationMatrix) async {
        print("  D. two denominators this package will not divide by")
        let rankLedger = EffectiveComparisonLedger(
            matrix: matrix, source: .structural(judgeCount: 4), estimator: LiJi()
        )
        if let measuredRank = try? await rankLedger.estimate() {
            print("     Li-Ji measures \(widthDp(measuredRank.value)) and the ledger will report it,")
        }
        do {
            _ = try await rankLedger.verdict()
            print("     REFUSAL MISSING: a rank was spent as a threshold")
        } catch {
            print("     but refuses to spend it: \(error)")
            print("       headline    a rank is not a multiplicity denominator")
            print("       because     it counts the quantities behind the family, not its maximum")
            print("       do instead  estimate the tail by simulation, or correct over all of m")
        }
        let assumed = EffectiveComparisonLedger(matrix: matrix, source: .assumed)
        do {
            _ = try await assumed.credited()
            print("     REFUSAL MISSING: an assumed matrix bought credit")
        } catch {
            print("     and refuses an undeclared matrix: \(error)")
            print("       headline    this denominator has no provenance")
            print("       because     an assumed correlation buys independence nobody measured")
            print("       do instead  declare the panel shape, or accept m and publish less")
        }
        print("     Measuring is free in both cases. Spending is what is gated.")
    }
}
