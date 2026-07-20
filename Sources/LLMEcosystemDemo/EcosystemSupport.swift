import Foundation
import ProviderGatewayKit
import StructuredOutputKit

/// The response shape every routed call in this demo asks a model to
/// answer in — shared across scenarios so the story stays focused on how
/// the packages compose, not on the schema itself.
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

/// The shape a tool call is asked to answer in once its result is fed back
/// for a final routed turn — shared with `WeatherReport`'s spirit but kept
/// separate since a tool-calling round trip's final answer is a distinct
/// step from the single-shot scenarios above.
struct ToolBackedAnswer: Decodable, Equatable, JSONSchemaConvertible {
    let city: String
    let conditions: String
    let tempF: Double

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "city": .string(description: "The city the report is for"),
                "conditions": .string(description: "Current conditions"),
                "tempF": .number(description: "Current temperature in Fahrenheit")
            ],
            required: ["city", "conditions", "tempF"]
        )
    }
}

/// The scripted "model decided to call a tool" reply, decoded so the demo
/// can build a real `ToolRegistryKit.ToolCallRequest` from it.
struct ScriptedToolCall: Decodable {
    let tool: String
    let arguments: [String: String]
}

/// A fourth provider identity, used only by the prompt-template scenario's
/// routed call. `ProviderIdentifier` is an extensible struct rather than a
/// closed enum (see `foundation-model-provider-gateway`'s own `.onDevice`/
/// `.cloud`/`.selfHosted` statics), so declaring a new one here is the same
/// pattern the upstream package itself uses — registered with its own
/// explicit rate in `EcosystemDemo.buildMeter()` so this hop's cost is
/// visible rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let promptTemplateHost = ProviderIdentifier("prompt-host")
}

/// A fifth provider identity, used only by the retry-policy scenario's
/// flaky provider — registered with its own explicit rate in
/// `EcosystemDemo.buildMeter()` so the successful, retried hop's cost is
/// visible rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let retryHost = ProviderIdentifier("retry-host")
}

/// A sixth provider identity, used only by the context-compaction
/// scenario's growing-conversation routed calls — registered with its own
/// explicit rate in `EcosystemDemo.buildMeter()` so every hop of the
/// growing conversation (and the final, compacted-context hop) shows up in
/// the cost report rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let compactionHost = ProviderIdentifier("compaction-host")
}

/// The response shape the retrieval scenario's routed call is asked to
/// answer in — a plain question-answering shape rather than `WeatherReport`,
/// since that scenario asks the model to ground its answer in retrieved
/// context rather than report on the weather. Reused as-is by the
/// prompt-template scenario, whose rendered prompt asks the same
/// context+question question-answering shape.
struct RAGAnswer: Decodable, Equatable, JSONSchemaConvertible {
    let answer: String
    let sourceCount: Int

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "answer": .string(description: "The answer, grounded only in the provided context"),
                "sourceCount": .number(description: "How many retrieved context chunks were used")
            ],
            required: ["answer", "sourceCount"]
        )
    }
}
