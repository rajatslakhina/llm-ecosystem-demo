import AnswerabilityKit
import Foundation
import MorphologyMatchAnswerability
import MorphologyMatchKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the thirty-second scenario bills its one *legitimate* hop against.
extension ProviderIdentifier {
    static let morphologyHost = ProviderIdentifier("morphology-host")
}

extension EcosystemDemo {
    /// The thirty-second scenario: **a gate is only as trustworthy as its matcher's recall.**
    ///
    /// Scenario 31 put `AnswerabilityKit` in front of the money and saved an avoidable hop. This
    /// scenario runs the failure mode that arrives with it. The gate refuses when nothing in the
    /// corpus speaks to an aspect — but "nothing speaks to it" is an inference drawn from a matcher
    /// finding no overlap, and that inference is worth exactly as much as the matcher's recall.
    ///
    /// Here the question asks about `requests` that were `retried`. The corpus says a client
    /// `retries` a `request`. Every word matches and none of them matches, so the lexical matcher
    /// reports absence and the gate refuses a question the corpus answers outright.
    ///
    /// The asymmetry worth taking away is in the cost line at the end: **a false refusal is free.**
    /// The meter records hops that happened, so a gate that refuses too much looks *cheaper* than
    /// one that is right. Nothing in this demo's cost report would ever have surfaced this bug —
    /// it took a user asking a reasonable question and being told no.
    static func runMorphologyMatchScenario(meter: TokenMeter) async {
        let question = "which requests were retried"
        print("[morphology scenario] Q: \(question)")

        await Self.describeLexicalRefusal(question: question)
        await Self.describeKeyedAdmission(question: question, meter: meter)
        await Self.describeConflationAudit()
        await Self.describeRefusedConflations()
        await Self.compareRecallCost(meter: meter)
    }

    /// A corpus that answers the question, in words the question does not use verbatim.
    private static var retryEvidence: [(id: String, text: String)] {
        [
            ("doc-retry-policy", "Retry policies apply to idempotent request handlers only."),
            ("doc-retry-client", "The client retries a request when the provider returns 429."),
            ("doc-retry-budget", "Each retry spends from the same deadline budget as the first attempt.")
        ]
    }

    private static var retryItems: [EvidenceItem] {
        retryEvidence.map { EvidenceItem(id: $0.id, text: $0.text) }
    }

    /// The gate as scenario 31 wired it: correct policy, insufficient recall.
    private static func describeLexicalRefusal(question: String) async {
        let gate = AnswerabilityGate(engine: AnswerabilityEngine(policy: .lenient))
        let report = await gate.admit(Question(question), evidence: retryItems)
        print("  lexical matcher:    \(Self.verdictLabel(report.verdict))")
        for assessment in report.assessments {
            print("    \(Self.padded(assessment.aspect.kind.rawValue, 11))"
                + Self.padded(assessment.aspect.surface, 26)
                + "affirm \(String(format: "%.2f", assessment.affirming))"
                + (assessment.isCovered ? "" : "   <- reported as absent"))
        }
        print("    approvedQuestion: \(report.approvedQuestion.map { "\"\($0)\"" } ?? "nil")")
        print("    the corpus answers this question. Nothing was spent, and nothing was gained.")
    }

    /// The same gate, same policy, same corpus — one matcher swapped underneath it.
    private static func describeKeyedAdmission(question: String, meter: TokenMeter) async {
        let gate = AnswerabilityGate(
            engine: AnswerabilityEngine(policy: .lenient, matcher: MorphologyEvidenceMatcher())
        )
        let report = await gate.admit(Question(question), evidence: retryItems)
        print("  morphology matcher: \(Self.verdictLabel(report.verdict))")
        for assessment in report.assessments {
            print("    \(Self.padded(assessment.aspect.kind.rawValue, 11))"
                + Self.padded(assessment.aspect.surface, 26)
                + "affirm \(String(format: "%.2f", assessment.affirming))")
        }
        let coverage = report.coverageRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("    coverage \(coverage), evidence examined: \(report.evidenceCount) passage(s)")

        // The hop only happens because the gate approved it, and it sends `approvedQuestion`
        // rather than the original text — the property that makes a caller fail closed.
        guard let approved = report.approvedQuestion else {
            print("    still refused; no hop attempted")
            return
        }
        do {
            let reply = "The client retries idempotent request handlers after a 429."
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .morphologyHost, script: [reply])
            ])
            let response = try await LLMSession(router: router).send(approved)
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: approved.count / 4,
                    completionTokens: response.text.count / 4
                ),
                for: ProviderIdentifier.morphologyHost.rawValue
            )
            print("    routed via \(response.providerID), answer: \"\(response.text)\"")
        } catch {
            print("    hop FAILED: \(error)")
        }
    }

    /// Which conflations earned the admission. Without this the gate's change of mind is
    /// unauditable, and an unauditable change of mind in a refusal path is not an improvement.
    private static func describeConflationAudit() async {
        let matcher = MorphologyEvidenceMatcher()
        let ledger = ConflationLedger()
        for aspect in LexicalAspectExtractor().aspects(in: Question("which requests were retried")) {
            for item in retryItems {
                await ledger.record(matcher.conflations(for: aspect, in: item))
            }
        }
        print("  conflations that earned it:")
        for family in await ledger.mergedFamilies().prefix(4) {
            print("    \(Self.padded(family.key, 10)) <- \(family.surfaces.joined(separator: ", "))")
        }
        print("    every family is one word's inflections. Two unrelated words sharing a key")
        print("    would be a precision bug, and this report is where it would show.")
    }

    /// The other half of the honest account: recall the kit declined to buy.
    private static func describeRefusedConflations() async {
        let normalizer = MorphologyNormalizer()
        print("  conflations refused, and why that is the point:")
        for term in ["note", "user", "using"] {
            let conflation = normalizer.key(term)
            print("    \(Self.padded(term, 10)) -> \(Self.padded(conflation.key, 10))"
                + "[\(conflation.rule.rawValue)]")
        }
        print("    'note' would key to 'not' - a negation cue - and every clause mentioning a")
        print("    note would read as a denial. In a judge, an invented contradiction is worse")
        print("    than a missed match: one omits a finding, the other manufactures one.")
    }

    private static func compareRecallCost(meter: TokenMeter) async {
        let spent = await meter.cost(for: ProviderIdentifier.morphologyHost.rawValue)
        print("  lexical cost: $0 (refused)   keyed cost: $\(spent) (answered)")
        print("  scenario 31 showed the gate saving a hop that should not have happened. This is")
        print("  the same gate refusing one that should have. Both are the gate working exactly as")
        print("  written; only the matcher underneath it changed.")
        print("  and note which of the two a cost report can see: the meter records hops taken, so")
        print("  the wrong refusal is invisible to it and shows up as a saving.")
    }

    private static func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func verdictLabel(_ verdict: AnswerabilityVerdict) -> String {
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
