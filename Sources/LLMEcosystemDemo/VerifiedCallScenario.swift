import Foundation
import IdempotencyKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit
import VerifiedCallKit

/// The identifier the eighty-first scenario's routed agent turns bill against.
extension ProviderIdentifier {
    static let verifiedCallHost = ProviderIdentifier("verified-call-host")
}

private struct ScriptedPaymentCall: Decodable {
    let tool: String
    let arguments: [String: String]
}

/// A payments backend with one non-atomic failure: the first POST for an invoice commits, then its
/// response is lost. Its read replica shows a payment one second after the commit.
actor PaymentsBackend {
    private var committedAt: [String: Duration] = [:]
    private var payments: [String: Int] = [:]
    private var faulted: Set<String>
    private let clock: ManualVerificationClock
    private(set) var lookups: [String] = []

    init(timeoutAfterCommit invoices: Set<String>, clock: ManualVerificationClock) {
        faulted = invoices
        self.clock = clock
    }

    func pay(invoice: String) async throws -> String {
        payments[invoice, default: 0] += 1
        if committedAt[invoice] == nil { committedAt[invoice] = await clock.now() }
        if faulted.remove(invoice) != nil { throw URLError(.timedOut) }
        return "rcpt-\(invoice)"
    }

    func lookup(invoice: String) async -> ProbeReading<String> {
        let now = await clock.now()
        let parts = now.components
        let stamp = "t=\(Double(parts.seconds) + Double(parts.attoseconds) / 1e18)s"
        guard let at = committedAt[invoice], now - at >= .seconds(1) else {
            lookups.append("\(stamp) absent")
            return .absent
        }
        lookups.append("\(stamp) found rcpt-\(invoice)")
        return .applied("rcpt-\(invoice)")
    }

    func paymentCount(_ invoice: String) -> Int { payments[invoice, default: 0] }
}

/// `IdempotencyKit`'s executor seam, with the payment run through `VerifiedCaller`, so an in-doubt
/// POST is settled by a lookup instead of being reported to the guard as indeterminate.
actor VerifiedPaymentExecutor: EffectExecuting {
    private let backend: PaymentsBackend
    private let caller: VerifiedCaller
    private(set) var verdicts: [String] = []

    init(backend: PaymentsBackend, caller: VerifiedCaller) {
        self.backend = backend
        self.caller = caller
    }

    func perform(_ payload: EffectPayload) async throws -> EffectResult {
        let invoice = payload.fields["invoice"] ?? "?"
        let backend = backend
        let outcome = await caller.execute(ClosureEffect<String>(
            key: invoice,
            perform: { _ in try await backend.pay(invoice: invoice) },
            probe: { _ in await backend.lookup(invoice: invoice) }
        ))
        verdicts = outcome.attempts.map(\.verdict.description)
        switch outcome.resolution {
        case .succeeded(let receipt), .recovered(let receipt):
            return EffectResult(body: receipt, metadata: ["resolution": outcome.resolution.label])
        case .failed(let reason):
            throw EffectFailure(reason: reason, mode: .notApplied)
        case .unconfirmed, .unresolved:
            throw EffectFailure.indeterminate(outcome.resolution.reason ?? "unknown")
        }
    }
}

/// The guard on its own: a thrown POST is all it can see, so it records the payment as indeterminate.
struct PlainPaymentExecutor: EffectExecuting {
    let backend: PaymentsBackend

    func perform(_ payload: EffectPayload) async throws -> EffectResult {
        EffectResult(body: try await backend.pay(invoice: payload.fields["invoice"] ?? "?"))
    }
}

