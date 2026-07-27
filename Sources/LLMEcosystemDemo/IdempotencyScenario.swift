import Foundation
import IdempotencyKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

/// A thirteenth provider identity, used only by the idempotency scenario's routed
/// turns — registered with its own explicit rate in `EcosystemDemo.buildMeter()`
/// so the hops that really happened bill at a real rate rather than silently $0.
extension ProviderIdentifier {
    static let idempotencyHost = ProviderIdentifier("idem-host")
}

/// `IdempotencyKit`'s `EffectExecuting` seam wired to a real routed
/// `ProviderRouter`/`LLMSession` pair, so the guarded effect genuinely goes through
/// `ProviderGatewayKit` rather than into a stub.
///
/// It records a hop **only when it actually runs**, which is the whole point: a
/// replay never reaches this type, so the hop count is direct evidence that the
/// duplicate cost nothing rather than a claim that it didn't.
actor GatewayEffectExecutor: EffectExecuting {
    private let replies: [String: String]
    private let decoder: StructuredOutputDecoder
    private let providerID: ProviderIdentifier
    private var pendingFailures: [String: EffectFailure]
    private var hops: [RoutedHop] = []

    init(
        replies: [String: String],
        decoder: StructuredOutputDecoder,
        providerID: ProviderIdentifier,
        failures: [String: EffectFailure] = [:]
    ) {
        self.replies = replies
        self.decoder = decoder
        self.providerID = providerID
        self.pendingFailures = failures
    }

    func perform(_ payload: EffectPayload) async throws -> EffectResult {
        let city = payload.fields["city"] ?? "unknown"
        if let failure = pendingFailures.removeValue(forKey: city) {
            throw failure
        }
        let prompt = "File a weather alert for \(city)."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [replies[city] ?? "{}"])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        let report = try await decoder.decode(WeatherReport.self, from: response.text)
        hops.append(
            RoutedHop(
                id: city,
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            )
        )
        return EffectResult(body: "alert-\(city.lowercased())", metadata: ["conditions": report.conditions])
    }

    /// Every routed hop that actually happened, in execution order.
    func routedHops() -> [RoutedHop] {
        hops
    }
}

extension EcosystemDemo {
    /// The nineteenth scenario: `IdempotencyKit` makes a side-effecting routed call
    /// safe to retry, so the retries the rest of this toolkit performs stop being
    /// dangerous.
    ///
    /// It is the exact counterpart to the realtime-session scenario above. There, a
    /// replay after a reconnect genuinely cost a second gateway hop, because
    /// at-least-once delivery means the effect really is re-sent. Here the same
    /// duplicate is answered from the record and the provider is never reached — so
    /// three requests bill one hop, and the guard's saving is a number rather than
    /// a promise.
    static func runIdempotencyScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let executor = GatewayEffectExecutor(
            replies: [
                "Shimla": #"{"city": "Shimla", "temperatureCelsius": 8.5, "conditions": "storm"}"#,
                "Kochi": #"{"city": "Kochi", "temperatureCelsius": 31.0, "conditions": "rain"}"#
            ],
            decoder: decoder,
            providerID: .idempotencyHost,
            failures: ["Kochi": .indeterminate("gateway timeout after send")]
        )
        let recorder = InMemoryEffectEventRecorder()
        let sentry = IdempotencyGuard(retention: RetentionWindow(60), recorder: recorder)

        await retriedAlertRunsOnce(sentry: sentry, executor: executor)
        await reusedKeyIsRefused(sentry: sentry, executor: executor)
        await indeterminateAlertIsFrozenThenReconciled(sentry: sentry, executor: executor)
        await billExecutedHops(executor: executor, meter: meter)

