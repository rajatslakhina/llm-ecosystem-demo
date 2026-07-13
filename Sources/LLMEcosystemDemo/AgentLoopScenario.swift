import AgentLoopKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit
import ToolRegistryKit

extension EcosystemDemo {
    /// The sixth and newest scenario: where `runToolCallingScenario` above
    /// hand-rolls a single tool-call round trip across two manually wired
    /// `LLMSession`s, `AgentLoopKit.AgentLoop` generalizes that into a
    /// reusable, bounded decide/act/observe loop that can chain *multiple*
    /// dependent tool calls before converging — comparing two cities
    /// requires two sequential `get_weather` calls, something the
    /// hand-rolled version above was never built to do. Metering happens
    /// entirely after the fact, straight off the returned `AgentTranscript`
    /// -- `AgentLoopKit` doesn't need to know `TokenMeterKit` exists.
    static func runAgentLoopScenario(meter: TokenMeter) async {
        let toolRegistry = await buildToolRegistry()
        let providerID = ProviderIdentifier.selfHosted

        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [
                    #"{"tool": "get_weather", "arguments": {"city": "Austin"}}"#,
                    #"{"tool": "get_weather", "arguments": {"city": "Boston"}}"#,
                    "Austin is warmer than Boston right now."
                ]
            )
        ])
        let session = LLMSession(router: router)
        let loop = AgentLoop(session: session, toolRegistry: toolRegistry, maxSteps: 4)

        do {
            let transcript = try await loop.run(initialPrompt: "Which is warmer right now, Austin or Boston?")
            for step in transcript.steps {
                await meter.record(
                    TokenUsage(promptTokens: step.prompt.count / 4, completionTokens: step.rawResponseText.count / 4),
                    for: providerID.rawValue
                )
            }
            print(
                "[AgentLoopKit orchestrated loop] \(transcript.steps.count) steps, "
                    + "halted: \(transcript.haltReason), answer: \(transcript.finalAnswer ?? "<none>")"
            )
        } catch {
            print("[AgentLoopKit orchestrated loop] FAILED: \(error)")
        }
    }
}