extension EcosystemDemo {
    /// The eighty-first scenario: `IdempotencyKit` (scenario 19) freezes a key when an effect fails
    /// in doubt, and scenario 19's own reconciler was a hand-written `resolve(.notApplied)`.
    /// `VerifiedCallKit` is that reconciler. An agent's `pay_invoice` call goes through
    /// `ToolRegistryKit` into an `IdempotencyGuard` whose executor runs the payment under a
    /// `VerifiedCaller`. The backend commits and then times out; the replica lags one second, so
    /// the settle window reads "absent" twice before it finds the payment. The receipt is recovered,
    /// the guard records it, and the agent's re-sent call is replayed instead of paying again.
    static func runVerifiedCallScenario(meter: TokenMeter) async {
        let providerID = ProviderIdentifier.verifiedCallHost
        let call = #"{"tool": "pay_invoice", "arguments": {"invoice": "INV-311", "cents": "18000"}}"#
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [call, call, "Paid INV-311 ($180.00), receipt rcpt-INV-311."]
            )
        ])
        let clock = ManualVerificationClock()
        let backend = PaymentsBackend(timeoutAfterCommit: ["INV-311"], clock: clock)
        let executor = VerifiedPaymentExecutor(backend: backend, caller: paymentCaller(clock: clock))
        let sentry = IdempotencyGuard(retention: RetentionWindow(60), recorder: InMemoryEffectEventRecorder())
        let registry = await paymentRegistry(sentry: sentry, executor: executor)
        var transcript = "Pay invoice INV-311 for $180.00."
        print("[verified call scenario] backend: the first POST for INV-311 commits, then times out; "
            + "its replica shows payments 1.0s late")
        do {
            for turn in 1...3 {
                let response = try await LLMSession(router: router).send(transcript)
                await meter.record(
                    TokenUsage(promptTokens: transcript.count / 4, completionTokens: response.text.count / 4),
                    for: providerID.rawValue
                )
                let decoded = try? JSONDecoder().decode(ScriptedPaymentCall.self, from: Data(response.text.utf8))
                guard let call = decoded else {
                    print("   turn \(turn) answer: \(response.text)")
                    break
                }
                let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
                    id: "p\(turn)", toolName: call.tool, argumentsJSON: try JSONEncoder().encode(call.arguments)
                ))
                let text = paymentResultText(result.outcome)
                print("   turn \(turn) \(call.tool)(invoice: INV-311, cents: 18000) -> \(text)")
                if turn == 1 {
                    print("      verifier: \(await executor.verdicts.joined(separator: "; "))")
                    print("      lookups: \(await backend.lookups.joined(separator: ", "))")
                }
                transcript += "\n\nTool \(call.tool) returned: \(text)"
            }
            await printPaymentControls(verifiedCharges: await backend.paymentCount("INV-311"))
            let stats = await sentry.statistics()
            print("   guard: executed \(stats.executed), replayed \(stats.replayed), "
                + "indeterminate blocks \(stats.indeterminateBlocks)")
        } catch {
            print("[verified call scenario] FAILED: \(error)")
        }
    }

    /// A 2-second settle window, probed every 500ms; only a malformed response is a rejection.
    private static func paymentCaller(clock: ManualVerificationClock) -> VerifiedCaller {
        let window = VisibilityWindow(settle: .seconds(2), interval: .milliseconds(500), maxProbes: 8)
        return VerifiedCaller(
            policy: VerificationPolicy(window: window),
            classifier: FailureClassifier { ($0 as? URLError)?.code == .badServerResponse ? .rejected : .inDoubt },
            clock: clock
        )
    }

    private static func paymentRegistry(
        sentry: IdempotencyGuard,
        executor: VerifiedPaymentExecutor
    ) async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        let schema = JSONSchema.object(
            properties: ["invoice": .string(description: "invoice id"), "cents": .string(description: "amount")],
            required: ["invoice", "cents"]
        )
        await registry.register(
            ToolRegistryKit.ToolDefinition(name: "pay_invoice", description: "Pays an invoice.", parameters: schema),
            handler: ClosureToolHandler { _ in
                let payload = EffectPayload(action: "pay_invoice", fields: ["invoice": "INV-311", "cents": "18000"])
                let outcome = try await sentry.execute(
                    key: IdempotencyKey("pay:INV-311"), payload: payload, using: executor
                )
                return .object([
                    "receipt": .string(outcome.result.body),
                    "guard": .string(outcome.wasReplayed ? "replayed" : "executed"),
                    "verifier": .string(outcome.result.metadata["resolution"] ?? "-")
                ])
            }
        )
        return registry
    }

    private static func paymentResultText(_ outcome: ToolCallOutcome) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch outcome {
        case .success(let value):
            return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        case .failure(let error):
            return "error: \(error)"
        }
    }

    /// The same fault against a plain retry, and against the guard with no verifier behind it.
    private static func printPaymentControls(verifiedCharges: Int) async {
        let clock = ManualVerificationClock()
        let retried = PaymentsBackend(timeoutAfterCommit: ["INV-311"], clock: clock)
        // A plain retry loop: send, and on any error send once more.
        if (try? await retried.pay(invoice: "INV-311")) == nil {
            _ = try? await retried.pay(invoice: "INV-311")
        }
        let alone = PaymentsBackend(timeoutAfterCommit: ["INV-311"], clock: clock)
        let sentry = IdempotencyGuard(retention: RetentionWindow(60), recorder: InMemoryEffectEventRecorder())
        let payload = EffectPayload(action: "pay_invoice", fields: ["invoice": "INV-311", "cents": "18000"])
        var refusal = "-"
        for _ in 1...2 {
            do {
                _ = try await sentry.execute(key: IdempotencyKey("pay:INV-311"), payload: payload,
                                             using: PlainPaymentExecutor(backend: alone))
            } catch let error as IdempotencyError {
                refusal = "\(error)"
            } catch {
                continue
            }
        }
        print("   charges for INV-311: plain retry \(await retried.paymentCount("INV-311")), "
            + "guard alone \(await alone.paymentCount("INV-311")), guard + verifier \(verifiedCharges)")
        print("   guard alone, re-sent call: \(refusal)")
    }
}
