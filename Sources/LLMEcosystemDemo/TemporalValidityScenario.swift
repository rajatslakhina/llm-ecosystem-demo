import AnswerabilityKit
import Foundation
import ProviderGatewayKit
import SourceIndependenceKit
import TemporalValidityAnswerability
import TemporalValidityKit
import TokenMeterKit

/// The identifier the thirty-fifth scenario bills its one *authorised* hop against.
extension ProviderIdentifier {
    static let temporalHost = ProviderIdentifier("temporal-host")
}

extension EcosystemDemo {
    /// The thirty-fifth scenario: **every gate passes, and all of it is out of date.**
    ///
    /// Scenario 33 established this demo's spending rule — pay only for a verdict that survives its
    /// own evidence being taken apart. Scenario 34 found the rule was being fed document identifiers
    /// nobody had derived. Both are questions about *content*: how many distinct voices, and would
    /// the verdict hold if one of them went quiet.
    ///
    /// Neither can tell a chorus from an echo of an old recording. Three genuinely independent
    /// sources that all reported the same figure in 2023 are three independent *stale* sources, and
    /// a verdict that survives losing any one of them is robustly, independently wrong.
    static func runTemporalValidityScenario(meter: TokenMeter) async {
        let question = "how long does a failed deployment take to roll back"
        print("[temporal scenario] Q: \(question)")

        let independence = SourceIndependenceAnalyzer().analyse(Self.temporalPassages)
        print("  A. what scenarios 33 and 34 ask of this corpus")
        print("    independence    \(independence.summary)")

        let assessment = Self.temporalAnalyzer.assess(Self.temporalObservations, asOf: Self.temporalAsOf)
        print("  B. the same corpus, read as of the moment it was asked about")
        for id in assessment.order {
            guard let reading = assessment.readings[id] else { continue }
            print("    \(id.padding(toLength: max(id.count, 14), withPad: " ", startingAt: 0))  \(reading)")
        }
        print("    standing        \(assessment.standing)")
        print("    entitledFloor   \(assessment.entitledFloor)")

        let finding = TemporalAdmissionProbe().probe(
            Question(question),
            evidence: Self.temporalEvidence,
            assessment: assessment
        )
        print("    probe           \(Self.temporalLabel(finding))")
        await Self.spendIfTimeSafe(finding, meter: meter)

        print("  independence counts voices. It cannot ask whether any of them has spoken since.")
    }

    private static let temporalAsOf = Date(timeIntervalSince1970: 1_786_924_800)
    private static let rollbackTiming = SubjectKey("rollback-timing")
    private static let incidentRecord = SubjectKey("incident-41")

    private static var temporalAnalyzer: TemporalValidityAnalyzer {
        TemporalValidityAnalyzer(
            catalog: VolatilityCatalog([rollbackTiming: .quarterly, incidentRecord: .immutable])
        )
    }

    /// Scenario 34's corpus with the tracking noise removed, so these really are four sources.
    ///
    /// The point of reusing it is that `SourceIndependenceKit` has nothing to merge here — this is
    /// the case where independence is genuinely high and the answer is still not one to give.
    private static var temporalPassages: [SourceIndependenceKit.Passage] {
        [
            Passage(
                id: "runbook",
                locator: "https://example.com/docs/rollback",
                text: "A failed deployment is rolled back automatically within two minutes of the health check failing."
            ),
            Passage(
                id: "blog",
                locator: "https://engineering.other.example/posts/deploy-safety",
                text: "Their platform reverts a bad deploy in about two minutes, triggered by health checks."
            ),
            Passage(
                id: "wiki",
                locator: "https://wiki.example.net/deployment/rollback-timing",
                text: "Rollback completes inside a two minute window once the health check reports failure."
            ),
            Passage(
                id: "incident",
                locator: "https://status.example.com/incidents/41",
                text: "Incident 41 was closed once the platform reported the revert as finished."
            )
        ]
    }

    /// The same four passages, dated. Three speak to rollback timing and all three predate the
    /// change; the incident record is a historical fact and cannot go stale.
    private static var temporalObservations: [EvidenceObservation] {
        [
            EvidenceObservation(id: "runbook", subject: rollbackTiming, observedAt: daysBefore(980)),
            EvidenceObservation(id: "blog", subject: rollbackTiming, observedAt: daysBefore(940)),
            EvidenceObservation(id: "wiki", subject: rollbackTiming, observedAt: daysBefore(910)),
            EvidenceObservation(id: "incident", subject: incidentRecord, observedAt: daysBefore(950))
        ]
    }

    private static var temporalEvidence: [EvidenceItem] {
        temporalPassages.map { EvidenceItem(id: $0.id, text: $0.text) }
    }

    private static func daysBefore(_ count: Int) -> Date {
        temporalAsOf.addingTimeInterval(-Double(count) * 86_400)
    }

    private static func temporalLabel(_ finding: TemporalAdmissionFinding) -> String {
        switch finding {
        case .timeInvariant(let verdict):
            return "time-invariant — \(verdict)"
        case let .timeDependent(all, entitled, withheld):
            return "TIME-DEPENDENT — \(all) becomes \(entitled), withholding \(withheld.joined(separator: ", "))"
        case .undetermined(let reason):
            return "undetermined — \(reason)"
        }
    }

    /// Scenario 33's rule with one clause added: the hop is spent only against a verdict that
    /// survived being taken apart *and* rests on evidence entitled to speak.
    private static func spendIfTimeSafe(_ finding: TemporalAdmissionFinding, meter: TokenMeter) async {
        guard finding.isTimeSafe else {
            print("    cost            $0 — nothing here is entitled to speak, routed to review")
            return
        }
        let prompt = "Summarise the rollback timing"
        do {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .temporalHost, script: [
                    "A failed deployment reverts automatically within two minutes of a failing health check."
                ])
            ])
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: prompt.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.temporalHost.rawValue
            )
            print("    cost            paid — routed via \(response.providerID)")
        } catch {
            print("    cost            hop failed: \(error)")
        }
    }
}
