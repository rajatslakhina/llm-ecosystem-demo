import ConformalGateKit
import DelaySignalKit
import DelaySignalReturn
import Foundation
import LabelReturnKit
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let delaySignalHost = ProviderIdentifier("delay-signal-host")
}

extension EcosystemDemo {
    /// The forty-second scenario: **scenario 41 wrote the mechanism down and did not notice.**
    ///
    /// Its delay function is `2 + floor(score * 8) + (wasWrong ? 6 : 0)`. The middle term says hard
    /// turns settle slowly, which is a statement about difficulty. The last term says **wrong turns
    /// settle six ticks slower still**, which is a statement about the outcome — and it is exactly
    /// the dependence that makes every figure scenario 41 read before the horizon optimistic.
    ///
    /// Scenario 41 handles it by refusing to pick a point inside its bracket. This one asks whether
    /// the delays themselves can pick one, and the first honest answer is about how much traffic
    /// that takes.
    static func runDelaySignalScenario(meter: TokenMeter) async {
        print("[delay signal scenario] the +6 in scenario 41's delay function")
        let gate = ConformalGate(budget: .oneInTwenty)
        guard let certificate = gate.certify(Self.conformalCalibration()).certificate else {
            print("  no certificate — nothing to audit")
            return
        }
        let fingerprint = GateFingerprint(identifier: "conformal-gate", threshold: certificate.threshold)
        guard
            let built = await Self.labelReturnLedger(threshold: certificate.threshold, gate: fingerprint)
        else {
            print("  the ledger could not be built")
            return
        }
        let answered = Set(built.admissions.map(\.id))
        Self.delaySignalPartA(built)
        await Self.delaySignalPartB(built)
        await Self.delaySignalPartC(answered)
        await Self.delaySignalPartD(answered)
        await meter.record(
            TokenUsage(promptTokens: built.admissions.count * 11, completionTokens: built.admissions.count * 4),
            for: ProviderIdentifier.delaySignalHost.rawValue
        )
    }

    // MARK: - A

    static func delaySignalPartA(_ run: LabelReturnRun) {
        let points = Self.conformalCalibration()
        let admitted = Set(run.admissions.map(\.id))
        let live = points.filter { admitted.contains($0.id) }
        let wrong = live.filter(\.wasWrong).map { Double(Self.labelReturnDelay(score: $0.score, wasWrong: true)) }
        let right = live.filter { !$0.wasWrong }
            .map { Double(Self.labelReturnDelay(score: $0.score, wasWrong: false)) }
        print("  A. the dependence was in the fixture the whole time")
        print("     delay = 2 + floor(score x 8) + (wasWrong ? 6 : 0)")
        print("     the last term is not difficulty. It is the outcome, in the arrival time.")
        print("     over the \(live.count) turns this stack answered:")
        print("       mean delay, loss      \(Self.number(Self.average(wrong), 2)) ticks "
            + "(\(wrong.count) turns)")
        print("       mean delay, no loss   \(Self.number(Self.average(right), 2)) ticks "
            + "(\(right.count) turns)")
    }

    // MARK: - B

    static func delaySignalPartB(_ run: LabelReturnRun) async {
        print("  B. reading it through the bridge, at four cutoffs")
        for tick in [4, 6, 8, 12] {
            let snapshot = await run.ledger.snapshot(asOf: LabelReturnKit.LogicalTime(tick))
            let panel = LedgerPanel.panel(from: snapshot)
            let decision = (try? DelaySignalEstimator.decide(panel: panel, settings: .standard))
                ?? .declined(.nothingAdmitted)
            print("     t\(tick)  in \(panel.returned.count)/\(panel.admittedCount)  \(decision.summary)")
        }
        print("     It never reaches the separation test, and what stops it is the mechanism in its")
        print("     purest form: at t4, t6 and t8 twelve of fifteen labels are in and not one is a")
        print("     loss. Every loss takes at least eight ticks by construction, so the panel holds")
        print("     nothing but clean answers and the number it would quote is 0.0000 against a truth")
        print("     of 0.2000. Declining on zero loss labels is the only defensible move: with none")
        print("     of one class there is no rate to fit, and a perfect score is what the arithmetic")
        print("     produces if you let it. Scenario 41's bracket is the right tool at this size.")
    }

