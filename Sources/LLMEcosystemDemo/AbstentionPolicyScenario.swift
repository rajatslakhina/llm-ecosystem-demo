import AbstentionPolicyAnswerability
import AbstentionPolicyKit
import AnswerabilityKit
import Foundation
import ProviderGatewayKit
import SourceIndependenceKit
import TemporalValidityKit
import TokenMeterKit

/// The identifier the thirty-sixth scenario bills its one *answered* turn against.
extension ProviderIdentifier {
    static let abstentionHost = ProviderIdentifier("abstention-host")
}

extension EcosystemDemo {
    /// The thirty-sixth scenario: **no gate refuses, and the turn is still not one to answer.**
    ///
    /// Every scenario from 26 to 35 ends with one judge blocking. That is the easy half. This one
    /// runs a corpus where the answerability gate admits, independence finds more than one voice,
    /// and the temporal read leaves something entitled to speak — so under the pipeline every
    /// earlier scenario has been built on, the turn is paid for.
    ///
    /// Each of those three judges is nonetheless holding a reservation it has nowhere to put. A
    /// judge unwilling to block on its own finding *discards* the finding. Three separate
    /// weaknesses, each survivable alone, currently add up to nothing because nobody counts.
    static func runAbstentionPolicyScenario(meter: TokenMeter) async {
        let ledger = AbstentionLedger(arbiter: AbstentionArbiter(policy: .standard))

        print("[abstention scenario] two turns through the same judges, arbitrated once each")

        print("  A. a turn where no single gate objects")
        let weak = await Self.abstentionSignals(for: Self.weakCorpus)
        for signal in weak { print("    \(signal.summary)") }
        let weakRuling = await ledger.rule(on: weak)
        Self.report(weakRuling)
        await Self.spendIfAnswerable(weakRuling, meter: meter, label: "rollback timing")

        print("  B. the same judges, a corpus that holds up")
        let strong = await Self.abstentionSignals(for: Self.strongCorpus)
        for signal in strong { print("    \(signal.summary)") }
        let strongRuling = await ledger.rule(on: strong)
        Self.report(strongRuling)
        await Self.spendIfAnswerable(strongRuling, meter: meter, label: "rollback timing")

        // Hindsight the arbiter does not have at decision time: the answered turn was right.
        await ledger.recordOutcome(wasCorrect: true)
        let stats = await ledger.statistics()
        print("  C. risk and coverage over both turns")
        print("    coverage        \(Self.percent(stats.coverage()))  (\(stats.answered)/\(stats.rulings) answered)")
        print("    selective risk  \(Self.percent(stats.selectiveRisk())) over \(stats.outcomesReported) reported")

        print("  Every gate passing is not the same as every gate being satisfied.")
    }

    // MARK: - Deriving signals from the judges that are already here

    /// Runs the three judges this demo already owns and turns each into one signal.
    ///
    /// Nothing here is hand-written. The answerability reading comes across the seam through
    /// `AnswerabilitySignalMapper`; the other two are derived from what those analysers actually
    /// returned for this corpus, which is the only way the scenario can be wrong in a way that
    /// shows up rather than one that reads well.
    static func abstentionSignals(for corpus: AbstentionCorpus) async -> [AbstentionSignal] {
        let report = AnswerabilityEngine().assess(Question(corpus.question), against: corpus.evidence)
        let gateSignal = AnswerabilitySignalMapper().signal(for: report)

        let independence = SourceIndependenceAnalyzer().analyse(corpus.passages)
        let independenceSignal = AbstentionSignal(
            origin: SignalOrigin("independence"),
            reading: independence.mergedPassageCount > 0
                ? .concern(.low, Self.counted(independence.mergedPassageCount, "passage") + " merged into "
                    + Self.counted(independence.establishedSourceCount, "source"))
                : .clear
        )

        let assessment = TemporalValidityAnalyzer(catalog: corpus.catalog)
            .assess(corpus.observations, asOf: abstentionAsOf)
        let temporalSignal = AbstentionSignal(
            origin: SignalOrigin("temporal"),
            reading: Self.temporalReading(assessment)
        )

        return [gateSignal, independenceSignal, temporalSignal]
    }

    /// A mixed standing is the interesting case and the reason this scenario exists.
    ///
    /// `TemporalValidityKit` refuses a turn when *nothing* is entitled to speak. When some of the
    /// corpus is stale and some is not, it has a real finding and no grounds to block on it — so
    /// today that finding is dropped on the floor. Here it becomes one voice among three.
    private static func temporalReading(_ assessment: TemporalAssessment) -> SignalReading {
        switch assessment.standing {
        case .current: return .clear
        case .mixed(let entitled, let stale):
            return .concern(
                .low,
                "\(stale) of " + Self.counted(entitled + stale, "passage") + " no longer entitled to speak"
            )
        case .whollyStale(let count): return .refuse("all \(count) passages are stale")
        case .undetermined(let reason): return .unavailable("\(reason)")
        case .noEvidence: return .unavailable("no observations offered")
        }
    }

