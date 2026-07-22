import Foundation
import ProviderGatewayKit
import SemanticRouterKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The fourteenth scenario: a `SemanticRouterKit.SemanticRouter`
    /// classifies an incoming user message into one of several support
    /// intents by embedding distance, then the matched route's `metadata` —
    /// not a hard-coded branch — selects which model the real routed
    /// `LLMSession.send()` call targets. This is semantic routing (by
    /// meaning) feeding provider routing (by capability): `SemanticRouterKit`
    /// decides *what the user wants*, `ProviderGatewayKit` decides *which
    /// backend serves it*, `StructuredOutputKit` decodes the reply, and
    /// `TokenMeter` meters the hop. `SemanticRouterKit` has no compile-time
    /// dependency on `ProviderGatewayKit`; the two join only at the metadata
    /// seam, matching every sibling kit's convention.
    static func runSemanticRouterScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        do {
            let router = try await buildIntentRouter()
            let userMessage = "what is the weather like in Denver right now"
            guard let match = try await router.route(userMessage) else {
                print("[semantic router scenario] no intent matched — would fall back to a general handler")
                return
            }
            let model = match.route.metadata["model"] ?? ProviderIdentifier.routerHost.rawValue
            print(
                "[semantic router scenario] \"\(userMessage.prefix(38))...\" \u{2192} intent '\(match.routeName)' "
                    + "(score \(String(format: "%.3f", match.score))), routing to model \(model)"
            )

            let response = try await answerRoutedIntent(userMessage, meter: meter)
            let value = try await decoder.decode(WeatherReport.self, from: response.text)
            print("[semantic router scenario] routed via \(response.providerID), decoded: \(value)")
        } catch {
            print("[semantic router scenario] FAILED: \(error)")
        }
    }

    /// Registers three support intents, each mapped to the model a match
    /// should route to. Uses the deterministic offline `HashingRouteEmbedder`
    /// (the default) so this scenario's routing is reproducible run to run;
    /// the seed utterances share vocabulary with the demo query, since a
    /// bag-of-words embedder matches on shared words rather than deep meaning.
    private static func buildIntentRouter() async throws -> SemanticRouter {
        let router = SemanticRouter(defaultThreshold: 0.2)
        try await router.register(Route(
            name: "weather",
            utterances: [
                "what is the weather like today",
                "is it going to rain in the city",
                "current temperature and conditions outside"
            ],
            metadata: ["model": ProviderIdentifier.routerHost.rawValue]
        ))
        try await router.register(Route(
            name: "order_status",
            utterances: [
                "where is my package it has not arrived",
                "track my order and shipping status"
            ],
            metadata: ["model": "orders-host"]
        ))
        try await router.register(Route(
            name: "small_talk",
            utterances: ["hello how are you", "thanks so much for the help"],
            metadata: ["model": "chat-lite"],
            scoreThreshold: 0.5
        ))
        return router
    }

    /// Routes the actual answer through a real `ProviderRouter`/`LLMSession`
    /// for the `.routerHost` model the matched intent pointed at, metered
    /// exactly like every other scenario.
    private static func answerRoutedIntent(_ query: String, meter: TokenMeter) async throws -> LLMResponse {
        let providerID = ProviderIdentifier.routerHost
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")
        let prompt = "\(instructions)\nUser asked: \(query)"
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [#"{"city": "Denver", "temperatureCelsius": 21.5, "conditions": "clear"}"#]
            )
        ])
        let session = LLMSession(router: router)
        let response = try await session.send(prompt)
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        return response
    }
}
