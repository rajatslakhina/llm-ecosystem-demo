import AnswerabilityKit
import ClaimSegmenterKit
import Foundation
import GroundingKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the thirty-first scenario bills its one avoidable hop against.
extension ProviderIdentifier {
    static let answerabilityHost = ProviderIdentifier("answerability-host")
}

extension EcosystemDemo {
    /// The thirty-first scenario: **every verifier in this demo runs after the money is spent.**
    ///
    /// Scenarios 26 through 30 built a chain that gets steadily better at telling you an answer was
    /// wrong — segmented, decontextualized, attributed, grounded, checked for consistency. All of it
    /// happens downstream of a provider call that has already been paid for.
    ///
    /// This scenario runs the same question twice over the same corpus. Once the way the demo has
    /// done it so far: send, pay, then let `GroundingKit` judge what came back. Once with
    /// `AnswerabilityKit` in front: the gate reads the question against the evidence and declines
    /// before the hop happens.
    ///
    /// The ungated path is the more instructive half, and it did not go the way this comment
    /// originally predicted. The model invents `build 41`, a token appearing in no source — and
    /// grounding returns **partially supported at 43%**, because every other word in the sentence
    /// overlaps `doc-agg-drop`. An overlap scorer cannot notice that the one token carrying the
    /// answer is the one token nothing backs, so the verdict bought with that hop is reassuring
    /// about a fabrication.
    ///
    /// The two findings are not the same finding, which is the point. Grounding judges *the
    /// answer*. Answerability judges *the question*, names the aspect the corpus never covered,
    /// and does it before anything is spent.
    static func runAnswerabilityScenario(meter: TokenMeter) async {
        let question = "When did the streaming aggregator start dropping frames?"
        print("[answerability scenario] Q: \(question)")

        await Self.describeUngatedPath(question: question, meter: meter)
        await Self.describeGatedPath(question: question)
        await Self.compareCost(meter: meter)
    }

    /// A corpus written entirely about the subject that never once states a time.
    ///
    /// This is the shape a similarity threshold cannot see past: the more thoroughly the corpus
    /// discusses the aggregator, the better it scores, and the more confident the send decision.
    private static var aggregatorEvidence: [(id: String, text: String)] {
        [
            ("doc-agg-overview", "The streaming aggregator merges partial deltas into one ordered stream."),
            ("doc-agg-buffer", "The streaming aggregator buffers out-of-order chunks until the sequence settles."),
            ("doc-agg-drop", "The streaming aggregator drops frames once the buffer is saturated.")
        ]
    }

    /// What the demo did before today: pay first, discover the gap afterwards.
    private static func describeUngatedPath(question: String, meter: TokenMeter) async {
        do {
            let reply = "The streaming aggregator began dropping frames in build 41."
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .answerabilityHost, script: [reply])
            ])
            let response = try await LLMSession(router: router).send(question)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: question.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.answerabilityHost.rawValue
            )
            print("  ungated: routed via \(response.providerID), answer: \"\(response.text)\"")

            let sources = try EvidenceSet(aggregatorEvidence.map {
                GroundingKit.SourceDocument(id: GroundingKit.SourceID($0.id), text: $0.text)
            })
            let grounding = try await GroundingVerifier(
                segmenter: ClaimSegmenterBridge(policy: .default)
            ).verify(answer: response.text, against: sources, policy: .strict, at: 1)

            for verdict in grounding.verdicts {
                print("           grounding: \(verdict.level.rawValue) "
                    + "\(Int((verdict.support.score * 100).rounded()))% vs \(verdict.support.sourceID)")
            }
            // Worth reading twice: the verdict is not `unsupported`. `build 41` appears in no
            // source, but the rest of the sentence shares its wording with doc-agg-drop, and an
            // overlap scorer has no way to notice that the one token carrying the actual answer
            // is the one token nothing supports.
            print("           the answer names build 41, which appears in no source - "
                + "and grounding still called it partially supported, because everything "
                + "around that number overlaps doc-agg-drop.")
            print("           one hop paid for, and the verdict bought with it is reassuring.")
        } catch {
            print("[answerability scenario] ungated path FAILED: \(error)")
        }
    }

    /// The same question, judged before anything is sent.
    private static func describeGatedPath(question: String) async {
        let gate = AnswerabilityGate(engine: AnswerabilityEngine(policy: .lenient))
        let report = await gate.admit(
            Question(question),
            evidence: aggregatorEvidence.map { EvidenceItem(id: $0.id, text: $0.text) }
        )

        print("  gated:   verdict \(Self.describe(report.verdict))")
        for assessment in report.assessments {
            print("           \(Self.pad(assessment.aspect.kind.rawValue, 11))"
                + Self.pad(assessment.aspect.surface, 44)
                + "affirm \(String(format: "%.2f", assessment.affirming))"
                + (assessment.isCovered ? "" : "   <- nothing speaks to this"))
        }

        let coverage = report.coverageRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("           coverage \(coverage), evidence examined: \(report.evidenceCount) passage(s)")

        // The property that makes the gate safe to wire in: there is no approved text to
        // forward, so a caller cannot spend money by forgetting to read the verdict.
        print("           approvedQuestion: \(report.approvedQuestion.map { "\"\($0)\"" } ?? "nil")")
        if let reason = report.blockingReason {
            print("           refusal reaching the user: \(reason)")
        }

        let stats = await gate.statistics()
        let rate = stats.abstentionRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("           gate stats: ruled \(stats.ruled), blocked \(stats.blocked), abstention \(rate)")
    }

    /// The comparison is computed rather than asserted, so it changes on its own if the corpus does.
    private static func compareCost(meter: TokenMeter) async {
        let spent = await meter.cost(for: ProviderIdentifier.answerabilityHost.rawValue)
        print("  ungated cost: $\(spent)   gated cost: $0 - the gate runs before the hop")
        print("  grounding judged the ANSWER and found it partially supported. Answerability "
            + "judged the QUESTION and found the corpus never held a time at all.")
        print("  the second is the load-bearing one here: it is the finding that is correct, "
            + "and it is the one available for free.")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func describe(_ verdict: AnswerabilityVerdict) -> String {
        switch verdict {
        case .answerable:
            return "ANSWERABLE"
        case .insufficient(let missing):
            return "BLOCKED insufficient - missing: \(missing.joined(separator: ", "))"
        case .contested(let aspects):
            return "BLOCKED contested - disputed: \(aspects.joined(separator: ", "))"
        case .undetermined(.tooFewAspects(let found, let required)):
            return "UNDETERMINED - \(found) aspect(s) read, \(required) required"
        case .undetermined(.noEvidenceOffered):
            return "UNDETERMINED - no evidence offered"
        }
    }
}
