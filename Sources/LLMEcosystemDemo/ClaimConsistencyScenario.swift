import ClaimConsistencyKit
import Foundation
import GroundingKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the twenty-sixth scenario's single routed hop bills against.
extension ProviderIdentifier {
    static let consistencyHost = ProviderIdentifier("consistency-host")
}

extension EcosystemDemo {
    /// The twenty-sixth scenario: **the sentence is in the source and still disagrees with it.**
    ///
    /// This runs directly on top of the twenty-second, and the interesting result is the boundary
    /// between them rather than a clean win for either.
    ///
    /// `GroundingKit` scores lexical overlap and, above a threshold, checks two conflicts of its
    /// own: `SupportConflict.polarity` and `SupportConflict.quantity`. That is real coverage, and
    /// the first claim below shows both layers reaching the same verdict.
    ///
    /// Its quantity check compares numeric *terms as written*, which is where the second claim
    /// goes wrong: `5` against `at least 3` is two different strings and one satisfied bound, so
    /// grounding reports a contradiction that is not there. This is the expensive kind of defect —
    /// a false alarm teaches a reader to stop reading the report.
    ///
    /// Claims three and four carry no negation and no numbers at all, so nothing in an overlap
    /// score can reach them: a quantifier widened from `some` to `all`, and one member of a
    /// mutually exclusive pair swapped for the other.
    ///
    /// All of it costs **zero** extra gateway hops. The published fix for this class of error is
    /// an NLI model call per claim; every finding here comes from reading two sentences.
    static func runClaimConsistencyScenario(meter: TokenMeter) async {
        do {
            let evidence = try EvidenceSet(consistencySources)
            let answer = try await routeConsistencyTurn(evidence: evidence, meter: meter)
            let grounding = try await GroundingVerifier().verify(
                answer: answer,
                against: evidence,
                policy: .strict,
                at: 1
            )
            try await compare(grounding, evidence: evidence)
        } catch {
            print("[claim consistency scenario] FAILED: \(error)")
        }
    }

    private static var consistencySources: [SourceDocument] {
        [
            SourceDocument(
                id: SourceID("kb-cache"),
                text: "The response cache is not enabled by default for streaming requests."
            ),
            SourceDocument(
                id: SourceID("kb-retry"),
                text: "The client retries at least 3 times before failing."
            ),
            SourceDocument(
                id: SourceID("kb-scope"),
                text: "Some providers expose a token counting endpoint."
            ),
            SourceDocument(
                id: SourceID("kb-refresh"),
                text: "Background refresh is enabled on watchOS."
            )
        ]
    }

    /// One real routed turn. Every sentence cites a document that genuinely contains its subject,
    /// so retrieval and citation checking both pass and the defect survives to this point.
    private static func routeConsistencyTurn(evidence: EvidenceSet, meter: TokenMeter) async throws -> String {
        let context = evidence.documents.map { "[\($0.id)] \($0.text)" }.joined(separator: "\n")
        let prompt = "Context:\n\(context)\n\nQuestion: summarise the caching, retry, metering and refresh behaviour."
        let reply = "The response cache is enabled by default for streaming requests [kb-cache]. "
            + "The client retries 5 times before failing [kb-retry]. "
            + "All providers expose a token counting endpoint [kb-scope]. "
            + "Background refresh is disabled on watchOS [kb-refresh]."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .consistencyHost, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            ),
            for: ProviderIdentifier.consistencyHost.rawValue
        )
        print("[claim consistency scenario] routed via \(response.providerID); "
            + "4 claims, each citing a document that really is about it")
        return response.text
    }

    /// The pairs are `GroundingKit`'s own, unchanged: whatever source it matched a claim to is the
    /// source the consistency rules judge it against. Re-matching here would answer a different
    /// question than the one the pipeline actually asked.
    private static func compare(_ grounding: GroundingReport, evidence: EvidenceSet) async throws {
        let pairs: [ClaimPair] = grounding.verdicts.compactMap { verdict in
            guard let document = evidence.document(verdict.support.sourceID) else { return nil }
            return ClaimPair(
                claim: ClaimConsistencyKit.Claim(id: verdict.claim.id, text: verdict.claim.text),
                passage: SourcePassage(id: document.id.rawValue, text: document.text)
            )
        }
        let checker = try ConsistencyChecker()
        let consistency = try await checker.check(pairs, policy: .standard, at: 1)

        print("  claim  overlap-grounding      propositional-consistency")
        for (verdict, judgement) in zip(grounding.verdicts, consistency.judgements) {
            let overlap = Int((verdict.support.score * 100).rounded())
            let left = "\(verdict.level.rawValue) (\(overlap)%)"
            print("  \(verdict.claim.id)     \(left.padding(toLength: 22, withPad: " ", startingAt: 0))"
                + judgement.verdict.rawValue.uppercased())
            for contradiction in judgement.contradictions.prefix(2) {
                print("           \(contradiction.summary)")
            }
        }
        print("  grounding  -> \(grounding.decision.kind().rawValue), "
            + "\(grounding.violations.count) violation(s)")
        print("  consistency-> \(consistency.decision.kind), "
            + "naming \(consistency.decision.claims.joined(separator: ", "))")
        print("  extra gateway hops spent on the second pass: 0 - every finding is local computation")
    }
}
