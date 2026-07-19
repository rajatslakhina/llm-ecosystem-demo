import Foundation
import ProviderGatewayKit
import RetryPolicyKit
import StructuredOutputKit
import TokenMeterKit

extension EcosystemDemo {
    /// The eleventh scenario: `RetryPolicyKit.RetryExecutor` wraps a routed
    /// `ProviderRouter`/`LLMSession.send()` call against a provider that
    /// genuinely fails at the transport layer for its first two attempts —
    /// not a malformed-reply repair like the third scenario, a real thrown
    /// error `ProviderRouter` has to fail over from. The *same* `LLMSession`
    /// is retried across all three attempts (not rebuilt per attempt), which
    /// is realistic: `CircuitBreaker`'s default `failureThreshold` is 3
    /// consecutive failures, so two failures followed by a success never
    /// trips it. Every attempt — including the two failures — is captured
    /// by an `InMemoryRetryEventRecorder`, and only the final, successful
    /// call is metered, matching how real LLM billing charges for completed
    /// responses, not failed ones.
    static func runRetryPolicyScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let providerID = ProviderIdentifier.retryHost
        let router = ProviderRouter(providers: [
            FlakyProvider(
                identifier: providerID,
                failingAttempts: 2,
                script: [#"{"city": "Seattle", "temperatureCelsius": 14.0, "conditions": "rain"}"#]
            )
        ])
        let session = LLMSession(router: router)
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")

        let recorder = InMemoryRetryEventRecorder()
        let executor = RetryExecutor(
            policy: ExponentialBackoffRetryPolicy(maxAttempts: 4, baseDelay: 0.01, jitter: .none),
            recorder: recorder
        )

        do {
            let outcome = try await executor.execute {
                try await session.send(instructions)
            }
            await meter.record(
                TokenUsage(promptTokens: instructions.count / 4, completionTokens: outcome.value.text.count / 4),
                for: providerID.rawValue
            )
            let value = try await decoder.decode(WeatherReport.self, from: outcome.value.text)
            print("[retry policy scenario] succeeded on attempt \(outcome.attempts): decoded \(value)")

            for event in await recorder.allEvents() {
                print(
                    "[retry policy scenario] attempt \(event.attempt) failed "
                        + "(\(event.errorDescription)) \u{2192} \(event.decision)"
                )
            }
        } catch {
            print("[retry policy scenario] FAILED: \(error)")
        }
    }
}

/// A demo-only `LLMProvider` that throws `FlakyProviderError` for its first
/// `failingAttempts` calls, then answers from `script` — unlike
/// `ScriptedProvider`, which always succeeds, this is the composition
/// `RetryPolicyKit` exists to demonstrate: a routed call that genuinely
/// fails at the transport layer and needs retrying, not a decode repair.
private struct FlakyProvider: LLMProvider {
    let identifier: ProviderIdentifier
    let capabilities: ProviderCapabilities
    private let failingAttempts: Int
    private let script: [String]
    private let callIndex = FlakyCallIndex()

    init(identifier: ProviderIdentifier, failingAttempts: Int, script: [String]) {
        self.identifier = identifier
        self.capabilities = ProviderCapabilities(
            supportsToolCalling: false,
            supportsStreaming: false,
            maxContextTokens: 32_000,
            costTier: .medium,
            locality: .network
        )
        self.failingAttempts = failingAttempts
        self.script = script
    }

    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let index = await callIndex.next()
                if index < failingAttempts {
                    continuation.finish(throwing: FlakyProviderError(attempt: index + 1))
                    return
                }
                let scriptIndex = min(index - failingAttempts, script.count - 1)
                let reply = script[scriptIndex]
                continuation.yield(.completed(LLMResponse(text: reply, finishReason: .stop, providerID: identifier)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct FlakyProviderError: Error, CustomStringConvertible {
    let attempt: Int
    var description: String { "simulated transport failure on attempt \(attempt)" }
}

/// Tiny actor backing `FlakyProvider`'s call counter, the same pattern
/// `ScriptedProvider`'s own `CallIndex` uses in `EcosystemSupport.swift`.
private actor FlakyCallIndex {
    private var value = 0
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}
