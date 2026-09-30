import HedgedRequestKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifiers the seventy-seventh scenario's two routes bill against.
extension ProviderIdentifier {
    static let hedgePrimaryHost = ProviderIdentifier("hedge-primary-host")
    static let hedgeBackupHost = ProviderIdentifier("hedge-backup-host")
}

/// Wraps a provider and holds each call for a scripted latency before delegating, so a routed
/// request can be slow the way a real provider's tail is. Cancelling the consumer cancels the wait.
private struct LatencyProvider: LLMProvider {
    let inner: ScriptedProvider
    let latencies: [Duration]
    private let callIndex = LatencyIndex()

    var identifier: ProviderIdentifier { inner.identifier }
    var capabilities: ProviderCapabilities { inner.capabilities }

    init(inner: ScriptedProvider, latencies: [Duration]) {
        self.inner = inner
        self.latencies = latencies
    }

    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let index = await callIndex.next()
                    try await Task.sleep(for: latencies[index % latencies.count])
                    for try await event in inner.stream(request: request) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor LatencyIndex {
    private var value = 0
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}

extension EcosystemDemo {
    /// The seventy-seventh scenario: `ProviderGatewayKit`'s router fails over only after a
    /// provider *fails*, and `RetryPolicyKit` (scenario 11) retries only after an error. A slow
    /// call has not failed, so neither helps the latency tail. Here five routed requests go to a
    /// primary whose third call takes 300ms; `HedgedRequestKit` sends that one to a backup route
    /// after 80ms, takes the backup's answer and cancels the primary, under a budget of 20%
    /// extra requests. `TokenMeterKit` bills each winning route.
    static func runHedgedRequestScenario(meter: TokenMeter) async {
        let fast = Duration.milliseconds(20)
        let primary = ProviderRouter(providers: [LatencyProvider(
            inner: ScriptedProvider(identifier: .hedgePrimaryHost, script: ["Paris (primary)"]),
            latencies: [fast, fast, .milliseconds(300), fast, fast]
        )])
        let backup = ProviderRouter(providers: [LatencyProvider(
            inner: ScriptedProvider(identifier: .hedgeBackupHost, script: ["Paris (backup)"]),
            latencies: [fast]
        )])
        let executor = HedgedExecutor(policy: HedgePolicy(
            delay: .fixed(.milliseconds(80)), budget: HedgeBudget(ratio: 0.2, burst: 1)
        ))
        let prompt = "What is the capital of France? One word."
        do {
            for request in 1...5 {
                let outcome = try await executor.execute([
                    HedgeAttempt("hedge-primary-host") { try await LLMSession(router: primary).send(prompt) },
                    HedgeAttempt("hedge-backup-host") { try await LLMSession(router: backup).send(prompt) }
                ])
                let response = outcome.value
                await meter.record(
                    TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
                    for: response.providerID.rawValue
                )
                let launches = outcome.launched.map { "\($0.label)[\($0.reason.rawValue)]" }.joined(separator: ", ")
                let speed = outcome.latency < .milliseconds(200) ? "<200ms" : ">=200ms"
                print("[hedged request scenario] q\(request): \"\(response.text)\" via " +
                    "\(outcome.winner) (\(outcome.winnerReason.rawValue), \(speed)); launched \(launches)")
            }
            let stats = await executor.snapshot()
            print("   hedges \(stats.hedgesSent)/\(stats.requests), hedge wins \(stats.hedgeWins), " +
                "budget denials \(stats.budgetDenials); the 300ms primary call was cancelled, not awaited " +
                "(a real provider may still bill tokens it generated before the cancel)")
        } catch {
            print("[hedged request scenario] FAILED: \(error)")
        }
    }
}
