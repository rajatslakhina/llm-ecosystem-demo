import ContextCompactionKit
import Foundation
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The twelfth scenario: a routed `LLMSession` conversation grows across
    /// several real turns, `ContextCompactionKit.ContextCompactor` compacts
    /// the resulting transcript before the next turn, and the compacted
    /// result — not the raw, ever-growing transcript — becomes the actual
    /// context handed to the next routed `send()` call.
    ///
    /// `LLMSession` is constructed with a deliberately huge internal
    /// `ContextBudgetManager` (100,000 tokens) so its own drop-oldest
    /// trimming never fires during this scenario — the point is to show
    /// `ContextCompactionKit` doing the real budgeting work *externally*,
    /// exactly the composition `ContextBudgetManager`'s own doc comment
    /// names explicitly ("a host app with different needs, e.g. summarizing
    /// dropped history instead of discarding it, would implement that on
    /// top of this type, not inside it"). `ContextCompactionKit` has no
    /// compile-time dependency on `ProviderGatewayKit`; bridging
    /// `LLMMessage` -> `CompactableMessage` is exactly what a host app
    /// would do itself, the same seam every sibling kit in this ecosystem
    /// uses.
    static func runContextCompactionScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let providerID = ProviderIdentifier.compactionHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: growingConversationReplies + [finalCompactedReply])
        ])
        let session = LLMSession(
            router: router,
            systemPrompt: "You are a meticulous Swift concurrency assistant. Always answer precisely.",
            budgetManager: ContextBudgetManager(maxTokens: 100_000)
        )

        do {
            try await growConversation(session: session, providerID: providerID, meter: meter)
            let bridged = try await bridgeTranscript(session: session)
            let result = try await compactTranscript(bridged)
            try await answerFromCompactedContext(
                result: result, session: session, providerID: providerID, decoder: decoder, meter: meter
            )
        } catch {
            print("[context compaction scenario] FAILED: \(error)")
        }
    }

    /// Sends each of `growingConversationTurns` through the same session, in
    /// order, so the transcript grows exactly like a real multi-turn
    /// conversation would — every hop metered like every other scenario.
    private static func growConversation(
        session: LLMSession, providerID: ProviderIdentifier, meter: TokenMeter
    ) async throws {
        for turn in growingConversationTurns {
            let response = try await session.send(turn)
            await meter.record(
                TokenUsage(promptTokens: turn.count / 4, completionTokens: response.text.count / 4),
                for: providerID.rawValue
            )
        }
    }

    /// Snapshots the session's real transcript and bridges each
    /// `ProviderGatewayKit.LLMMessage` into a `ContextCompactionKit.CompactableMessage`
    /// — the two role enums share the same case names, so mapping through
    /// `rawValue` is exactly the seam a host app would write itself.
    private static func bridgeTranscript(session: LLMSession) async throws -> [CompactableMessage] {
        let transcript = await session.currentTranscript()
        print("[context compaction scenario] transcript before: \(transcript.count) messages")
        return transcript.map { message in
            let role = CompactableRole(rawValue: message.role.rawValue) ?? .user
            return CompactableMessage(id: message.id, role: role, content: message.content)
        }
    }

    /// Runs the full three-tier pipeline with an event recorder attached and
    /// prints the real before/after numbers.
    private static func compactTranscript(_ bridged: [CompactableMessage]) async throws -> CompactionResult {
        let recorder = InMemoryCompactionEventRecorder()
        let compactor = ContextCompactor(
            strategies: [
                SlidingWindowCompactionStrategy(),
                TruncatingCompactionStrategy(),
                SummarizingCompactionStrategy(summarizer: ConcatenatingSummarizer())
            ],
            eventRecorder: recorder
        )
        let budget = CompactionBudget(maxTokens: 120, reservedForResponse: 20)
        let result = try await compactor.compact(bridged, budget: budget)

        print(
            "[context compaction scenario] compacted to: \(result.messages.count) messages, "
                + "~\(result.tokensAfter) tokens (budget: \(result.budget)), via \(result.strategiesApplied)"
        )
        if let event = await recorder.allEvents().first {
            print(
                "[context compaction scenario] recorded event: \(event.messagesBefore) \u{2192} "
                    + "\(event.messagesAfter) messages, fits budget: \(event.fitsBudget)"
            )
        }
        return result
    }

    /// The whole point of this scenario: the *compacted* messages, not the
    /// raw ever-growing transcript, become the actual context handed to the
    /// next routed `send()` call.
    private static func answerFromCompactedContext(
        result: CompactionResult,
        session: LLMSession,
        providerID: ProviderIdentifier,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws {
        let compactedContextBlock = result.messages
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n")
        let followUp = "Given everything above, what's the single most important Swift 6 concurrency rule?"
        let augmentedPrompt = "Compacted conversation so far:\n\(compactedContextBlock)\n\nQuestion: \(followUp)"

        let response = try await session.send(augmentedPrompt)
        await meter.record(
            TokenUsage(promptTokens: augmentedPrompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        let value = try await decoder.decode(RAGAnswer.self, from: response.text)
        print(
            "[context compaction scenario] routed via \(response.providerID) with compacted context "
                + "\u{2192} \(value)"
        )
    }

    /// Four real conversational turns, each answered by the matching entry
    /// in `growingConversationReplies` — long enough in aggregate (plus the
    /// system prompt) that a 100-token `CompactionBudget` genuinely can't
    /// fit them all, so the compaction below has real work to do rather
    /// than being a no-op.
    private static var growingConversationTurns: [String] {
        [
            "What's the difference between an actor and a class in Swift 6?",
            "How do I avoid data races when passing state across actors?",
            "What does the Sendable protocol actually enforce at compile time?",
            "Can a struct capture non-Sendable state safely?"
        ]
    }

    private static var growingConversationReplies: [String] {
        [
            "An actor serializes access to its mutable state through isolation; a class has no such protection "
                + "and can be mutated concurrently from multiple threads, risking data races.",
            "Keep mutable state inside a single actor and only pass Sendable values across actor boundaries — "
                + "the compiler enforces this at every call site for a type marked or inferred Sendable.",
            "Sendable marks a type safe to share across concurrency domains, either because it's a value type "
                + "with no reference semantics, or because it manages its own internal synchronization.",
            "Only if every property it captures is itself Sendable — a struct isn't automatically safe just "
                + "because it's a value type; each stored property still has to satisfy Sendable on its own."
        ]
    }

    private static var finalCompactedReply: String {
        #"""
        {
          "answer": "Keep all mutable state behind actor isolation; cross concurrency domains only with Sendable.",
          "sourceCount": 4
        }
        """#
    }
}
