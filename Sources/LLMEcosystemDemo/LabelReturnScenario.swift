import ConformalGateKit
import ExplorationChannelKit
import Foundation
import LabelReturnExploration
import LabelReturnKit
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let labelReturnHost = ProviderIdentifier("label-return-host")
}

extension EcosystemDemo {
    /// The forty-first scenario: **scenario 40 read three labels. When did they arrive?**
    ///
    /// Scenario 40 admitted three refusals, took their outcomes, and reported an estimate. It could
    /// only do that because this demo holds every turn's ground truth in memory — it labels an
    /// admission in the same statement that admits it. No deployed system has that. Outcomes arrive
    /// later, incompletely, and the ones that arrive first are not a random half.
    ///
    /// This scenario puts a clock on the same population and asks what the gate's own numbers look
    /// like before the slow labels land.
    static func runLabelReturnScenario(meter: TokenMeter) async {
        print("[label return scenario] the same turns, with a clock on the verification")
        let gate = ConformalGate(budget: .oneInTwenty)
        let outcome = gate.certify(Self.conformalCalibration())
        guard let certificate = outcome.certificate else {
            print("  no certificate — nothing to audit")
            return
        }
        let threshold = certificate.threshold
        let fingerprint = GateFingerprint(identifier: "conformal-gate", threshold: threshold)

        guard let built = await Self.labelReturnLedger(threshold: threshold, gate: fingerprint) else {
            print("  the ledger could not be built")
            return
        }
        Self.labelReturnPartA(built)
        await Self.labelReturnPartB(ledger: built.ledger, alpha: 0.05)
        await Self.labelReturnPartC(built: built, alpha: 0.05)
        await Self.labelReturnPartD(built: built, gate: fingerprint)

        await meter.record(
            TokenUsage(promptTokens: built.admissions.count * 14, completionTokens: built.admissions.count * 5),
            for: ProviderIdentifier.labelReturnHost.rawValue
        )
    }

    // MARK: - fixture

    struct LabelReturnRun {
        let admissions: [PendingAdmission]
        let ledger: ReturnLedger
        let answered: Int
        let explored: Int
        let entries: [ExplorationEntry]
    }

    /// How long a turn takes to verify.
    ///
    /// Both terms are the demo's own data rather than a shape chosen to make a point. A turn the
    /// gate scored as more nonconforming is one it found harder, and harder turns take longer to
    /// settle. A turn that was in fact wrong surfaces through a complaint or a correction rather
    /// than through somebody confirming it worked, and that is slower again.
    static func labelReturnDelay(score: Double, wasWrong: Bool) -> Int {
        2 + Int((score * 8).rounded(.down)) + (wasWrong ? 6 : 0)
    }

    /// Everything this stack actually answered, in the two regions it answered them from.
    ///
    /// Turns the gate refused *and* the channel did not admit are absent on purpose: nothing was
    /// answered, so there is no outcome to wait for. Their absence is scenario 39's censoring, not
    /// this scenario's incompleteness, and mixing the two would make both invisible.
    static func labelReturnLedger(
        threshold: Double,
        gate: GateFingerprint
    ) async -> LabelReturnRun? {
        let points = Self.conformalCalibration()
        let candidates = Self.explorationCandidates(threshold: threshold)
        let entries = await Self.labelReturnExplorationEntries(candidates: candidates, threshold: threshold)
        let exploredIDs = Set(entries.map(\.id))

        var admissions: [PendingAdmission] = []
        var labels: [ReturnedLabel] = []
        var answered = 0
        for point in points {
            let isExplored = exploredIDs.contains(point.id)
            let isAnswered = point.score <= threshold
            guard isAnswered || isExplored else { continue }
            if isAnswered { answered += 1 }
            let probability = isExplored ? 0.5 : 1.0
            admissions.append(
                PendingAdmission(
                    id: point.id,
                    region: isExplored ? "explored" : "answered",
                    admissionProbability: probability,
                    admittedAt: LogicalTime(0),
                    gate: gate
                )
            )
            labels.append(
                ReturnedLabel(
                    id: point.id,
                    outcome: point.wasWrong ? .loss : .noLoss,
                    returnedAt: LogicalTime(Self.labelReturnDelay(score: point.score, wasWrong: point.wasWrong)),
                    gate: gate
                )
            )
        }
        guard let ledger = try? ReturnLedger(admissions: admissions) else { return nil }
        await ledger.record(contentsOf: labels)
        return LabelReturnRun(
            admissions: admissions,
            ledger: ledger,
            answered: answered,
            explored: admissions.count - answered,
            entries: entries
        )
    }

