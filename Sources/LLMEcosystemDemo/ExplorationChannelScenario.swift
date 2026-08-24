import CensoredFeedbackKit
import ConformalGateKit
import ExplorationChannelCensored
import ExplorationChannelKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let explorationHost = ProviderIdentifier("exploration-host")
}

extension EcosystemDemo {
    /// The fortieth scenario: **scenario 39 priced the fix. Can this stack afford it?**
    ///
    /// Scenario 39 ended by saying this demo cannot manufacture censoring and the app can. It also
    /// left a quote sitting there — nineteen labelled refusals to certify `alpha = 0.05` — with
    /// nothing in the ecosystem able to produce one. Producing them is not a question about
    /// censoring. It is a question about which refusals you can afford to admit, and this scenario
    /// asks it against the conformal gate's own calibration set.
    ///
    /// The first thing it finds is not about exploration at all. **Eighteen of the thirty turns the
    /// gate is calibrated on score above its own threshold**, so the gate would refuse the majority
    /// of the set that certifies it. That is the same shape as scenario 39's finding read from the
    /// other end.
    static func runExplorationChannelScenario(meter: TokenMeter) async {
        print("[exploration channel scenario] what would it cost to learn what the gate refuses?")
        let gate = ConformalGate(budget: .oneInTwenty)
        let outcome = gate.certify(Self.conformalCalibration())
        guard let certificate = outcome.certificate else {
            print("  no certificate — nothing to explore against")
            return
        }
        let threshold = certificate.threshold
        print("  certificate     \(outcome.summary)")

        let candidates = Self.explorationCandidates(threshold: threshold)
        print("  A. the refusals, as depths below the cut")
        print("     \(candidates.count) of \(Self.conformalCalibration().count) calibration turns score above the")
        print("     threshold \(Self.fmt(threshold, 4)) and would be refused.")
        guard !candidates.isEmpty else {
            print("     Nothing is refused, so there is nothing to explore.")
            return
        }
        let depths = candidates.map(\.depth)
        let deepest = depths.reduce(0) { Swift.max($0, $1) }
        print("     depths run from \(Self.fmt(depths.reduce(1_000) { Swift.min($0, $1) }, 4)) "
            + "to \(Self.fmt(deepest, 4)).")
        print("     The gate would refuse most of the set that certifies it — scenario 39's finding")
        print("     read from the other end, and the reason there is anything here to explore.")

        await Self.explorationChannelRun(candidates: candidates, threshold: threshold, meter: meter)
        Self.explorationPlannerSweep(depths: depths)
    }

    // MARK: - orientation

    /// Conformal scores run the other way from this channel's.
    ///
    /// `ConformalGateKit` refuses a turn whose nonconformity is *above* the threshold; a channel
    /// refuses one whose score is *below* it. Negating both puts them in the same orientation and
    /// leaves the depth — the distance from the cut, which is all either side reasons about —
    /// unchanged. Worth stating rather than doing quietly: an orientation flip that goes unnoticed
    /// explores the confidently-correct end of the log and calls it the refused one.
    static func explorationCandidates(threshold: Double) -> [RefusalCandidate] {
        Self.conformalCalibration()
            .filter { $0.score > threshold }
            .map { point in
                RefusalCandidate(
                    id: point.id,
                    score: -point.score,
                    threshold: -threshold,
                    stratum: point.stratum.map { ExplorationChannelKit.Stratum($0.rawValue) }
                )
            }
    }

    // MARK: - B: a real run

