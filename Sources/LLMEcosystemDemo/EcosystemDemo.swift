import AgentLoopKit
import ContextCompactionKit
import Foundation
import GuardrailKit
import ProviderGatewayKit
import ResponseCacheKit
import RetrievalKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit
import TraceKit

@main
struct EcosystemDemo {
    static func main() async {
        print("== LLM Ecosystem Integration Demo ==")
        print(
            "ProviderGatewayKit (routing) + StructuredOutputKit (decoding) + TokenMeterKit (cost) + "
                + "ResponseCacheKit (caching) + ToolRegistryKit (tool dispatch) + AgentLoopKit (agent loop) + "
                + "GuardrailKit (PII redaction & policy) + TraceKit (tracing & eval gates) + "
                + "RetrievalKit (retrieval-augmented context) + PromptTemplateKit (prompt templating & rollback) + "
                + "RetryPolicyKit (rate limiting & retry policy) + "
                + "ContextCompactionKit (conversation compaction under a token budget)\n"
        )

        let meter = await buildMeter()
        let decoder = StructuredOutputDecoder()
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")

        await runSingleShotScenario(
            ScenarioRequest(
                label: "on-device provider, clean JSON",
                providerID: .onDevice,
                script: [#"{"city": "Bengaluru", "temperatureCelsius": 27.5, "conditions": "cloudy"}"#]
            ),
            instructions: instructions,
            decoder: decoder,
            meter: meter
        )

        await runSingleShotScenario(
            ScenarioRequest(
                label: "cloud provider, JSON fenced in prose",
                providerID: .cloud,
                script: [
                    "Here is the current report:\n```json\n" +
                        #"{"city": "Mumbai", "temperatureCelsius": 31.0, "conditions": "storm"}"# +
                        "\n```\nLet me know if you need more detail."
                ]
            ),
            instructions: instructions,
            decoder: decoder,
            meter: meter
        )

        await runSelfRepairingScenario(instructions: instructions, decoder: decoder, meter: meter)
        await runCachedScenario(instructions: instructions, decoder: decoder, meter: meter)
        await runToolCallingScenario(decoder: decoder, meter: meter)
        await runAgentLoopScenario(meter: meter)
        await runGuardrailScenario(decoder: decoder, meter: meter)
        await runTraceScenario(decoder: decoder, meter: meter)
        await runRetrievalScenario(decoder: decoder, meter: meter)
        await runPromptTemplateScenario(decoder: decoder, meter: meter)
        await runRetryPolicyScenario(decoder: decoder, meter: meter)
        await runContextCompactionScenario(decoder: decoder, meter: meter)

        print()
        let report = await meter.report()
        print(report.formatted())
        print("Total metered cost across all twelve scenarios: $\(await meter.totalCost())")
    }

    /// Registers illustrative rates for the three routed providers this demo
    /// uses — TokenMeterKit ships a small default catalog (real model names
    /// like "gpt-4o"), but a host app routes against whatever identifiers
    /// its own providers use, so registering your own rates against those
    /// identifiers is the expected integration pattern rather than a
    /// workaround.
    private static func buildMeter() async -> TokenMeter {
        let registry = PricingRegistry()
        let rates: [(ProviderIdentifier, ModelPricing)] = [
            (.onDevice, ModelPricing(inputPerMillion: 0, outputPerMillion: 0)),
            (.cloud, ModelPricing(inputPerMillion: 3, outputPerMillion: 15)),
            (.selfHosted, ModelPricing(inputPerMillion: 1, outputPerMillion: 4)),
            (.promptTemplateHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.retryHost, ModelPricing(inputPerMillion: 1.5, outputPerMillion: 6)),
            (.compactionHost, ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10))
        ]
        for (identifier, pricing) in rates {
            await registry.register(pricing, for: identifier.rawValue)
        }
        return TokenMeter(registry: registry)
    }

    /// Groups a single-shot scenario's fixed setup so `runSingleShotScenario`
    /// stays under SwiftLint's parameter-count limit without hiding any of
    /// the per-scenario configuration.
    private struct ScenarioRequest {
        let label: String
        let providerID: ProviderIdentifier
        let script: [String]
    }