    private static func report(_ ruling: AbstentionRuling) {
        print("    ruling          \(ruling.decision.summary)")
        print("    headline        \(ruling.headline)")
        let exact = ruling.exactConcurrenceCount().map(String.init) ?? "unknown"
        print("    concurrence     floor \(ruling.concurrenceFloor), exact \(exact)")
    }

    /// Counts a noun for a line somebody reads. "1 passages merged" makes a reader doubt the
    /// number as well as the grammar, and this scenario's whole point is a number.
    private static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "\(count) \(noun)" : "\(count) \(noun)s"
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f%%", value * 100)
    }

    static func spendIfAnswerable(
        _ ruling: AbstentionRuling,
        meter: TokenMeter,
        label: String
    ) async {
        guard !ruling.isAbstention else {
            print("    cost            $0 — \(ruling.explanation)")
            return
        }
        let prompt = "Summarise the \(label)"
        do {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .abstentionHost, script: [
                    "A failed deployment reverts automatically within ninety seconds of a failing health check."
                ])
            ])
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: prompt.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.abstentionHost.rawValue
            )
            print("    cost            paid — routed via \(response.providerID)")
        } catch {
            print("    cost            hop failed: \(error)")
        }
    }

    private static let abstentionAsOf = Date(timeIntervalSince1970: 1_786_924_800)
    private static let rollback = SubjectKey("rollback-window")
    private static let healthCheck = SubjectKey("health-check")
}

/// One turn's worth of the same corpus, in the three shapes the three judges each want it in.
///
/// Carried as one value so a scenario cannot quietly hand independence a corpus that the
/// answerability gate never saw — the mistake 08-14 found by hand and 08-17 found again.
struct AbstentionCorpus {
    let question: String
    let evidence: [EvidenceItem]
    let passages: [SourceIndependenceKit.Passage]
    let observations: [EvidenceObservation]
    let catalog: VolatilityCatalog
}

extension EcosystemDemo {
    /// A corpus that clears every bar and satisfies nobody.
    ///
    /// The gate admits: both aspects are covered. Independence finds two sources, not one — but it
    /// merged a third passage into one of them, which is a real finding it has no grounds to block
    /// on. The temporal read leaves the newer passage entitled and the older one expired, which is
    /// `mixed` — also real, also not blocking.
    static var weakCorpus: AbstentionCorpus {
        AbstentionCorpus(
            question: "how long is the rollback window after a failed health check",
            evidence: [
                EvidenceItem(id: "runbook", text: "The rollback window after a failed health check is two minutes."),
                EvidenceItem(id: "mirror", text: "The rollback window after a failed health check is two minutes."),
                EvidenceItem(id: "wiki", text: "A failed health check starts a rollback window of two minutes.")
            ],
            passages: [
                Passage(
                    id: "runbook",
                    locator: "https://example.com/docs/rollback",
                    text: "The rollback window after a failed health check is two minutes."
                ),
                Passage(
                    id: "mirror",
                    locator: "https://example.com/docs/rollback?utm_source=newsletter",
                    text: "The rollback window after a failed health check is two minutes."
                ),
                Passage(
                    id: "wiki",
                    locator: "https://wiki.example.com/rollback",
                    text: "A failed health check starts a rollback window of two minutes."
                )
            ],
            observations: [
                EvidenceObservation(
                    id: "wiki",
                    subject: healthCheck,
                    observedAt: Date(timeIntervalSince1970: 1_786_800_000)
                ),
                EvidenceObservation(
                    id: "runbook",
                    subject: rollback,
                    observedAt: Date(timeIntervalSince1970: 1_690_000_000)
                )
            ],
            catalog: VolatilityCatalog([rollback: .quarterly, healthCheck: .quarterly])
        )
    }

    /// The same question, answered by a corpus with nothing to hold against it.
    static var strongCorpus: AbstentionCorpus {
        AbstentionCorpus(
            question: "how long is the rollback window after a failed health check",
            evidence: [
                EvidenceItem(id: "runbook", text: "The rollback window after a failed health check is ninety seconds."),
                EvidenceItem(id: "sre", text: "A failed health check opens a rollback window of ninety seconds.")
            ],
            passages: [
                Passage(
                    id: "runbook",
                    locator: "https://example.com/docs/rollback",
                    text: "The rollback window after a failed health check is ninety seconds."
                ),
                Passage(
                    id: "sre",
                    locator: "https://sre.example.com/runbooks/rollback",
                    text: "A failed health check opens a rollback window of ninety seconds."
                )
            ],
            observations: [
                EvidenceObservation(
                    id: "runbook",
                    subject: rollback,
                    observedAt: Date(timeIntervalSince1970: 1_786_800_000)
                ),
                EvidenceObservation(
                    id: "sre",
                    subject: healthCheck,
                    observedAt: Date(timeIntervalSince1970: 1_786_820_000)
                )
            ],
            catalog: VolatilityCatalog([rollback: .quarterly, healthCheck: .quarterly])
        )
    }
}