    /// Scenario 40's channel run, replayed so this scenario audits the same admissions.
    static func labelReturnExplorationEntries(
        candidates: [RefusalCandidate],
        threshold: Double
    ) async -> [ExplorationEntry] {
        let deepest = candidates.map(\.depth).reduce(0) { Swift.max($0, $1) }
        guard let region = try? ExplorationRegion(
            lowerBound: -threshold - deepest / 2,
            threshold: -threshold,
            frequency: 0.5
        ), let channel = try? ExplorationChannel(
            region: region,
            budget: 0.01,
            costModel: LinearExplorationCost(unitCost: 0.02)
        ) else { return [] }
        let ledger = ExplorationLedger()
        for candidate in candidates {
            let ruling = await channel.consider(candidate)
            await ledger.record(candidate, ruling: ruling)
            if ruling.wasAdmitted {
                await ledger.label(candidate.id, loss: Self.explorationLoss(for: candidate.id))
            }
        }
        return await ledger.allEntries
    }

    // MARK: - A

    static func labelReturnPartA(_ run: LabelReturnRun) {
        print("  A. what this stack actually answered")
        print("     \(run.answered) turns the gate admitted at p = 1.00, plus \(run.explored) "
            + "refusals the channel bought at p = 0.50.")
        print("     The remaining refusals are not here: nothing was answered, so there is no")
        print("     outcome to wait for. That absence is scenario 39's censoring, not this one's.")
    }

    // MARK: - B

    static func labelReturnPartB(ledger: ReturnLedger, alpha: Double) async {
        print("  B. the same population, read at eight cutoffs")
        let cutoffs = [1, 2, 3, 4, 6, 8, 10, 14].map(LogicalTime.init)
        let rows = await WaitCurve.build(
            ledger: ledger,
            cutoffs: cutoffs,
            alpha: alpha,
            selectivityTolerance: 0.15
        )
        print("     cutoff  back  out   floor   ceiling  point     diagnosis    verdict")
        for row in rows {
            print("     " + Self.labelReturnRow(row))
        }
        let settled = WaitCurve.firstSettled(in: rows)
        print("     first settled: "
            + (settled.map { "t\($0.cutoff.tick)" } ?? "never")
            + ", narrows monotonically: \(WaitCurve.narrowsMonotonically(rows))")
        print("     The floor reads 0.0000 for nine ticks and the promise looks kept the whole time.")
        print("     Every loss in this population lands at t10 together, because the delay carries a")
        print("     six-tick penalty for being wrong — and then the certificate is withdrawn against")
        print("     a budget of 0.0500 by a measured 0.3333. Nothing changed at t10 except that the")
        print("     evidence arrived.")
    }

    static func labelReturnRow(_ row: WaitCurve.Row) -> String {
        let risk = row.risk
        return Self.labelReturnPad("t\(row.cutoff.tick)", 8)
            + Self.labelReturnPad("\(row.returned)", 6)
            + Self.labelReturnPad("\(row.pending)", 6)
            + Self.labelReturnPad(risk.map { Self.fmt($0.lower, 4) } ?? "—", 8)
            + Self.labelReturnPad(risk.map { Self.fmt($0.upper, 4) } ?? "—", 9)
            + Self.labelReturnPad(risk?.pointEstimate.map { Self.fmt($0, 4) } ?? "withheld", 10)
            + Self.labelReturnPad(Self.labelReturnDiagnosis(risk), 13)
            + Self.labelReturnVerdict(row.verdict)
    }

