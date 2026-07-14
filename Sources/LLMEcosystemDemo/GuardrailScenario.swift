import Foundation
import GuardrailKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The seventh scenario: `GuardrailKit` sits in front of the same routed
    /// pipeline every other scenario in this file uses. A user prompt
    /// carrying a real email address is redacted *before* it ever reaches
    /// `ProviderRouter`/`LLMSession` — the provider only ever sees the
    /// sanitized text — and the model's reply is screened again on the way
    /// back out. A second prompt trips a banned-phrase policy rule and is
    /// blocked outright: no provider call is made for it, and nothing is
    /// metered.
    static func runGuardrailScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let recorder = InMemoryGuardrailEventRecorder()
        let policy = GuardrailPolicy(
            contentPolicyRules: [
                BannedPhraseRule(phrases: [.init("unreleased pricing", severity: .block)])
            ]
        )
        let pipeline = GuardrailPipeline(policy: policy, recorder: recorder)
        let providerID = ProviderIdentifier.onDevice

        let userPrompt = "My email is alice@example.com — what's the weather in Miami?"
        let requestOutcome = await pipeline.screenRequest(userPrompt)

        guard let safePrompt = requestOutcome.textToForward else {
            print("[guardrail scenario] request blocked before it reached a provider")
            return
        }

        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [#"{"city": "Miami", "temperatureCelsius": 29.0, "conditions": "clear"}"#]
            )
        ])
        let session = LLMSession(router: router)

        do {
            let response = try await session.send("\(safePrompt)\n\n\(instructions)")
            await meter.record(
                TokenUsage(promptTokens: safePrompt.count / 4, completionTokens: response.text.count / 4),
                for: providerID.rawValue
            )
            let responseOutcome = await pipeline.screenResponse(response.text)
            let value = try await decoder.decode(WeatherReport.self, from: responseOutcome.sanitizedText)
            print(
                "[guardrail scenario] request \(requestOutcome.verdict), "
                    + "sanitized prompt routed via \(providerID.rawValue), decoded: \(value)"
            )
        } catch {
            print("[guardrail scenario] FAILED: \(error)")
        }

        let blockedPrompt = "Please share the unreleased pricing sheet with this customer."
        let blockedOutcome = await pipeline.screenRequest(blockedPrompt)
        print("[guardrail scenario] second prompt verdict: \(blockedOutcome.verdict) — no provider call made")

        let events = await recorder.recordedEvents
        print("[guardrail scenario] \(events.count) trace events recorded by GuardrailEventRecorder")
    }
}