    /// Routes one call through a real `ProviderRouter`/`LLMSession`, meters
    /// it with `TokenMeter`, and decodes the reply with
    /// `StructuredOutputDecoder` — the three packages' real code, wired
    /// together exactly as a host app would.
    private static func runSingleShotScenario(
        _ scenario: ScenarioRequest,
        instructions: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async {
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: scenario.providerID, script: scenario.script)
        ])
        let session = LLMSession(router: router)
        do {
            let response = try await session.send(instructions)
            await meter.record(
                TokenUsage(promptTokens: instructions.count / 4, completionTokens: response.text.count / 4),
                for: scenario.providerID.rawValue
            )
            let value = try await decoder.decode(WeatherReport.self, from: response.text)
            print("[\(scenario.label)] routed via \(response.providerID) \u{2192} decoded: \(value)")
        } catch {
            print("[\(scenario.label)] FAILED: \(error)")
        }
    }

    /// The self-hosted provider's first answer omits a required field;
    /// `StructuredOutputDecoder`'s retry loop re-invokes the same routed
    /// `LLMSession` with the previous error folded into the follow-up
    /// prompt, and the second routed call repairs it. Every hop — both the
    /// failed and the successful one — is metered.
    private static func runSelfRepairingScenario(
        instructions: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async {
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: .selfHosted,
                script: [
                    #"{"city": "Chennai", "temperatureCelsius": 33.2}"#,
                    #"{"city": "Chennai", "temperatureCelsius": 33.2, "conditions": "clear"}"#
                ]
            )
        ])
        let session = LLMSession(router: router)
        do {
            let value = try await decoder.decode(WeatherReport.self, maxAttempts: 2) { _, previousError in
                let response: LLMResponse
                if let previousError {
                    response = try await session.send(
                        "Your last answer was invalid: \(previousError). "
                            + "Please answer again, matching the shape exactly."
                    )
                } else {
                    response = try await session.send(instructions)
                }
                await meter.record(
                    TokenUsage(promptTokens: 24, completionTokens: response.text.count / 4),
                    for: "self-hosted"
                )
                return response.text
            }
            print("[self-hosted provider, self-repairing] decoded after a repair round-trip: \(value)")
        } catch {
            print("[self-hosted provider, self-repairing] FAILED: \(error)")
        }
    }

    /// Sits a `ResponseCache` in front of the same routed pipeline and asks
    /// the identical question twice. The first call is a real MISS — routed
    /// through `ProviderRouter`/`LLMSession` and metered with `TokenMeter`
    /// exactly like the scenarios above. The second call never reaches the
    /// router at all: `ResponseCache` answers from its own storage, and the
    /// cost that would have been re-paid is credited to `estimatedSavings`
    /// instead of a second `TokenMeter` recording.
    private static func runCachedScenario(
        instructions: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async {
        let cache = ResponseCache(capacity: 50, defaultTTL: 300)
        // Routed through the cloud provider rather than on-device: the
        // registered on-device rate is $0, which would make a HIT's
        // estimatedSavings credit invisible. Cloud pricing makes the
        // saved cost of the second, cache-answered call actually show up.
        let providerID = ProviderIdentifier.cloud
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [#"{"city": "Pune", "temperatureCelsius": 24.0, "conditions": "clear"}"#]
            )
        ])
        let session = LLMSession(router: router)
        let request = CacheableRequest(modelID: providerID.rawValue, prompt: instructions)

        for attempt in 1...2 {
            if await cache.response(for: request) != nil {
                print("[cached scenario] attempt \(attempt): HIT — no provider call, no additional cost")
                continue
            }
            do {
                let response = try await session.send(instructions)
                await meter.record(
                    TokenUsage(promptTokens: instructions.count / 4, completionTokens: response.text.count / 4),
                    for: providerID.rawValue
                )
                let cost = await meter.cost(for: providerID.rawValue)
                await cache.store(
                    CachedResponse(text: response.text, providerID: response.providerID.rawValue),
                    for: request,
                    estimatedCost: cost
                )
                let value = try await decoder.decode(WeatherReport.self, from: response.text)
                print(
                    "[cached scenario] attempt \(attempt): MISS — routed via \(response.providerID), "
                        + "decoded: \(value)"
                )
            } catch {
                print("[cached scenario] attempt \(attempt): FAILED: \(error)")
            }
        }

        print(await cache.statistics().formatted())
    }

    /// Builds a `ToolRegistryKit.ToolRegistry` with one registered tool —
    /// a weather lookup whose arguments are schema-validated before this
    /// handler ever runs. Qualified as `ToolRegistryKit.ToolRegistry`
    /// throughout this file because `ProviderGatewayKit` also exports its
    /// own, more minimal `ToolRegistry`/`ToolCallRequest` types.
    static func buildToolRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        let weatherParameters = JSONSchema.object(
            properties: ["city": .string(description: "City name")],
            required: ["city"]
        )
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "get_weather",
                description: "Look up current weather for a city.",
                parameters: weatherParameters
            ),
            handler: ClosureToolHandler { arguments in
                guard case .object(let fields) = arguments, case .string(let city) = fields["city"] ?? .null else {
                    return .object(["error": .string("missing city")])
                }
                return .object(["city": .string(city), "conditions": .string("Clear"), "tempF": .number(68)])
            }
        )
        return registry
    }

    /// The full tool-calling round trip: a routed turn "decides" to call a
    /// tool, `ToolRegistryKit` validates and dispatches it, and the tool's
    /// result is fed back into a second routed turn for the model's final,
    /// schema-validated answer. Every hop is metered, exactly like the
    /// scenarios above.
    private static func runToolCallingScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let toolRegistry = await buildToolRegistry()
        let providerID = ProviderIdentifier.cloud

        let decisionScript = #"{"tool": "get_weather", "arguments": {"city": "Denver"}}"#
        let decisionRouter = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [decisionScript])
        ])
        let decisionSession = LLMSession(router: decisionRouter)

        do {
            let decisionPrompt = "What's the weather in Denver? Call the get_weather tool if you need to."
            let decisionResponse = try await decisionSession.send(decisionPrompt)
            await meter.record(
                TokenUsage(promptTokens: decisionPrompt.count / 4, completionTokens: decisionResponse.text.count / 4),
                for: providerID.rawValue
            )

            let scriptedCall = try JSONDecoder().decode(ScriptedToolCall.self, from: Data(decisionResponse.text.utf8))
            let argumentsData = try JSONEncoder().encode(scriptedCall.arguments)

            let dispatchResult = await toolRegistry.dispatch(
                ToolRegistryKit.ToolCallRequest(id: "call-1", toolName: scriptedCall.tool, argumentsJSON: argumentsData)
            )

            guard case .success(let toolOutput) = dispatchResult.outcome else {
                print("[tool-calling round trip] FAILED: tool dispatch did not succeed: \(dispatchResult.outcome)")
                return
            }
            let toolOutputJSON = String(data: try JSONEncoder().encode(toolOutput), encoding: .utf8) ?? "{}"

            let finalInstructions = PromptBuilder.instructions(
                for: ToolBackedAnswer.jsonSchema,
                typeName: "a ToolBackedAnswer"
            )
            let finalPrompt = "Tool '\(scriptedCall.tool)' returned: \(toolOutputJSON). \(finalInstructions)"
            let finalRouter = ProviderRouter(providers: [
                ScriptedProvider(identifier: providerID, script: [toolOutputJSON])
            ])
            let finalSession = LLMSession(router: finalRouter)
            let finalResponse = try await finalSession.send(finalPrompt)
            await meter.record(
                TokenUsage(promptTokens: finalPrompt.count / 4, completionTokens: finalResponse.text.count / 4),
                for: providerID.rawValue
            )

            let finalValue = try await decoder.decode(ToolBackedAnswer.self, from: finalResponse.text)
            print("[tool-calling round trip] dispatched \"\(scriptedCall.tool)\", final answer: \(finalValue)")

            let stats = await toolRegistry.statisticsSnapshot
            print(
                "ToolRegistry stats: totalCalls=\(stats.totalCalls) "
                    + "success=\(stats.successCount) failures=\(stats.failureCount)"
            )
        } catch {
            print("[tool-calling round trip] FAILED: \(error)")
        }
    }
}