    // MARK: - C

    /// The same rule at more volume. Nothing about the delay changes; only how much of it there is.
    static func delaySignalPartC(_ answered: Set<String>) async {
        print("  C. the same rule, at traffic this stack does not have — read at t\(Self.delaySignalCutoff)")
        print("     turns   in  ratio      LR       p  verdict")
        for copies in [1, 4, 10, 20, 40] {
            let population = Self.delaySignalPopulation(copies: copies, answered: answered)
            guard let estimator = await Self.delaySignalEstimator(over: population) else { continue }
            let cutoff = DelaySignalKit.LogicalTime(Self.delaySignalCutoff)
            guard let panel = try? await estimator.panel(asOf: cutoff),
                let decision = try? await estimator.estimate(asOf: cutoff) else {
                continue
            }
            let test = decision.risk?.separation ?? Self.delaySignalDeclinedTest(decision)
            let head = "     \(Self.pad(population.count, 5))\(Self.pad(panel.returned.count, 5))"
            guard let test else {
                print(head + "  \(decision.summary)")
                continue
            }
            let stats = "  \(Self.number(test.ratio, 4))  \(Self.number(test.likelihoodRatio, 3))"
                + "  \(Self.number(test.pValue, 4))"
            switch decision {
            case .corrected(let risk):
                print(head + stats + "  corrected \(Self.number(risk.corrected, 4)) "
                    + "from \(Self.number(risk.naive, 4))")
            case .declined:
                print(head + stats + "  declined")
            }
        }
        print("     The +6 is the same size in every row. What changes is whether it can be told")
        print("     apart from a small sample.")
    }

    // MARK: - D

    static func delaySignalPartD(_ answered: Set<String>) async {
        print("  D. the correction against LabelReturnKit's bracket, on the same events")
        let population = Self.delaySignalPopulation(copies: 40, answered: answered)
        let cutoff = DelaySignalKit.LogicalTime(Self.delaySignalCutoff)
        guard let estimator = await Self.delaySignalEstimator(over: population),
            let risk = try? await estimator.estimate(asOf: cutoff).risk,
            let snapshot = await Self.delaySignalSnapshot(over: population, asOf: Self.delaySignalCutoff),
            let reconciliation = Reconciliation.compare(
                snapshot: snapshot,
                risk: risk,
                selectivityTolerance: 0.15
            )
        else {
            print("     no correction to reconcile")
            return
        }
        let truth = Double(population.filter(\.wasWrong).count) / Double(population.count)
        print("     floor \(Self.number(reconciliation.floor, 4))   "
            + "ceiling \(Self.number(reconciliation.ceiling, 4))   "
            + "dropped-denominator \(Self.number(reconciliation.droppedDenominator, 4))")
        print("     corrected \(Self.number(reconciliation.corrected, 4))   "
            + "truth \(Self.number(truth, 4))")
        print("     \(reconciliation.verdict)")
        print("     weighting comparable: \(reconciliation.weightingComparable) — every turn here is")
        print("     admitted at certainty, so the unweighted correction and the weighted bracket are")
        print("     answering the same question.")
        print("")
        print("     And the correction under-shoots, which is worth more than a clean row would be.")
        print("     It moves the right way and closes about a quarter of the gap: naive is 0.1108")
        print("     from the truth, corrected is 0.0816. It stops there because this demo's delay")
        print("     rule is not exponential. 2 + floor(score x 8) + 6 is close to two-point, and")
        print("     an exponential fitted to it keeps a tail the real delays do not have, so it")
        print("     believes fewer losses are outstanding than there are.")
        print("     DelaySignalKit's own demo shows the separation test catching a wrong shape by")
        print("     collapsing the two rates together. That was luck rather than a guarantee. Here")
        print("     the shape is wrong and the two classes are genuinely far apart — 10.00 ticks")
        print("     against 2.17 — so the test passes honestly and the estimate is still short.")
        print("     The bracket still holds it. That is what the bracket is for.")
    }

