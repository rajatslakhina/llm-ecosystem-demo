import Foundation
import GroundingKit
import ProviderGatewayKit
import RetrievalKit
import StructuredOutputKit
import TokenMeterKit

/// The identifier the twenty-second scenario's single routed hop bills against.
/// Registered with its own explicit rate in `EcosystemDemo.buildMeter()` so this
/// hop's cost is visible rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let groundingHost = ProviderIdentifier("grounding-host")
}

extension EcosystemDemo {
    /// The twenty-second scenario: the answer is **well-formed and wrong**.
    ///
    /// `RetrievalKit` really indexes and retrieves the passages.
    /// `ProviderGatewayKit` routes a real turn. `StructuredOutputKit` decodes the
    /// reply and **accepts it** — every required field is present and correctly
    /// typed, because a hallucination is not a schema violation.
    ///
    /// `GroundingKit` is the only layer in this pipeline positioned to ask the
    /// remaining question: is each sentence actually in the passages we supplied,
    /// and does the document it names actually say so? It answers three different
    /// ways for the three sentences, which is the whole point — one verdict for
    /// the answer would have hidden all of it:
    ///
    /// - a sentence that is grounded and correctly cited,
    /// - a sentence that inflates a number the source does not carry
    ///   (`contradicted`, not merely unsupported — the source says otherwise),
    /// - a sentence citing a document that was never retrieved at all.
    ///
    /// Under `.strip` the grounded remainder is published and the rest is named.
    /// This costs **one** gateway hop: verification is local computation, so
    /// catching the hallucination is free — unlike `OutputRepairKit`, which pays
    /// a second hop to ask the model to try again.
    static func runGroundingScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let retriever = Retriever(embedder: HashingEmbeddingProvider())
        do {
            try await indexPricingKnowledgeBase(retriever)
            let chunks = try await retriever.retrieve(query: "cost metering retention limits", topK: 3)
            let evidence = try EvidenceSet(chunks.map {
                SourceDocument(id: SourceID($0.chunk.documentID), text: $0.chunk.text)
            })
            print("[grounding scenario] retrieved \(chunks.count) passages: "
                + evidence.identifiers().map(\.rawValue).joined(separator: ", "))

            let answer = try await routeGroundedTurn(evidence: evidence, decoder: decoder, meter: meter)
            try await checkAnswer(answer, against: evidence)
        } catch {
            print("[grounding scenario] FAILED: \(error)")
        }
    }

    /// Three short passages, deliberately overlapping in vocabulary with the
    /// answer below so the hashing embedder ranks them correctly — the same
    /// lesson the retrieval scenario documents.
    private static func indexPricingKnowledgeBase(_ retriever: Retriever) async throws {
        let documents = [
            Document(
                id: "kb-metering",
                text: "TokenMeterKit records token usage per provider and reports cost with Decimal pricing."
            ),
            Document(
                id: "kb-retention",
                text: "Cached responses are retained for 30 days before the cost record is discarded."
            ),
            Document(
                id: "kb-limits",
                text: "The metering export limit is 500 records per request."
            )
        ]
        for document in documents {
            try await retriever.index(document)
        }
    }

    /// One real routed turn. The reply decodes cleanly as a `RAGAnswer` — which
    /// is exactly the trap: schema validation passing is not evidence that the
    /// prose inside the validated field is true.
    private static func routeGroundedTurn(
        evidence: EvidenceSet,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws -> String {
        let context = evidence.documents
            .map { "[\($0.id)] \($0.text)" }
            .joined(separator: "\n")
        let prompt = "Context:\n\(context)\n\nQuestion: what are the metering limits? Cite every claim."
        let reply = #"""
        {
          "answer": "Cached responses are retained for 30 days [kb-retention]. \#
        The metering export limit is 5000 records per request [kb-limits]. \#
        Enterprise plans raise that limit on request [kb-enterprise].",
          "sourceCount": 3
        }
        """#
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .groundingHost, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            ),
            for: ProviderIdentifier.groundingHost.rawValue
        )
        let decoded = try await decoder.decode(RAGAnswer.self, from: response.text)
        print("[grounding scenario] routed via \(response.providerID); "
            + "StructuredOutputKit ACCEPTED the reply (sourceCount \(decoded.sourceCount)) "
            + "- the shape is valid, which says nothing about the content")
        return decoded.answer
    }

    private static func checkAnswer(_ answer: String, against evidence: EvidenceSet) async throws {
        let verifier = GroundingVerifier()
        let report = try await verifier.verify(
            answer: answer,
            against: evidence,
            policy: .strict,
            at: 1
        )
        for verdict in report.verdicts {
            let cited = verdict.claim.citations.map(\.rawValue).joined(separator: ",")
            let percent = Int((verdict.support.score * 100).rounded())
            print("  \(verdict.claim.id) \(verdict.level.rawValue) "
                + "(\(percent)% vs \(verdict.support.sourceID)) "
                + "cites \(cited.isEmpty ? "nothing" : cited)")
            if let conflict = verdict.support.conflict, verdict.level == .contradicted {
                print("      conflict \(conflict); source says \"\(verdict.evidence()?.text ?? "")\"")
            }
            for issue in verdict.citationIssues {
                print("      \(issue)")
            }
        }
        print("  strict -> \(report.decision.kind().rawValue), "
            + "\(report.violations.count) violation(s); unused \(report.unusedSources.count)")

        let stripped = try await verifier.verify(
            answer: answer,
            against: evidence,
            policy: .stripping,
            at: 2
        )
        if case .revised(let text, let removed) = stripped.decision {
            print("  strip  -> removed \(removed.joined(separator: ",")): \"\(text)\"")
        }
        print("  extra gateway hops spent catching this: 0 - verification is local computation")
    }
}
