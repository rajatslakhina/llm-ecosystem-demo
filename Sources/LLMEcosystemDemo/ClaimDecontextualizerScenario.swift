import ClaimDecontextualizerKit
import ClaimSegmenterKit
import Foundation
import GroundingKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the thirtieth scenario's single routed hop bills against.
extension ProviderIdentifier {
    static let decontextHost = ProviderIdentifier("decontext-host")
}

/// One answer sentence, split into the prose a resolver can work on and the citation it carries.
struct SplitSentence {
    let prose: String
    let citations: String

    /// The sentence as it appeared, with `prose` swapped for `replacement`.
    func rebuilt(with replacement: String) -> String {
        let body = replacement.hasSuffix(".") ? String(replacement.dropLast()) : replacement
        return citations.isEmpty ? body + "." : body + " " + citations + "."
    }
}

extension EcosystemDemo {
    /// The thirtieth scenario: **grounding will happily return a verdict about a claim that has no
    /// subject.**
    ///
    /// Scenarios 28 and 29 both ended on the same defect from opposite sides: a finely-cut claim
    /// gets scored against whichever passage shares the most wording, which is not necessarily the
    /// one it cited. Both treated that as a scoring problem. Some of it is not. A claim reading
    /// `It is not shared across sessions` has no subject at all — there is nothing in it to score
    /// correctly, and the verifier's confident answer is about a sentence nobody wrote.
    ///
    /// `ClaimDecontextualizerKit` is the step before. It rewrites what it can justify and refuses
    /// what it cannot, and this scenario runs `GroundingKit` twice — over the answer as written and
    /// over the answer as resolved — so the difference is visible rather than argued.
    static func runClaimDecontextualizerScenario(meter: TokenMeter) async {
        do {
            let answer = try await routeDecontextTurn(meter: meter)
            let split = answer.components(separatedBy: ". ").map(Self.splitSentence)
            let report = try Self.decontextualize(split.map(\.prose))
            Self.describeResolution(report)

            let rewritten = Self.rewrite(split, using: report)
            print("  answer as resolved: \(rewritten)")

            let before = try await Self.ground(answer)
            let after = try await Self.ground(rewritten)
            Self.compareGrounding(before: before, after: after, report: report)
        } catch {
            print("[claim decontextualizer scenario] FAILED: \(error)")
        }
    }

