import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import ProxyLabelKit
import TokenMeterKit

/// The identifier the fiftieth scenario bills its audit against.
extension ProviderIdentifier {
    static let proxyLabelHost = ProviderIdentifier("proxy-label-host")
}

extension EcosystemDemo {
    /// The fiftieth scenario: **scenario 49 was handed a label no deployment has.**
    ///
    /// Scenario 49 measures error agreement between four analysers, and it can only do that
    /// because `PanelSpec.isSafeToAnswer` is a fact about how each corpus was *built*. A running
    /// system has no such fact. It has a downstream outcome — a later check disagreed, a user
    /// pushed back — and a decision to treat that outcome as a correctness label.
    ///
    /// This runs scenario 49's own 96 corpora twice: once with the construction label, once with
    /// a proxy label derived from an item-scoped outcome that is wrong 12% of the time. The
    /// effective-vote count moves, and the direction it moves is not the one a reader would guess.
    static func runProxyLabelScenario(meter: TokenMeter) async {
        print("[proxy label scenario] the label scenario 49 got for free, priced")

        let constructed = panelHistory()
        let proxied = proxyLabelledHistory(from: constructed, flipRate: 0.12)
        let estimator = EffectiveVoteEstimator(basis: .errorAgreement)
        let honest = estimator.estimate(constructed, stratum: .all)
        let derived = estimator.estimate(proxied.history, stratum: .all)

        proxyPartA(honest: honest, derived: derived, flipped: proxied.flippedItems)
        proxyPartB(honest: honest, derived: derived)
        let cost = proxyPartC(proxied)
        proxyPartD(proxied, cost: cost, honest: honest)

        await meter.record(
            TokenUsage(promptTokens: 640, completionTokens: 195),
            for: ProviderIdentifier.proxyLabelHost.rawValue
        )
    }

    // MARK: - A: the same panel, two labels

    private static func proxyPartA(
        honest: EffectiveVoteEstimate,
        derived: EffectiveVoteEstimate,
        flipped: Int
    ) {
        print("  A. the same 96 corpora, labelled two ways")
        print("     construction label   effectiveVotes \(fourDp(honest.effectiveVotes)) "
            + "· mean r \(fourDp(honest.meanAssociation))")
        print("     proxy label          effectiveVotes \(fourDp(derived.effectiveVotes)) "
            + "· mean r \(fourDp(derived.meanAssociation))")
        print("     the proxy was wrong on \(flipped) of 96 items, and no judge changed its verdict")
    }

    // MARK: - B: which pairs moved

    private static func proxyPartB(honest: EffectiveVoteEstimate, derived: EffectiveVoteEstimate) {
        print("  B. per pair, construction label -> proxy label")
        let derivedByPair = Dictionary(
            uniqueKeysWithValues: derived.associations.map { ($0.pair, $0) }
        )
        for association in honest.associations.sorted(by: { ($0.coefficient ?? -2) > ($1.coefficient ?? -2) }) {
            let after = derivedByPair[association.pair]?.coefficient
            print("     \(association.pair)  \(fourDp(association.coefficient)) -> \(fourDp(after))")
        }
    }

    // MARK: - C: what the proxy costs

    private static func proxyPartC(_ proxied: ProxyLabelledPanel) -> FlipRateEstimate? {
        print("  C. pricing the proxy against 60 audited labels")
        switch FlipRateEstimator().estimate(from: proxied.auditSample(limit: 60)) {
        case .success(let cost):
            print("     false alarm \(cost.falseAlarm)")
            print("     miss        \(cost.miss)")
            print("     symmetric   \(cost.symmetric) — contains the real 0.12: "
                + "\(cost.symmetric.contains(0.12))")
            return cost
        case .failure(let refusal):
            print("     refused: \(refusal)")
            return nil
        }
    }

    // MARK: - D: bounding what the proxy could be hiding

    private static func proxyPartD(
        _ proxied: ProxyLabelledPanel,
        cost: FlipRateEstimate?,
        honest: EffectiveVoteEstimate
    ) {
        print("  D. bounding the true association for the two declared pairs")
        guard cost != nil else {
            print("     skipped: the proxy was never priced, so nothing can be bounded from it")
            return
        }
        let honestByPair = Dictionary(uniqueKeysWithValues: honest.associations.map { ($0.pair, $0) })
        for pair in [JudgePair("answerability", "morphology"), JudgePair("independence", "temporal")] {
            let audit = ProxyLabelAuditor().audit(
                proposals: proxied.proposals,
                left: JudgeID(pair.first.rawValue),
                right: JudgeID(pair.second.rawValue),
                against: proxied.auditSample(limit: 60)
            )
            switch audit.outcome {
            case .bounded(let association, _, _):
                let truth = honestByPair[pair]?.coefficient
                let inside = truth.map { $0 >= association.lowest && $0 <= association.highest }
                print("     \(pair)  measured \(fourDp(association.measured)) "
                    + "· true in [\(fourDp(association.lowest)), \(fourDp(association.highest))] "
                    + "· \(association.direction())")
                print("       construction label said \(fourDp(truth)) — inside the bound: "
                    + "\(inside.map(String.init) ?? "no label")")
                if inside == false {
                    print("       the bound missed. It carries the flip rate's uncertainty and not the")
                    print("       table's: 96 items put roughly 0.10 of sampling error on a phi near zero,")
                    print("       and nothing in the deconvolution is accounting for that.")
                }
            case .refused(let refusal):
                print("     \(pair)  refused: \(refusal)")
            }
        }
    }

    private static func fourDp(_ value: Double?) -> String {
        guard let value else { return "unmeasurable" }
        return String(format: "%.4f", value)
    }
}
