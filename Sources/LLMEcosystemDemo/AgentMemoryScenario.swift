import AgentMemoryKit
import Foundation
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The thirteenth scenario: an `AgentMemoryKit.MemoryStore` holds facts
    /// written in an earlier "session" — a pinned persona note plus a
    /// preference and a low-importance aside — and `recall(query:topK:)`
    /// ranks and retrieves the ones relevant to a fresh question. The
    /// recalled memories, not a hand-picked string, are folded into the
    /// prompt for a routed `LLMSession.send()` call, exactly the way a real
    /// agent would ground an answer in what it already knows about a user.
    /// `AgentMemoryKit` has no compile-time dependency on
    /// `ProviderGatewayKit`, matching every sibling kit's convention.
    static func runAgentMemoryScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let providerID = ProviderIdentifier.memoryHost
        do {
            let store = try await seedMemoryStore()
            let recalled = try await store.recall(query: "what editor and theme does the user prefer", topK: 2)
            print(
                "[agent memory scenario] recalled \(recalled.count) memories: "
                    + recalled.map { "[\($0.kind.rawValue)] \($0.content.prefix(40))..." }.joined(separator: "; ")
            )

            let response = try await answerFromRecalledMemory(recalled, providerID: providerID, meter: meter)
            let value = try await decoder.decode(RAGAnswer.self, from: response.text)
            print("[agent memory scenario] routed via \(response.providerID) with recalled memory \u{2192} \(value)")

            let pruned = await store.decay(pruneBelow: 0.4)
            print("[agent memory scenario] decay pass pruned \(pruned) low-importance, unpinned memories")
        } catch {
            print("[agent memory scenario] FAILED: \(error)")
        }
    }

    /// Writes three memories a host app might have persisted across earlier
    /// sessions: a pinned persona fact `decay` can never touch, a genuine
    /// preference, and a low-importance aside included specifically so the
    /// scenario's later `decay(pruneBelow:)` call has real work to do.
    private static func seedMemoryStore() async throws -> MemoryStore {
        let store = MemoryStore()
        _ = try await store.write(
            content: "The user is a senior iOS engineer building an open-source Swift LLM ecosystem.",
            kind: .fact,
            importance: 1.0,
            pinned: true
        )
        _ = try await store.write(
            content: "The user's favorite editor theme is dark with a monospace font.",
            kind: .preference,
            importance: 0.6
        )
        _ = try await store.write(
            content: "The user mentioned liking coffee once, in passing.",
            kind: .fact,
            importance: 0.1
        )
        return store
    }

    /// Folds the recalled memories' content into the prompt and routes a
    /// single call through a real `ProviderRouter`/`LLMSession`, metered
    /// exactly like every other scenario.
    private static func answerFromRecalledMemory(
        _ recalled: [MemoryRecord],
        providerID: ProviderIdentifier,
        meter: TokenMeter
    ) async throws -> LLMResponse {
        let memoryContext = recalled.map(\.content).joined(separator: "\n")
        let instructions = PromptBuilder.instructions(for: RAGAnswer.jsonSchema, typeName: "a RAGAnswer")
        let prompt = "Known facts about the user:\n\(memoryContext)\n\n\(instructions)\n"
            + "Question: What editor setup would suit this user?"

        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [memoryScenarioReply])
        ])
        let session = LLMSession(router: router)
        let response = try await session.send(prompt)
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        return response
    }

    private static var memoryScenarioReply: String {
        #"""
        {
          "answer": "A dark-themed, monospace-font editor fits this user's stated preference.",
          "sourceCount": 2
        }
        """#
    }
}
