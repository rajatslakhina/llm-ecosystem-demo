import EffectiveVoteKit
import FamilyErrorKit
import Foundation
import ProviderGatewayKit
import SampleWidthKit
import TokenMeterKit

/// The identifier the fifty-second scenario bills its correction against.
extension ProviderIdentifier {
    static let familyErrorHost = ProviderIdentifier("family-error-host")
}

extension EcosystemDemo {
    /// The fifty-second scenario: **every reading on this panel is quoted at 95%, and there
    /// are six of them.**
    ///
    /// Scenario 50 published six pairwise readings off the proxy-labelled panel. Scenario 51
    /// asked what ninety-six items support and widened each of them by its own sampling error.
    /// Both worked one pair at a time, which is correct for one pair and wrong for a page of
    /// six: the chance that all six intervals cover is not 95%, and the largest of the six was
    /// selected out of six candidates by the quantity being quoted.
    ///
    /// `FamilyErrorKit` corrects for the six. Nothing here re-measures anything — the
    /// coefficients, tables and intervals are the ones `EffectiveVoteKit` already produced.
    static func runFamilyErrorScenario(meter: TokenMeter) async {
        print("[family error scenario] six pairs, six intervals, and the level none of them held")

        let constructed = panelHistory()
        let proxied = proxyLabelledHistory(from: constructed, flipRate: 0.12)
        let estimator = EffectiveVoteEstimator(basis: .errorAgreement)
        let estimate = estimator.estimate(proxied.history, stratum: .all)
        let measured = estimate.measuredAssociations

        await familyPartA(measured, judgeCount: estimate.nominalJudges)
        familyPartB(judgeCount: estimate.nominalJudges)
        familyPartC(measured)
        familyPartD(measured, familySize: measured.count)

        await meter.record(
            TokenUsage(promptTokens: 610, completionTokens: 180),
            for: ProviderIdentifier.familyErrorHost.rawValue
        )
    }

    // MARK: - A: what survives once the page is counted

    private static func familyPartA(_ measured: [PairwiseAssociation], judgeCount: Int) async {
        print("  A. the readings scenario 50 published, corrected for being a page of them")
        guard let family = familyOfPairs(measured, judgeCount: judgeCount) else {
            print("     no pair produced a usable coefficient, so there is no family to correct")
            return
        }
        for finding in family.findings {
            print("     \(pad(finding.key))phi \(widthDp(finding.estimate))"
                + "   p \(exponent(finding.pValue))")
        }
        let level = FamilyErrorKit.ConfidenceLevel.ninetyFive
        let raw = family.findings.filter { $0.pValue <= level.alpha }.count
        print("     uncorrected at 0.05: \(raw) of \(family.size)")
        for correction in [Holm(), BenjaminiYekutieli()] as [any MultiplicityCorrection] {
            let survivors = correction.survivors(of: family, at: level)
            print("     \(pad(correction.name))\(survivors.count) of \(family.size)"
                + "   (\(correction.controls.rawValue), \(correction.dependenceAssumption.rawValue))")
        }
    }

    // MARK: - B: whether independence was ever on the table

    private static func familyPartB(judgeCount: Int) {
        guard let graph = try? PairOverlapGraph(judgeCount: judgeCount) else { return }
        print("  B. how much of this family is dependent by construction")
        print("     \(graph.judgeCount) judges -> \(graph.pairCount) pairs "
            + "-> \(graph.totalPairings) pairings of pairs")
        print("     \(graph.overlappingPairings) of those share a judge: "
            + "\(String(format: "%.2f", graph.overlapDensity * 100))% overlap "
            + "-> \(graph.recommendedAssumption.rawValue)")
        let price = BenjaminiYekutieli.dependencePrice(forSize: graph.pairCount)
        print("     Benjamini-Yekutieli pays H(\(graph.pairCount)) = \(widthDp(price)) for that.")
        print("     Scenario 49 already proved the overlap is not theoretical: two of the four")
        print("     judges were measured to be the same judge on this corpus.")
    }

    // MARK: - C: what six noise readings would have produced

