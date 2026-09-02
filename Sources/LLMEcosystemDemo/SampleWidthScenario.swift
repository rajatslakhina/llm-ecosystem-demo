import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import ProxyLabelKit
import SampleWidthKit
import TokenMeterKit

/// The identifier the fifty-first scenario bills its width calculation against.
extension ProviderIdentifier {
    static let sampleWidthHost = ProviderIdentifier("sample-width-host")
}

/// One pair's audit, kept whole so the width work and the de-noising see the same table.
struct AuditedPair {
    let pair: JudgePair
    let table: ErrorAgreementTable
    let association: FeasibleAssociation
    let flipRate: ProportionInterval
    let regime: NoiseRegime
}

extension EcosystemDemo {
    /// The fifty-first scenario: **scenario 50 reported movements it could not have measured.**
    ///
    /// Scenario 50 found four pairs whose true association is exactly zero sitting off zero once a
    /// proxy label was used, and one bound that excluded the truth outright. It named the reason in
    /// its own output — the bound carries the flip rate's uncertainty and not the table's.
    ///
    /// This scenario supplies the missing half. Every one of those readings comes from ninety-six
    /// items, `SampleWidthKit` says what ninety-six items pin down, and the same de-noising, handed
    /// an interval instead of a point, produces a bound that contains the truth.
    static func runSampleWidthScenario(meter: TokenMeter) async {
        print("[sample width scenario] the movements scenario 50 reported, and whether 96 items can tell")

        let constructed = panelHistory()
        let proxied = proxyLabelledHistory(from: constructed, flipRate: 0.12)
        let estimator = EffectiveVoteEstimator(basis: .errorAgreement)
        let honest = estimator.estimate(constructed, stratum: .all)
        let derived = estimator.estimate(proxied.history, stratum: .all)
        let audits = auditedPairs(from: proxied, pairs: honest.associations.map(\.pair))

        await widthPartA(audits)
        widthPartB(honest: honest, derived: derived, audits: audits)
        widthPartC(audits)

        await meter.record(
            TokenUsage(promptTokens: 610, completionTokens: 180),
            for: ProviderIdentifier.sampleWidthHost.rawValue
        )
    }

    // MARK: - A: what the corpus pins down

    private static func widthPartA(_ audits: [AuditedPair]) async {
        print("  A. what 96 items pin down about each pair, at 95%")
        let ledger = WidthLedger()
        for audit in audits {
            guard let table = contingency(from: audit.table) else {
                print("     \(pad(audit.pair.description))  no table: a margin collapsed, phi is undefined")
                continue
            }
            await ledger.record(table, for: audit.pair.description)
        }
        for key in await ledger.keys() {
            await widthReport(key, from: ledger)
        }
    }

    /// One pair's line, with a refusal printed rather than skipped.
    ///
    /// The first draft of this used `try?` and a `continue`, and quietly dropped the one pair whose
    /// table cannot carry an interval — leaving five confident readings and no sign that a sixth
    /// existed. A gap that looks like an absence is worse than a refusal that looks like a problem.
    private static func widthReport(_ key: String, from ledger: WidthLedger) async {
        do {
            let interval = try await ledger.interval(for: key)
            let clamp = interval.marginClamp == .within ? "" : " · trimmed to the feasible range"
            print("     \(pad(key))  phi \(widthDp(interval.pointEstimate)) "
                + "· \(show(interval.range)) · width \(widthDp(interval.width))\(clamp)")
        } catch {
            print("     \(pad(key))  refused: \(error)")
        }
    }

    // MARK: - B: were the movements measurable

    private static func widthPartB(
        honest: EffectiveVoteEstimate,
        derived: EffectiveVoteEstimate,
        audits: [AuditedPair]
    ) {
        print("  B. scenario 50's movements, against what the sample supports")
        let truthByPair = measuredByPair(honest)
        let afterByPair = measuredByPair(derived)
        var unmeasurable = 0

        for audit in audits.sorted(by: { $0.pair < $1.pair }) {
            let before = truthByPair[audit.pair]
            let after = afterByPair[audit.pair]
            let reading = movementReading(audit, before: before)
            if reading.isUnresolved { unmeasurable += 1 }
            print("     \(pad(audit.pair.description))  \(widthDp(before)) -> \(widthDp(after))  \(reading.text)")
        }
        print("     \(unmeasurable) of \(audits.count) movements are indistinguishable from where they started")
    }

    /// Each pair that produced a coefficient, dropping the ones that did not.
    private static func measuredByPair(_ estimate: EffectiveVoteEstimate) -> [JudgePair: Double] {
        Dictionary(uniqueKeysWithValues: estimate.associations.compactMap { association in
            association.coefficient.map { (association.pair, $0) }
        })
    }

    /// Whether one pair's movement clears the association the corpus was built with.
    private static func movementReading(
        _ audit: AuditedPair,
        before: Double?
    ) -> (text: String, isUnresolved: Bool) {
        guard let table = contingency(from: audit.table), let before else {
            return ("no verdict: the table cannot carry an interval", false)
        }
        do {
            switch try SampleSufficiency().verdict(for: table, against: before) {
            case .separated(let side):
                return ("separated \(side.rawValue) — the movement is real", false)
            case .unresolved(let required):
                let text = required.map { "unresolved — \($0) items would settle it" }
                    ?? "unresolved — no count settles it"
                return (text, true)
            }
        } catch {
            return ("refused: \(error)", false)
        }
    }

    // MARK: - C: the bound that missed, widened by the table

    private static func widthPartC(_ audits: [AuditedPair]) {
        print("  C. the bound that missed, with the sampling width carried through")
        for audit in audits where audit.pair == JudgePair("independence", "temporal") {
            guard let table = contingency(from: audit.table),
                  let sampling = try? FisherZEstimator().interval(for: table, at: .ninetyFive) else {
                print("     \(audit.pair)  no interval: the table cannot carry one")
                continue
            }
            let point = audit.association.lowest...audit.association.highest
            let widened = (try? IntervalPropagation.propagate(sampling.range) { candidate in
                try licensedTruth(candidate, audit: audit)
            }) ?? point

            print("     \(audit.pair)  measured \(widthDp(table.phi)) · true 0.0000")
            print("       point bound   \(show(point)) · contains the truth: \(point.contains(0))")
            print("       sampling      \(show(sampling.range)) · width \(widthDp(sampling.width))")
            print("       propagated    \(show(widened)) · contains the truth: \(widened.contains(0))")
            print("       width gained  \(widthDp(IntervalPropagation.widthGained(from: point, to: widened)))")
        }
    }

    /// What the de-noising licenses for one candidate measurement.
    ///
    /// Phi is linear in the top-left cell once the margins are fixed, so a candidate phi inverts
    /// to a real integer table — one this sample could genuinely have produced — rather than to a
    /// synthetic proportion the deconvolver has no way to check.
    private static func licensedTruth(_ candidate: Double, audit: AuditedPair) throws -> ClosedRange<Double> {
        guard let table = agreementTable(atPhi: candidate, like: audit.table) else {
            return audit.association.lowest...audit.association.highest
        }
        switch AssociationDeconvolver().bound(measured: table, flipRate: audit.flipRate, regime: audit.regime) {
        case .success(let feasible):
            return feasible.lowest...feasible.highest
        case .failure:
            return audit.association.lowest...audit.association.highest
        }
    }
}