        let stats = await sentry.statistics()
        let events = await recorder.recorded().count
        print("[idempotency scenario] executed \(stats.executed), replayed \(stats.replayed), "
            + "conflicts \(stats.conflicts), blocked \(stats.indeterminateBlocks), "
            + "resolutions \(stats.resolutions); \(events) events recorded, trail is timestamp-free")
    }

    /// The same alert filed three times — once for real, twice from the record.
    private static func retriedAlertRunsOnce(sentry: IdempotencyGuard, executor: GatewayEffectExecutor) async {
        let payload = EffectPayload(action: "file_weather_alert", fields: ["city": "Shimla", "severity": "high"])
        let key = IdempotencyKey.derived(from: payload)
        do {
            var outcomes: [String] = []
            for _ in 1...3 {
                let outcome = try await sentry.execute(key: key, payload: payload, now: 0, using: executor)
                outcomes.append(outcome.wasReplayed ? "replayed" : "executed")
            }
            let hops = await executor.routedHops().count
            print("[idempotency scenario] key \(key)")
            print("[idempotency scenario] 3 attempts -> \(outcomes.joined(separator: ", ")); "
                + "\(hops) gateway hop for 3 requests")
        } catch {
            print("[idempotency scenario] FAILED filing the Shimla alert: \(error)")
        }
    }

    /// The same key with a changed severity is a different request, and is refused
    /// rather than answered with the earlier alert.
    private static func reusedKeyIsRefused(sentry: IdempotencyGuard, executor: GatewayEffectExecutor) async {
        let original = EffectPayload(action: "file_weather_alert", fields: ["city": "Shimla", "severity": "high"])
        let altered = EffectPayload(action: "file_weather_alert", fields: ["city": "Shimla", "severity": "low"])
        do {
            _ = try await sentry.execute(
                key: .derived(from: original),
                payload: altered,
                now: 0,
                using: executor
            )
            print("[idempotency scenario] altered payload unexpectedly accepted")
        } catch let error as IdempotencyError {
            print("[idempotency scenario] same key, severity high -> low: \(error)")
        } catch {
            print("[idempotency scenario] unexpected error: \(error)")
        }
    }

    /// A timeout after the request was sent: the alert may already be filed, so the
    /// key is frozen until a reconciler says otherwise — and only then does it run.
    private static func indeterminateAlertIsFrozenThenReconciled(
        sentry: IdempotencyGuard,
        executor: GatewayEffectExecutor
    ) async {
        let payload = EffectPayload(action: "file_weather_alert", fields: ["city": "Kochi", "severity": "medium"])
        let key = IdempotencyKey.derived(from: payload)

        do {
            _ = try await sentry.execute(key: key, payload: payload, now: 1, using: executor)
        } catch let failure as EffectFailure {
            print("[idempotency scenario] Kochi attempt 1 -> failed (\(failure.mode)): \(failure.reason)")
        } catch {
            print("[idempotency scenario] Kochi attempt 1 -> unexpected error: \(error)")
        }

        do {
            _ = try await sentry.execute(key: key, payload: payload, now: 2, using: executor)
        } catch let error as IdempotencyError {
            let hops = await executor.routedHops().count
            print("[idempotency scenario] Kochi attempt 2 -> \(error) (still \(hops) hop, no duplicate filing)")
        } catch {
            print("[idempotency scenario] Kochi attempt 2 -> unexpected error: \(error)")
        }

        do {
            try await sentry.resolve(key: key, as: .notApplied, now: 3)
            let outcome = try await sentry.execute(key: key, payload: payload, now: 4, using: executor)
            let verb = outcome.wasReplayed ? "replayed" : "executed"
            print("[idempotency scenario] reconciler says it never landed -> \(verb) \(outcome.result.body)")
        } catch {
            print("[idempotency scenario] Kochi reconciliation FAILED: \(error)")
        }
    }

    /// Bills only the hops that actually reached a provider. The replays are absent
    /// from this total by construction, not by subtraction.
    private static func billExecutedHops(executor: GatewayEffectExecutor, meter: TokenMeter) async {
        let hops = await executor.routedHops()
        let prompt = hops.reduce(0) { $0 + $1.promptTokens }
        let completion = hops.reduce(0) { $0 + $1.completionTokens }
        await meter.record(
            TokenMeterKit.TokenUsage(promptTokens: prompt, completionTokens: completion),
            for: ProviderIdentifier.idempotencyHost.rawValue
        )
        let cost = await meter.cost(for: ProviderIdentifier.idempotencyHost.rawValue)
        print("[idempotency scenario] \(hops.count) executed hops billed under idem-host: "
            + "\(prompt)+\(completion) tokens, $\(cost)")
    }
}