    static func labelReturnDiagnosis(_ risk: CorrectedRisk?) -> String {
        guard let risk else { return "—" }
        switch risk.diagnosis {
        case .noAdmissions: return "none"
        case .complete: return "complete"
        case .selectiveByRegion: return "selective"
        case .incomplete: return "incomplete"
        }
    }

    static func labelReturnVerdict(_ verdict: ReauditVerdict?) -> String {
        guard let verdict else { return "—" }
        switch verdict {
        case .holds: return "holds"
        case .withdrawn: return "withdrawn"
        case .undetermined: return "undetermined"
        }
    }

    static func labelReturnPad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    // MARK: - C

    /// Split the same reading by region, because the two are not the same promise.
    static func labelReturnPartC(built: LabelReturnRun, alpha: Double) async {
        print("  C. whose losses are they?")
        let whole = await built.ledger.snapshot(asOf: LogicalTime(99))
        for region in whole.regions {
            let only = LedgerSnapshot(
                asOf: whole.asOf,
                returned: whole.returned.filter { $0.admission.region == region },
                pending: whole.pending.filter { $0.region == region }
            )
            guard let risk = CorrectedRisk.estimate(from: only, selectivityTolerance: 0.15) else { continue }
            print("     \(Self.labelReturnPad(region.name, 12))\(risk.summary)")
            print("     \(Self.labelReturnPad("", 12))\(ReauditVerdict.reaudit(risk, alpha: alpha))")
        }
        print("     **The pooled figure withdraws a certificate the gate never broke.** Of the twelve")
        print("     turns it chose to answer, not one was wrong. All three losses are refusals the")
        print("     channel bought — and it bought them precisely because the gate was unsure, so")
        print("     they are enriched for exactly the outcome being counted.")
        print("     Comparing that pooled rate to alpha compares a promise about answered traffic")
        print("     against a population deliberately stocked with the refused kind. Exploration")
        print("     does not just cost money; it makes the naive risk figure worse by construction,")
        print("     and an audit that cannot say which region a loss came from will read that as a")
        print("     gate failing.")
    }

    // MARK: - D

    static func labelReturnPartD(built: LabelReturnRun, gate: GateFingerprint) async {
        print("  D. the channel's own admissions, banded by depth")
        guard !built.entries.isEmpty else {
            print("     the channel admitted nothing, so there is nothing to band")
            return
        }
        let depths = built.entries.map(\.depth).sorted()
        print("     depths: \(depths.map { Self.fmt($0, 4) }.joined(separator: ", "))")
        let plan = ExplorationAuditPlan(
            edges: [depths[depths.count / 2]],
            lossThreshold: 0.5,
            gate: gate
        )
        guard let built2 = try? await ExplorationReturnAudit.ledger(
            from: built.entries,
            plan: plan,
            admittedAt: { _ in LogicalTime(0) },
            returnedAt: { entry in
                LogicalTime(Self.labelReturnDelay(
                    score: Self.labelReturnScore(for: entry.id),
                    wasWrong: Self.explorationLoss(for: entry.id) > 0
                ))
            }
        ) else {
            print("     the banded ledger could not be built")
            return
        }
        let snapshot = await built2.ledger.snapshot(asOf: LogicalTime(99))
        for band in snapshot.regions {
            print("     \(band) -> \(Self.fmt((snapshot.returnRate(in: band) ?? 0) * 100, 2))% back")
        }
        guard let risk = CorrectedRisk.estimate(from: snapshot, selectivityTolerance: 0.15) else { return }
        print("     \(risk.diagnosis)")
        print("     \(risk.summary)")
        print("     All three admissions sit at the same depth, so a band cannot separate them and")
        print("     the selectivity check has nothing to compare. Reported rather than hidden: the")
        print("     check is only as good as the spread of what was bought, and a channel that drew")
        print("     three turns from one depth bought no ability to detect a depth-selective return.")
    }

    static func labelReturnScore(for id: String) -> Double {
        Self.conformalCalibration().first { $0.id == id }?.score ?? 0
    }
}
