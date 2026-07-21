import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The two original single-shot scenarios, split out of `EcosystemDemo.swift`
    /// into their own file so the main struct's declaration body stays under
    /// SwiftLint's `type_body_length` limit as this demo has grown a
    /// scenario call per package — the same per-scenario-file split every
    /// other package's integration already follows
    /// (`ContextCompactionScenario.swift`, `AgentMemoryScenario.swift`, etc.).
    static func runSingleShotScenarios(
        instructions: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async {
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
    }

    /// Groups a single-shot scenario's fixed setup so `runSingleShotScenario`
    /// stays under SwiftLint's parameter-count limit without hiding any of
    /// the per-scenario configuration.
    struct ScenarioRequest {
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
}
