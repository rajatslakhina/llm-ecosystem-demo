import Foundation
import ProviderGatewayKit
import RetrievalKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The ninth scenario: `RetrievalKit` indexes a small knowledge base of
    /// facts about this ecosystem's own packages, retrieves the chunks most
    /// relevant to a real question, and folds the resulting context block
    /// into the prompt handed to a routed `LLMSession` — the actual RAG
    /// pattern (retrieve first, then generate), not a simulation of it.
    /// `RetrievalKit` has no compile-time dependency on `ProviderGatewayKit`
    /// (matching every sibling kit), so this integration seam is exactly
    /// what a host app would do itself: call
    /// `Retriever.retrieveContextBlock(query:)` and prepend the result to
    /// the prompt.
    static func runRetrievalScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let retriever = Retriever(embedder: HashingEmbeddingProvider())
        do {
            try await indexKnowledgeBase(retriever)
        } catch {
            print("[retrieval scenario] FAILED to index knowledge base: \(error)")
            return
        }

        let query = "How does token metering and cost work in this ecosystem?"
        do {
            let contextBlock = try await retriever.retrieveContextBlock(query: query, topK: 2)
            print("[retrieval scenario] query: \"\(query)\"")
            print("[retrieval scenario] retrieved context:\n\(contextBlock)")
            try await answerFromContext(query: query, contextBlock: contextBlock, decoder: decoder, meter: meter)
        } catch {
            print("[retrieval scenario] FAILED: \(error)")
        }
    }

    /// Indexes four short documents, one per sibling package, each written
    /// so its own key vocabulary repeats — a lexical hashing embedder needs
    /// query/document vocabulary overlap to rank correctly, the same lesson
    /// `RetrievalKit`'s own demo documents.
    private static func indexKnowledgeBase(_ retriever: Retriever) async throws {
        let documents = [
            Document(
                id: "token-meter-kit",
                text: "TokenMeterKit provides actor-based token usage and cost metering for LLM apps in Swift, "
                    + "tracking cost per provider with Decimal-based pricing and a formatted cost report."
            ),
            Document(
                id: "guardrail-kit",
                text: "GuardrailKit provides actor-based guardrails for Swift LLM apps, screening prompts and "
                    + "responses for PII redaction and content policy violations before or after routing."
            ),
            Document(
                id: "trace-kit",
                text: "TraceKit provides actor-based nested span tracing for Swift LLM apps, capturing LLM call "
                    + "and tool call spans and scoring captured traces against an EvalGate for pass fail gates."
            ),
            Document(
                id: "agent-loop-kit",
                text: "AgentLoopKit provides a host-driven ReAct agent loop for Swift LLM apps, deciding whether "
                    + "to call a tool or answer, dispatching tool calls through ToolRegistryKit for a transcript."
            )
        ]
        for document in documents {
            try await retriever.index(document)
        }
    }

    /// Routes the retrieved context through a scripted self-hosted provider
    /// call (already registered in this demo's pricing catalog) and decodes
    /// the reply as a `RAGAnswer` — metered exactly like every other
    /// scenario's routed call.
    private static func answerFromContext(
        query: String,
        contextBlock: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws {
        let providerID = ProviderIdentifier.selfHosted
        let scriptedReply = #"""
        {
          "answer": "TokenMeterKit meters usage per provider with Decimal-based pricing and a cost report.",
          "sourceCount": 2
        }
        """#
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [scriptedReply])
        ])
        let session = LLMSession(router: router)
        let augmentedPrompt = "Context:\n\(contextBlock)\n\nQuestion: \(query)\nAnswer using only the context above."

        let response = try await session.send(augmentedPrompt)
        await meter.record(
            TokenUsage(promptTokens: augmentedPrompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        let value = try await decoder.decode(RAGAnswer.self, from: response.text)
        print("[retrieval scenario] routed via \(response.providerID) \u{2192} grounded answer: \(value)")
    }
}
