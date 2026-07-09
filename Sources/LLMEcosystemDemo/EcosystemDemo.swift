import Foundation
import ProviderGatewayKit
import ResponseCacheKit
import StructuredOutputKit
import TokenMeterKit

/// The response shape every routed call in this demo asks a model to
/// answer in — shared across all three scenarios below so the story stays
/// focused on how the packages compose, not on the schema itself.
struct WeatherReport: Decodable, Equatable, JSONSchemaConvertible {
    let city: String
    let temperatureCelsius: Double
    let conditions: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "city": .string(description: "The city the report is for"),
                "temperatureCelsius": .number(description: "Current temperature in Celsius"),
                "conditions": .string(enumValues: ["clear", "cloudy", "rain", "storm"])
            ],
            required: ["city", "temperatureCelsius", "conditions"]
        )
    }
}

/// A demo-only conformer to ProviderGatewayKit's real `LLMProvider`
/// protocol: it answers from a fixed script indexed by call count instead
/// of calling out to a live network or on-device runtime. This mirrors the
/// same pattern `ProviderGatewayKit` itself uses for its own
/// `SimulatedCloudProvider`/`SimulatedOnDeviceProvider` — a real,
/// protocol-conforming provider with scripted rather than live output —
/// so this demo exercises the actual `ProviderRouter` → `LLMSession`
/// pipeline instead of hand-waving it.
struct ScriptedProvider: LLMProvider {
    let identifier: ProviderIdentifier
    let capabilities: ProviderCapabilities
    private let script: [String]
    private let callIndex = CallIndex()

    init(identifier: ProviderIdentifier, script: [String]) {
        self.identifier = identifier
        self.capabilities = ProviderCapabilities(
            supportsToolCalling: false,
            supportsStreaming: false,
            maxContextTokens: 32_000,
            costTier: .medium,
            locality: .network
        )
        self.script = script
    }

    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let index = await callIndex.next()
                let reply = script[min(index, script.count - 1)]
                continuation.yield(.completed(LLMResponse(text: reply, finishReason: .stop, providerID: identifier)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Tiny actor backing `ScriptedProvider`'s call counter — a struct is
/// `Sendable`, but the mutable index it closes over needs its own
/// isolation, exactly as `ProviderGatewayKit`'s own simulated providers do.
private actor CallIndex {
    private var value = 0
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}

@main
struct EcosystemDemo {
    static func main() async {
        print("== LLM Ecosystem Integration Demo ==")
        print("ProviderGatewayKit (routing) + StructuredOutputKit (decoding) + TokenMeterKit (cost)\n")

        // Register illustrative rates for the three routed providers this
        // demo uses — TokenMeterKit ships a small default catalog (real
        // model names like "gpt-4o"), but a host app routes against
        // whatever identifiers its own providers use, so registering your
        // own rates against those identifiers is the expected integration
        // pattern rather than a workaround.
        let registry = PricingRegistry()
        await registry.register(
            ModelPricing(inputPerMillion: 0, outputPerMillion: 0), for: ProviderIdentifier.onDevice.rawValue
        )
        await registry.register(
            ModelPricing(inputPerMillion: 3, outputPerMillion: 15), for: ProviderIdentifier.cloud.rawValue
        )
        await registry.register(
            ModelPricing(inputPerMillion: 1, outputPerMillion: 4), for: ProviderIdentifier.selfHosted.rawValue
        )

        let meter = TokenMeter(registry: registry)
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

        print()
        let report = await meter.report()
        print(report.formatted())
        print("Total metered cost across all three routed calls: $\(await meter.totalCost())")
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
}