    private static func explorationChannelRun(
        candidates: [RefusalCandidate],
        threshold: Double,
        meter: TokenMeter
    ) async {
        print("  B. a channel over those refusals")
        let deepest = candidates.map(\.depth).reduce(0) { Swift.max($0, $1) }
        guard let region = try? ExplorationRegion(
            lowerBound: -threshold - deepest / 2,
            threshold: -threshold,
            frequency: 0.5
        ) else {
            print("     region could not be formed")
            return
        }
        let costModel = LinearExplorationCost(unitCost: 0.02)
        guard let channel = try? ExplorationChannel(
            region: region,
            budget: 0.01,
            costModel: costModel
        ) else { return }

        let ledger = ExplorationLedger()
        for candidate in candidates {
            let ruling = await channel.consider(candidate)
            await ledger.record(candidate, ruling: ruling)
            if ruling.wasAdmitted {
                await ledger.label(candidate.id, loss: Self.explorationLoss(for: candidate.id))
            }
        }
        let yield = await ledger.yield(budget: 0.01)
        print("     region \(region.summary), budget $0.0100 against a $0.02-per-unit-depth price")
        print("     \(yield.summary)")

        let entries = await ledger.allEntries
        let bridge = ChannelFeedbackBridge(region: region)
        guard let auditor = try? CensoringAuditor(lossBound: 1, budget: 0.05) else { return }

        if let population = try? auditor.audit(bridge.records(refusals: candidates, entries: entries)) {
            print("     whole refused set  \(population.profile.diagnosis)")
        }
        if let band = try? auditor.audit(bridge.bandRecords(refusals: candidates, entries: entries)) {
            print("     band only          \(band.profile.diagnosis)")
            if let reweighted = band.profile.reweighted {
                print("     \(reweighted.summary)")
                print("     Those two estimates disagree because all three labels came back wrong.")
                print("     Self-normalised reports what was seen; Horvitz-Thompson divides that")
                print("     across the band it stands for. On three observations both are honest and")
                print("     neither is worth acting on — which is what an effective sample size of 3 is")
                print("     for saying.")
            }
        }
        await meter.record(
            TokenUsage(promptTokens: candidates.count * 12, completionTokens: candidates.count * 4),
            for: ProviderIdentifier.explorationHost.rawValue
        )
    }

    /// Whether a refused turn would in fact have been wrong.
    ///
    /// Taken from the calibration point's own recorded outcome, which is the one thing this demo
    /// has that a deployed gate does not — and precisely the thing exploration exists to buy.
    static func explorationLoss(for id: String) -> Double {
        let point = Self.conformalCalibration().first { $0.id == id }
        return (point?.wasWrong ?? false) ? 1 : 0
    }

    // MARK: - C: does exploring help at all

    private static func explorationPlannerSweep(depths: [Double]) {
        print("  C. the sweep — is any band worth buying?")
        let model = BoundModel(lossBound: 1, delta: 0.05, spliceCost: 0.01)
        for budget in [0.01, 0.20] {
            let planner = RegionPlanner(
                model: model,
                frequency: 1,
                budget: budget,
                costModel: LinearExplorationCost(unitCost: 0.02)
            )
            let sweep = planner.sweep(censoredDepths: depths)
            print("     budget \(Self.fmt(budget, 4)) — \(sweep.count) candidate bands")
            for step in sweep {
                print("       \(step.summary)")
            }
            if let best = planner.bestRegion(censoredDepths: depths) {
                print("       best: depth \(Self.fmt(best.maximumDepth, 4)), bound "
                    + "\(Self.fmt(best.total, 4)) vs baseline \(Self.fmt(model.baseline, 4))")
            } else {
                print("       no band beats not exploring at this budget")
            }
        }
        print("     At $0.0100 the optimum is interior: the band reaching 0.1667 bounds at 0.8421,")
        print("     while the band covering every refusal bounds at 0.9703 — worse, on two labels")
        print("     rather than three, for less money. At $0.2000 the budget stops binding and the")
        print("     widest band wins outright at 0.3301. Same regime switch the package's own demo")
        print("     shows on synthetic depths, here on the gate's real calibration scores.")
        print("     Neither band gets near the nineteen labels scenario 39 quoted. The cheap answer")
        print("     is a band worth buying; the certificate is still out of reach.")
    }

    static func fmt(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }
}