    /// The same knowledge base scenarios 28 and 29 use. `kb-cache` and `kb-share` both describe the
    /// response cache, which is what makes a subject-less claim about "it" genuinely undecidable.
    private static var decontextSources: [GroundingKit.SourceDocument] {
        [
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-cache"),
                                        text: "The response cache is enabled by default."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-share"),
                                        text: "The response cache is shared across sessions."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-retry"),
                                        text: "The client is capped at two retries."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-stream"),
                                        text: "Streaming is disabled by default."),
            GroundingKit.SourceDocument(
                id: GroundingKit.SourceID("kb-queue"),
                text: "Requests queue behind the limiter and the queue is bounded."
            )
        ]
    }

    private static func routeDecontextTurn(meter: TokenMeter) async throws -> String {
        let prompt = "Question: summarise the caching, retry and queueing behaviour."
        let reply = "The response cache is enabled by default [kb-cache]. "
            + "It is not shared across sessions [kb-share]. "
            + "The client is capped at two retries [kb-retry]. "
            + "They expire after an hour [kb-queue]."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .decontextHost, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: ProviderIdentifier.decontextHost.rawValue
        )
        print("[claim decontextualizer scenario] routed via \(response.providerID)")
        return response.text
    }

    /// Separates the prose from its citation so the resolver reads a sentence rather than a footnote.
    ///
    /// `[kb-share]` carries no referent and would otherwise contribute `kb` and `share` as candidate
    /// antecedents — a resolver scoring a bracket against a pronoun is a category error, not a
    /// near miss.
    static func splitSentence(_ raw: String) -> SplitSentence {
        var prose = ""
        var citations = ""
        var depth = 0
        for character in raw {
            if character == "[" { depth += 1 }
            if depth > 0 { citations.append(character) } else { prose.append(character) }
            if character == "]" { depth = max(0, depth - 1) }
        }
        let cleaned = prose
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return SplitSentence(
            prose: cleaned.hasSuffix(".") ? cleaned : cleaned + ".",
            citations: citations.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func decontextualize(_ prose: [String]) throws -> DecontextualizationReport {
        DecontextualizationEngine(policy: .strict).report(for: try Discourse(prose))
    }

    private static func rewrite(_ split: [SplitSentence], using report: DecontextualizationReport) -> String {
        split.enumerated().map { index, sentence in
            let text = report.standaloneText(at: index) ?? sentence.prose
            return sentence.rebuilt(with: text)
        }.joined(separator: " ")
    }

    private static func ground(_ answer: String) async throws -> GroundingReport {
        try await GroundingVerifier(segmenter: ClaimSegmenterBridge(policy: .default)).verify(
            answer: answer,
            against: try EvidenceSet(decontextSources),
            policy: .strict,
            at: 1
        )
    }

    private static func describeResolution(_ report: DecontextualizationReport) {
        print("  sentence  outcome          detail")
        for entry in report.outcomes {
            print("  s\(entry.sentenceIndex)        "
                + padded(Self.label(entry.outcome), 17)
                + Self.detail(entry.outcome))
        }
        let rate = report.resolutionRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("  \(report.outcomes.count) sentences, \(report.contextDependentCount) context-dependent, "
            + "\(report.resolvedCount) resolved, \(report.refusedCount) refused. Resolution rate \(rate).")
    }

    private static func label(_ outcome: ResolutionOutcome) -> String {
        switch outcome {
        case .alreadyStandalone: return "standalone"
        case .resolved: return "resolved"
        case .ambiguous: return "REFUSED ambig."
        case .noAntecedent: return "REFUSED no ant."
        case .overSpecified: return "REFUSED cost"
        }
    }

    private static func detail(_ outcome: ResolutionOutcome) -> String {
        switch outcome {
        case .alreadyStandalone:
            return "nothing to resolve"
        case .resolved(let result):
            return "\(result.standaloneText)  (+\(result.addedTokens) tokens)"
        case .ambiguous(let report):
            return "margin too narrow for \"\(report.expression.text)\""
        case .noAntecedent(let expression):
            return "nothing agrees with \"\(expression.text)\" "
                + "(\(expression.expectsPlural ? "plural" : "singular")) - left as written"
        case .overSpecified(_, let limit):
            return "substitution would exceed the \(limit)-token budget"
        }
    }

    /// The comparison the scenario exists for: what grounding said before and after resolving.
    private static func compareGrounding(
        before: GroundingReport,
        after: GroundingReport,
        report: DecontextualizationReport
    ) {
        guard before.verdicts.count == after.verdicts.count else {
            print("  segmentation changed under rewriting (\(before.verdicts.count) -> "
                + "\(after.verdicts.count) claims); per-claim comparison skipped")
            return
        }
        print("  claim  as written                          as resolved")
        for (index, pair) in zip(before.verdicts, after.verdicts).enumerated() {
            let lhs = "\(pair.0.level.rawValue) \(percent(pair.0.support.score)) vs \(pair.0.support.sourceID)"
            let rhs = "\(pair.1.level.rawValue) \(percent(pair.1.support.score)) vs \(pair.1.support.sourceID)"
            print("  c\(index)     " + padded(lhs, 36) + rhs + (lhs == rhs ? "" : "   <- changed"))
        }
        print("  -> \(before.decision.kind().rawValue) as written, "
            + "\(after.decision.kind().rawValue) as resolved")
        let moved = zip(before.verdicts, after.verdicts).filter {
            $0.level != $1.level || $0.support.sourceID != $1.support.sourceID
        }.count
        Self.describeUnjustifiedVerdicts(before, report: report, moved: moved)
        print("  extra gateway hops: 0 - decontextualization is local computation over the answer")
    }

    /// The part of the result that is not a win, and is the more useful half.
    ///
    /// Resolving changed no verdict here, because the predicate alone — `shared`, `sessions` — was
    /// enough for the overlap scorer to land on `kb-share`. That is worth stating rather than
    /// dressing up: on this passage the rewrite made an already-correct verdict *justified* rather
    /// than making a wrong one right.
    ///
    /// The claim the resolver refused is the sharper case. Grounding scored it anyway, against a
    /// document it shares nothing with, and returned a level a reader will take at face value.
    private static func describeUnjustifiedVerdicts(
        _ grounding: GroundingReport,
        report: DecontextualizationReport,
        moved: Int
    ) {
        for entry in report.outcomes where entry.outcome.isRefusal {
            guard entry.sentenceIndex < grounding.verdicts.count else { continue }
            let verdict = grounding.verdicts[entry.sentenceIndex]
            print("  s\(entry.sentenceIndex) was refused as unresolvable, and grounding still returned "
                + "\"\(verdict.level.rawValue)\" for it")
            print("     scored \(percent(verdict.support.score)) against \(verdict.support.sourceID) - "
                + "a verdict a reader will read as \"checked and found wanting\" when the claim was "
                + "never interpretable")
        }
        guard moved == 0 else {
            print("  \(moved) verdict(s) moved once the claims were resolved")
            return
        }
        print("  no verdict moved: the predicate alone was enough for the scorer to reach its source "
            + "without the subject. The rewrite made a correct verdict justified, not a wrong one right.")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