    private static func familyPartC(_ measured: [PairwiseAssociation]) {
        print("  C. what the top of this page would look like if nothing on it were real")
        let magnitudes = measured.compactMap(\.coefficient).map(abs).sorted(by: >)
        guard let largest = magnitudes.first,
              let items = measured.first?.sampleSize,
              let ceiling = try? NullMaximum.threshold(familySize: measured.count, observationCount: items),
              let single = try? NullMaximum.threshold(familySize: 1, observationCount: items),
              let median = try? NullMaximum.medianLargest(familySize: measured.count, observationCount: items),
              let exceedance = try? NullMaximum.exceedanceProbability(
                ofPhi: largest, familySize: measured.count, observationCount: items) else { return }
        print("     largest |phi| observed        \(widthDp(largest))")
        print("     median largest under the null \(widthDp(median))")
        print("     95% ceiling for the largest   \(widthDp(ceiling)) (a single reading: \(widthDp(single)))")
        print("     P(noise makes one this big)   \(exponent(exceedance))")
        if magnitudes.count > 1 {
            let runnerUp = magnitudes[1]
            let odds = (try? NullMaximum.exceedanceProbability(
                ofPhi: runnerUp, familySize: measured.count, observationCount: items)) ?? 1
            let verdict = runnerUp > single ? "clears the single-reading bar" : "clears nothing"
            print("     runner-up \(widthDp(runnerUp)) \(verdict), and noise matches it \(widthDp(odds)) of the time")
        }
    }

    // MARK: - D: the interval scenario 51 widened, widened again for the page

    private static func familyPartD(_ measured: [PairwiseAssociation], familySize: Int) {
        print("  D. re-quoting an interval so all \(familySize) hold at once")
        let ranked = measured.sorted { abs($0.coefficient ?? 0) > abs($1.coefficient ?? 0) }
        if let perfect = ranked.first, abs(perfect.coefficient ?? 0) >= 1 {
            print("     the largest reading on the page is the one that cannot be re-quoted:")
            print("     \(perfect.pair.summaryKey) sits at phi \(widthDp(perfect.coefficient)), "
                + "where atanh is unbounded.")
            print("     Refused rather than clamped -- the same refusal scenario 51 hit on this pair.")
        }
        guard let strongest = ranked.first(where: { abs($0.coefficient ?? 1) < 1 }),
              let interval = strongest.interval,
              let widened = try? SimultaneousInterval.widenedFisher(interval, familySize: familySize)
        else {
            print("     no remaining pair carries a widenable interval")
            return
        }
        print("     pair \(strongest.pair.summaryKey), phi \(widthDp(strongest.coefficient))")
        print("     per-comparison 95% (EffectiveVoteKit, Fisher)  \(show(interval))")
        print("     simultaneous 95% across \(familySize)                   \(show(widened.simultaneous))")
        print("     member level each one needs                   "
            + "\(String(format: "%.6f", widened.memberLevel.coverage)) "
            + "-> \(widthDp(widened.scaleFactor))x half-width")
        print("     added width \(widthDp(widened.addedWidth)). Scenario 51 widened these for the")
        print("     corpus. Nothing until now widened them for each other.")
        if let naive = try? SimultaneousInterval.scaledLinearly(interval, familySize: familySize) {
            print("     scaling the printed half-width instead   \(show(naive.simultaneous))"
                + "  exact: \(naive.exact)")
        }
    }

    // MARK: - support

    /// Turns measured associations into a family, with the size the panel's shape implies.
    static func familyOfPairs(_ measured: [PairwiseAssociation], judgeCount: Int) -> Family? {
        let findings = measured.compactMap { association -> Finding? in
            guard let coefficient = association.coefficient else { return nil }
            let statistic = coefficient * Double(association.sampleSize).squareRoot()
            return try? Finding(
                key: association.pair.summaryKey,
                pValue: NormalTail.twoSidedPValue(forZ: statistic),
                estimate: coefficient,
                standardError: 1 / Double(max(association.sampleSize - 3, 1)).squareRoot()
            )
        }
        return try? Family(findings: findings, origin: .panelPairs(judgeCount: judgeCount))
    }

    static func exponent(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.3e", value)
    }
}

extension JudgePair {
    /// The key this pair is published under across the family scenarios.
    var summaryKey: String { PanelPair(first.rawValue, second.rawValue).key }
}