    // MARK: - fixture

    /// Late enough that the fast class is almost entirely in and early enough that the slow class is
    /// not, which is the only window in which a delay carries information about an outcome.
    static let delaySignalCutoff = 16

    struct DelaySignalTurn {
        let id: String
        let admittedAt: Int
        let wasWrong: Bool
        let delay: Int
    }

    /// The turns this stack actually answered, tiled, with a deterministic arrival jitter so the
    /// copies are more traffic rather than the same turn stamped repeatedly.
    ///
    /// Tiled from the answered set rather than the whole calibration set, so the loss rate this part
    /// is estimating is the same `0.2000` parts A and B are looking at. Tiling everything the gate
    /// scored would quietly change the question to one about turns nobody answered.
    static func delaySignalPopulation(copies: Int, answered: Set<String>) -> [DelaySignalTurn] {
        let points = Self.conformalCalibration().filter { answered.contains($0.id) }
        var turns: [DelaySignalTurn] = []
        for copy in 0..<copies {
            for (index, point) in points.enumerated() {
                let identifier = "\(point.id)#\(copy)"
                let jitter = Int(Self.delaySignalHash(identifier) % 6)
                let base = Self.labelReturnDelay(score: point.score, wasWrong: point.wasWrong)
                turns.append(
                    DelaySignalTurn(
                        id: identifier,
                        admittedAt: (copy * points.count + index) % 20,
                        wasWrong: point.wasWrong,
                        delay: base + jitter
                    )
                )
            }
        }
        return turns
    }

    static func delaySignalEstimator(over turns: [DelaySignalTurn]) async -> DelaySignalEstimator? {
        let estimator = DelaySignalEstimator()
        do {
            try await estimator.admit(
                contentsOf: turns.map {
                    Admission(id: $0.id, admittedAt: DelaySignalKit.LogicalTime($0.admittedAt))
                }
            )
        } catch {
            return nil
        }
        await estimator.record(
            contentsOf: turns.map {
                Verification(
                    id: $0.id,
                    label: $0.wasWrong ? .loss : .noLoss,
                    returnedAt: DelaySignalKit.LogicalTime($0.admittedAt + $0.delay)
                )
            }
        )
        return estimator
    }

    static func delaySignalSnapshot(over turns: [DelaySignalTurn], asOf tick: Int) async -> LedgerSnapshot? {
        let fingerprint = GateFingerprint(identifier: "delay-signal", threshold: 0.5)
        let admissions = turns.map {
            PendingAdmission(
                id: $0.id,
                region: "answered",
                admissionProbability: 1,
                admittedAt: LabelReturnKit.LogicalTime($0.admittedAt),
                gate: fingerprint
            )
        }
        guard let ledger = try? ReturnLedger(admissions: admissions) else { return nil }
        await ledger.record(
            contentsOf: turns.map {
                ReturnedLabel(
                    id: $0.id,
                    outcome: $0.wasWrong ? .loss : .noLoss,
                    returnedAt: LabelReturnKit.LogicalTime($0.admittedAt + $0.delay),
                    gate: fingerprint
                )
            }
        )
        return await ledger.snapshot(asOf: LabelReturnKit.LogicalTime(tick))
    }

    static func delaySignalDeclinedTest(_ decision: EstimatorDecision) -> SeparationTest? {
        guard case .declined(.noSeparation(let test)) = decision else { return nil }
        return test
    }

    /// splitmix64's finaliser over the identifier's bytes. Deterministic across runs and machines,
    /// and it avalanches — ids differing in one byte must not land on the same jitter.
    static func delaySignalHash(_ identifier: String) -> UInt64 {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in identifier.utf8 {
            state = (state ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static func number(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: " ", count: Swift.max(0, width - text.count)) + text
    }
}
