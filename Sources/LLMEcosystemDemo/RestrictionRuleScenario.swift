import Foundation
import ProviderGatewayKit
import RestrictionRuleKit
import TokenMeterKit
import UnconditionalExactKit

/// The identifier the sixty-fourth scenario bills its measurement against.
extension ProviderIdentifier {
    static let restrictionRuleHost = ProviderIdentifier("restriction-rule-host")
}

extension EcosystemDemo {
    /// The sixty-fourth scenario: **every exact test up to this point offered a Berger–Boos
    /// restriction at a fixed conventional `gamma = 0.001`. Nothing ever selected it.**
    ///
    /// This scenario measures that convention against the two things that matter — whether it
    /// beats not restricting at all, and whether a design-fixed recommendation still holds its
    /// level — rather than assuming the convention is fine because it usually runs without error.
    static func runRestrictionRuleScenario(meter: TokenMeter) async {
        print("[restriction rule scenario] the gamma nothing has ever selected")

        restrictionRulePartA()
        await restrictionRulePartB()

        await meter.record(
            TokenUsage(promptTokens: 410, completionTokens: 150),
            for: ProviderIdentifier.restrictionRuleHost.rawValue
        )
    }

    /// The same twelve-item reference table this series keeps reporting on, read row-fixed.
    private static var restrictionRuleReference: ArmCounts? {
        try? ArmCounts(successes: 6, trials: 6, otherSuccesses: 3, otherTrials: 6)
    }

    // MARK: - A: the convention against a search

    private static func restrictionRulePartA() {
        print("  A. the conventional gamma=0.001, measured rather than assumed to be fine")
        guard let arms = restrictionRuleReference,
              let test = try? UnconditionalExact(resolution: 1024) else {
            print("     the reference table could not be read")
            return
        }
        let measure = PooledScore()
        let cost = ClosureGammaCostFunction { gamma in
            try test.pValue(
                for: arms, alternative: .twoSided, using: measure,
                restriction: .bergerBoos(gamma: gamma)
            ).value
        }
        guard let conventional = try? cost.value(atGamma: 0.001),
              let recommendation = try? GammaSearch.recommend(
                  costFunction: cost, gammaFloor: 1e-6, gammaCeiling: 0.2
              ) else {
            print("     the search failed")
            return
        }
        let floor = RestrictionRuleFormatting.decimal(recommendation.floorValue, places: 6)
        let conv = RestrictionRuleFormatting.decimal(conventional, places: 6)
        let recGamma = RestrictionRuleFormatting.decimal(recommendation.recommendedGamma, places: 6)
        let recValue = RestrictionRuleFormatting.decimal(recommendation.recommendedValue, places: 6)
        print("     unrestricted (floor)   value = \(floor)")
        print("     conventional gamma=0.001 value = \(conv)")
        print("     recommended gamma = \(recGamma), value = \(recValue)")
        let convBeatsFloor = conventional <= recommendation.floorValue
        print("     the convention " + (convBeatsFloor ? "beats" : "costs more than")
            + " not restricting at all on this table.")
    }

    // MARK: - B: the safe way to use a recommendation

    private static func restrictionRulePartB() async {
        print("  B. a design-fixed recommendation still holds its level")
        guard let arms = restrictionRuleReference else { return }
        let trials = 6
        let otherTrials = 6
        let alpha = 0.1
        let resolution = 1024
        guard let test = try? UnconditionalExact(resolution: resolution) else { return }
        let measure = PooledScore()
        let cost = ClosureGammaCostFunction { gamma in
            try test.pValue(
                for: arms, alternative: .twoSided, using: measure,
                restriction: .bergerBoos(gamma: gamma)
            ).value
        }
        guard let recommendation = try? GammaSearch.recommend(
            costFunction: cost, gammaFloor: 1e-6, gammaCeiling: 0.2
        ) else { return }

        guard let conventionalCertificate = try? SizeCertificate.of(
            procedure: .unconditional(.bergerBoos(gamma: 0.001)),
            trials: trials, otherTrials: otherTrials, alpha: alpha, resolution: resolution
        ), let recommendedCertificate = try? SizeCertificate.of(
            procedure: .unconditional(.bergerBoos(gamma: recommendation.recommendedGamma)),
            trials: trials, otherTrials: otherTrials, alpha: alpha, resolution: resolution
        ) else {
            print("     the level audit could not be run")
            return
        }
        print("     conventional gamma=0.001   holds its level: \(conventionalCertificate.holdsItsLevel)")
        print("     design-fixed recommendation holds its level: \(recommendedCertificate.holdsItsLevel)")
        print("     Both are fixed before any table is looked at, which is what the guarantee needs.")
        print("     What re-minimising per observed table would change is measured in")
        print("     restriction-rule-kit's own repository, by full enumeration — not assumed here.")
    }
}
