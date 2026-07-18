import Foundation
import ProviderGatewayKit
import PromptTemplateKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The tenth scenario: `PromptTemplateKit.PromptRegistry` versions the
    /// same context+question system prompt the retrieval scenario answers
    /// by hand — a v1 template with `{{context}}`/`{{question}}`
    /// placeholders, promoted to a more explicit v2 wording that becomes
    /// active immediately. The active version is rendered (strict mode)
    /// into real prompt text, and only that *rendered string* — never the
    /// raw template — is handed to a real routed
    /// `ProviderRouter`/`LLMSession.send()` call, metered by `TokenMeterKit`
    /// exactly like every other scenario: `PromptTemplateKit` renders,
    /// `ProviderGatewayKit` sends. A rollback to v1 and a lenient-mode
    /// render (with `question` omitted) round out the walk past the
    /// trivial register/render path, and every registry action is captured
    /// by an `InMemoryPromptAuditRecorder`.
    static func runPromptTemplateScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let auditRecorder = InMemoryPromptAuditRecorder()
        let registry = PromptRegistry(auditRecorder: auditRecorder)
        let templateName = "rag-system-prompt"

        do {
            try await registerAndPromote(registry: registry, name: templateName)
            try await renderAndRoute(registry: registry, name: templateName, decoder: decoder, meter: meter)
            try await rollbackAndRenderLeniently(registry: registry, name: templateName)

            let history = try await registry.history(name: templateName)
            let events = await auditRecorder.allEvents()
            let kinds = events.map { $0.kind.rawValue }.joined(separator: ", ")
            print(
                "[prompt template scenario] \(history.count) version(s) in history, "
                    + "\(events.count) audit events: \(kinds)"
            )
        } catch {
            print("[prompt template scenario] FAILED: \(error)")
        }
    }

    /// Registers the v1 wording, then promotes a v2 that becomes active
    /// immediately — two real `PromptRegistry` calls, not simulated ones.
    private static func registerAndPromote(registry: PromptRegistry, name: String) async throws {
        try await registry.register(
            name: name,
            template: "Answer the question using only the context below.\n"
                + "Context: {{context}}\nQuestion: {{question}}"
        )
        try await registry.promote(
            name: name,
            template: "You are a grounded assistant. Using ONLY the context provided, answer concisely and "
                + "do not rely on anything outside it.\nContext:\n{{context}}\nQuestion: {{question}}"
        )
    }

    /// Renders the active (v2) template in strict mode and routes only the
    /// rendered string through a real `LLMSession` — the composition this
    /// scenario exists to demonstrate. Uses
    /// `ProviderIdentifier.promptTemplateHost`, a provider identity
    /// registered with its own explicit rate in `buildMeter()` so this
    /// hop's cost is visible rather than silently defaulting to $0.
    private static func renderAndRoute(
        registry: PromptRegistry,
        name: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws {
        let variables = [
            "context": "TokenMeterKit meters usage per provider with Decimal-based pricing and a cost report.",
            "question": "How is cost tracked across providers?"
        ]
        let renderedPrompt = try await registry.render(name: name, variables: variables, mode: .strict)
        print("[prompt template scenario] rendered v2 (strict):\n\(renderedPrompt)")

        let providerID = ProviderIdentifier.promptTemplateHost
        let scriptedReply = #"""
        {
          "answer": "TokenMeterKit meters usage per provider with Decimal-based pricing and a cost report.",
          "sourceCount": 1
        }
        """#
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [scriptedReply])
        ])
        let session = LLMSession(router: router)
        let response = try await session.send(renderedPrompt)
        await meter.record(
            TokenUsage(promptTokens: renderedPrompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        let value = try await decoder.decode(RAGAnswer.self, from: response.text)
        print("[prompt template scenario] routed via \(response.providerID) \u{2192} decoded: \(value)")
    }

    /// Rolls back to v1 and renders it in lenient mode with `question`
    /// omitted — the unresolved placeholder is left as literal text rather
    /// than throwing, exercising the second `PromptRenderMode` this
    /// scenario is required to demonstrate.
    private static func rollbackAndRenderLeniently(registry: PromptRegistry, name: String) async throws {
        let rolledBack = try await registry.rollbackToPrevious(name: name)
        print("[prompt template scenario] rolled back to v\(rolledBack.id)")

        let lenientPrompt = try await registry.render(
            name: name,
            variables: ["context": "TokenMeterKit meters usage per provider with Decimal-based pricing."],
            mode: .lenient
        )
        print("[prompt template scenario] rendered v\(rolledBack.id) (lenient, question omitted):\n\(lenientPrompt)")
    }
}
