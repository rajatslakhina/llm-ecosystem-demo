import CurveDivergenceKit
import DelayCurveKit
import Foundation
import LabelClockKit
import ProviderGatewayKit
import TokenMeterKit

extension ProviderIdentifier {
    static let labelClockHost = ProviderIdentifier("label-clock-host")
}

/// What the nonconformity scorer's output looks like across the turns being banded.
///
/// A struct rather than a tuple because three members is where a tuple stops naming its own
/// contents, and this one is read at a call site four screens away from where it is built.
struct LabelClockScoreShape {
    let distinct: Int
    let median: Double
    let minimum: Double
}

extension EcosystemDemo {
    /// The forty-sixth scenario: **the arms scenarios 44 and 45 compared could not have been built
    /// by anything that did not already know the answer.**
    ///
    /// `delayCurveSample(_:asOf:wrong:)` splits the population on `wasWrong` and *then* marks a turn
    /// outstanding when its delay runs past the cut-off. Read those two steps in order. The second
    /// says the label has not come back. The first says which class the turn is in — and in this
    /// fixture that is knowable for an outstanding turn only because the fixture generated it. A
    /// consumer holding real traffic has exactly the outstanding turns and none of their classes.
    ///
    /// So the censoring in scenarios 44 and 45 is real arithmetic over a class assignment nothing in
    /// production could make. Nothing there is wrong about the statistics; what is wrong is the
    /// claim that a service could reproduce them. This scenario measures that, and then does the
    /// comparison a service actually can.
    static func runLabelClockScenario(meter: TokenMeter) async {
        print("[label clock scenario] the arms two scenarios compared, and who could have built them")
        guard let answered = await Self.delayShapeAnswered() else {
            print("  the ledger could not be built")
            return
        }
        let population = Self.delaySignalPopulation(copies: 40, answered: answered)
        let scores = Self.labelClockScores()
        guard let fused = Self.labelClockLedger(population, scores: scores, honest: false),
            let honest = Self.labelClockLedger(population, scores: scores, honest: true)
        else {
            print("  both ledgers are needed and one could not be formed")
            return
        }
        let summary = Self.labelClockScoreSummary(population, scores: scores)
        await Self.labelClockPartA(fused: fused, honest: honest, scores: summary)
        await Self.labelClockPartB(fused: fused)
        await Self.labelClockPartC(honest: honest)
        await meter.record(
            TokenUsage(promptTokens: population.count * 4, completionTokens: population.count * 2),
            for: ProviderIdentifier.labelClockHost.rawValue
        )
    }

    // MARK: - A

    static func labelClockPartA(
        fused: ObservationLedger,
        honest: ObservationLedger,
        scores: LabelClockScoreShape
    ) async {
        print("  A. the same \(fused.count) turns, and the two fields a cohort could come out of")
        let auditor = LedgerAuditor()
        let fusedAudit = await auditor.audit(fused)
        let honestAudit = await auditor.audit(honest)
        print("     cohort = wasWrong, decided when the label returned:")
        print("       \(fusedAudit.verdict)")
        print("       \(fusedAudit.table)")
        print("       \(fusedAudit.clocks)")
        print("     cohort = conformal score band, decided at admission:")
        print("       \(honestAudit.verdict)")
        print("       \(honestAudit.table)")
        print("       \(honestAudit.clocks)")
        print("     The score is computed before the answer is judged, so the second cohort is one a")
        print("     live gate already holds. The first is the outcome, wearing a covariate's name.")
        let degenerate = scores.median == scores.minimum ? "and its median is its minimum" : "with a usable median"
        print("     Across these turns the scorer emits \(scores.distinct) distinct values \(degenerate),")
        print("     so the band is the coarse one a gate already acts on — any nonconformity, or none —")
        print("     rather than a quantile split that would put every turn on one side.")
    }

    // MARK: - B

    static func labelClockPartB(fused: ObservationLedger) async {
        print("  B. every landmark on the fused ledger")
        let former = ArmFormer(settings: ClockSettings(minimumCensorableUnits: 1, minimumArmSize: 1))
        var refused = 0
        var tried = 0
        for landmark in 0...fused.longestFollowUp {
            tried += 1
            do {
                let arms = try await former.arms(from: fused, at: landmark)
                print("     t+\(landmark): \(arms.retained) retained, \(arms.censored) censored")
            } catch {
                refused += 1
            }
        }
        print("     \(tried) landmarks across the whole follow-up, \(refused) refusals, 0 arms formed.")
        print("     This is not scarcity. A turn carries a cohort here exactly when its label has")
        print("     come back, and the landmark method excludes exactly those turns, so the")
        print("     surviving set is empty by construction at every landmark rather than by luck.")
    }

