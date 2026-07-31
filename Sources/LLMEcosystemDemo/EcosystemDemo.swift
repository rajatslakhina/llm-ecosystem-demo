import AgentLoopKit
import AgentMemoryKit
import BatchInferenceKit
import ContextCompactionKit
import Foundation
import GroundingKit
import GuardrailKit
import IdempotencyKit
import OutputRepairKit
import ProviderGatewayKit
import QuotaGovernorKit
import RealtimeSessionKit
import ResponseCacheKit
import RetrievalKit
import SchemaMigrationKit
import SemanticRouterKit
import StreamAggregatorKit
import StructuredOutputKit
import TokenMeterKit
import ToolAuthorityKit
import ToolRegistryKit
import TraceKit

@main
struct EcosystemDemo {
    static func main() async {
        printBanner()

        let meter = await buildMeter()
        let decoder = StructuredOutputDecoder()
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")

        await runSingleShotScenarios(instructions: instructions, decoder: decoder, meter: meter)
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
        await runAgentMemoryScenario(decoder: decoder, meter: meter)
        await runSemanticRouterScenario(decoder: decoder, meter: meter)
        await runOutputRepairScenario(decoder: decoder, meter: meter)
        await runStreamAggregatorScenario(meter: meter)
        await runBatchInferenceScenario(decoder: decoder, meter: meter)
        await runRealtimeSessionScenario(decoder: decoder, meter: meter)
        await runIdempotencyScenario(decoder: decoder, meter: meter)
        await runSchemaMigrationScenario(decoder: decoder, meter: meter)
        await runToolAuthorityScenario(meter: meter)
        await runGroundingScenario(decoder: decoder, meter: meter)
        await runQuotaGovernorScenario(decoder: decoder, meter: meter)
        await runCostEstimatorScenario(decoder: decoder, meter: meter)
        await runWorkloadProfilerScenario(meter: meter)

        print()
        let report = await meter.report()
        print(report.formatted())
        print("Total metered cost across all twenty-five scenarios: $\(await meter.totalCost())")
    }

    /// The banner, lifted out of `main()` so that function stays inside
    /// SwiftLint's 50-line body limit as scenarios keep being added.
    private static func printBanner() {
            print("== LLM Ecosystem Integration Demo ==")
            print(
                "ProviderGatewayKit (routing) + StructuredOutputKit (decoding) + TokenMeterKit (cost) + "
                    + "ResponseCacheKit (caching) + ToolRegistryKit (tool dispatch) + AgentLoopKit (agent loop) + "
                    + "GuardrailKit (PII redaction & policy) + TraceKit (tracing & eval gates) + "
                    + "RetrievalKit (retrieval-augmented context) + PromptTemplateKit (prompt templating & rollback) + "
                    + "RetryPolicyKit (rate limiting & retry policy) + "
                    + "ContextCompactionKit (conversation compaction under a token budget) + "
                    + "AgentMemoryKit (long-term write/recall memory across sessions) + "
                    + "SemanticRouterKit (semantic intent routing by embedding distance) + "
                    + "OutputRepairKit (bounded self-healing structured-output repair loop) + "
                    + "StreamAggregatorKit (streamed delta + tool-call fragment reassembly) + "
                    + "BatchInferenceKit (bounded-concurrency batch fan-out with per-item failure isolation) + "
                    + "RealtimeSessionKit (a realtime session that survives a reconnect: at-least-once "
                    + "outbox, strict inbound ordering, two-layer dedup) + "
                    + "IdempotencyKit (at-most-once side effects under at-least-once delivery) + "
                    + "SchemaMigrationKit (versioned contracts: migrate a payload across schema versions, "
                    + "validated at every hop) + "
                    + "ToolAuthorityKit (deny-by-default authority for agent tool calls: capability scoping, "
                    + "a provenance ceiling, and approvals bound to one exact call) + "
                    + "GroundingKit (claim-level grounding and citation verification: a verdict per sentence "
                    + "with the source span that proves it) + "
                    + "QuotaGovernorKit (hierarchical reserve/settle budget governance: hold an estimate "
                    + "before the hop, settle it against the metered cost, refuse the next one) + "
                    + "CostEstimatorKit (where that estimate comes from: forecast a loop's cost before it "
                    + "runs from transcript growth, tools, cache and retries, then reconcile against the "
                    + "metered actual) + "
                    + "WorkloadProfilerKit (and where that plan comes from: derive it from runs that "
                    + "already happened, then gate the hand-written one against what the runs did)\n"
            )
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
            (.compactionHost, ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10)),
            (.memoryHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.routerHost, ModelPricing(inputPerMillion: 1.8, outputPerMillion: 7)),
            (.repairHost, ModelPricing(inputPerMillion: 2.2, outputPerMillion: 9)),
            (.streamHost, ModelPricing(inputPerMillion: 1.6, outputPerMillion: 6.5)),
            (.batchHost, ModelPricing(inputPerMillion: 2.6, outputPerMillion: 10.5)),
            (.realtimeHost, ModelPricing(inputPerMillion: 1.9, outputPerMillion: 7.5)),
            (.idempotencyHost, ModelPricing(inputPerMillion: 2.4, outputPerMillion: 9.5)),
            (.schemaHost, ModelPricing(inputPerMillion: 2.1, outputPerMillion: 8.5)),
            (.authorityHost, ModelPricing(inputPerMillion: 2.3, outputPerMillion: 9.2)),
            (.groundingHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.quotaHost, ModelPricing(inputPerMillion: 2.4, outputPerMillion: 9.6)),
            (.estimatorHost, ModelPricing(inputPerMillion: 2.8, outputPerMillion: 11.2)),
            (.profilerHost, ModelPricing(inputPerMillion: 2.8, outputPerMillion: 11.2))
        ]
        for (identifier, pricing) in rates {
            await registry.register(pricing, for: identifier.rawValue)
        }
        return TokenMeter(registry: registry)
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