    // MARK: - C

    static func labelClockPartC(honest: ObservationLedger) async {
        print("  C. the comparison a live gate could actually run")
        let former = ArmFormer(settings: ClockSettings(minimumCensorableUnits: 1, minimumArmSize: 5))
        let landmark = 1
        do {
            let arms = try await former.arms(from: honest, at: landmark)
            for arm in arms.arms {
                print("     \(arm)")
            }
            print("     \(arms.exclusions)")
            guard let flagged = arms["flagged"], let unflagged = arms["unflagged"],
                let flaggedSample = Self.labelClockSample(flagged),
                let unflaggedSample = Self.labelClockSample(unflagged)
            else {
                print("     one arm could not be turned into a curve sample")
                return
            }
            let report = await DivergenceAnalyzer()
                .report(for: DivergenceSample(first: flaggedSample, second: unflaggedSample))
            print("     \(report.verdict)")
            print("     Same two packages as scenario 45, same cut-off, different cohort field. What")
            print("     changed is that every fact this used was on hand before any label returned.")
        } catch {
            print("     the honest ledger refused at t+\(landmark): \(error)")
        }
    }

    // MARK: - fixture

    /// The conformal score for every calibration point, keyed by its id.
    ///
    /// The score is the thing this stack computes to *decide whether to answer*, so it exists at
    /// admission by definition. That is the whole qualification for being a cohort here.
    static func labelClockScores() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: Self.conformalCalibration().map { ($0.id, $0.score) })
    }

    /// Both ledgers over one population, differing only in where the cohort comes from.
    static func labelClockLedger(
        _ population: [DelaySignalTurn],
        scores: [String: Double],
        honest: Bool
    ) -> ObservationLedger? {
        let banded = population.compactMap { turn -> (DelaySignalTurn, Double)? in
            let base = turn.id.split(separator: "#").first.map(String.init) ?? turn.id
            guard let score = scores[base] else { return nil }
            return (turn, score)
        }

        var records: [ObservationRecord] = []
        for (turn, score) in banded {
            let followUp = Self.delaySignalCutoff - turn.admittedAt
            guard followUp >= 1 else { continue }
            let returned = turn.delay <= followUp
            let arrival = returned
                ? LabelArrival(at: turn.admittedAt + turn.delay, content: turn.wasWrong ? "loss" : "clean")
                : nil
            let assignment: CohortAssignment? = honest
                ? CohortAssignment(cohort: score > 0 ? "flagged" : "unflagged", assignedAt: turn.admittedAt)
                : arrival.map { CohortAssignment(cohort: $0.content, assignedAt: $0.at) }
            records.append(
                ObservationRecord(
                    id: turn.id,
                    enrolledAt: turn.admittedAt,
                    assignment: assignment,
                    arrival: arrival,
                    observedThrough: Self.delaySignalCutoff
                )
            )
        }
        return try? ObservationLedger(records)
    }

    static func labelClockSample(_ arm: LandmarkArm) -> CurveSample? {
        let observations = arm.observations.compactMap { observation -> CurveObservation? in
            switch observation {
            case let .returned(afterTicks): return try? CurveObservation.makeReturned(afterTicks: afterTicks)
            case let .outstanding(forTicks): return try? CurveObservation.makeOutstanding(forTicks: forTicks)
            }
        }
        return try? CurveSample(observations)
    }

    /// What the nonconformity scores actually look like across the turns in play.
    ///
    /// Measured over the same turns the ledger is built from rather than the whole calibration set,
    /// because those are two different populations and quoting one while banding the other is how a
    /// demo ends up describing a split it did not perform. Choosing the split by looking at the
    /// scores is legitimate precisely because the scores exist before any label does.
    static func labelClockScoreSummary(
        _ population: [DelaySignalTurn],
        scores: [String: Double]
    ) -> LabelClockScoreShape {
        let values = population.compactMap { turn -> Double? in
            let base = turn.id.split(separator: "#").first.map(String.init) ?? turn.id
            return scores[base]
        }.sorted()
        guard let minimum = values.first else {
            return LabelClockScoreShape(distinct: 0, median: 0, minimum: 0)
        }
        let distinct = Set(values.map { String(format: "%.6f", $0) }).count
        let middle = values.count / 2
        let median = values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
        return LabelClockScoreShape(distinct: distinct, median: median, minimum: minimum)
    }
}
