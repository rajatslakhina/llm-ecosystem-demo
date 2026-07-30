import Foundation
import ProviderGatewayKit
import QuotaGovernorKit
import StructuredOutputKit
import TokenMeterKit

/// The identifier the twenty-third scenario's routed hops bill against.
/// Registered with its own explicit rate in `EcosystemDemo.buildMeter()` so these
/// hops' costs are visible rather than silently defaulting to $0 — which matters
/// more here than anywhere else, since this scenario settles its budget against
/// the figure `TokenMeter` reports.
extension ProviderIdentifier {
    static let quotaHost = ProviderIdentifier("quota-host")
}

extension EcosystemDemo {
    /// The twenty-third scenario: the loop has a budget, and the budget is real.
    ///
    /// Every earlier scenario spends whatever it needs. This one asks permission
    /// first. `QuotaGovernorKit` closes the loop the other packages leave open:
    /// `TokenMeterKit` can say what a hop cost, but only *after* it has been paid,
    /// and nothing in the toolkit could refuse the hop that comes next.
    ///
    /// The pairing is the point. `QuotaGovernor.reserve` holds an estimate before
    /// `ProviderGatewayKit` routes the turn; `TokenMeter` prices the response;
    /// `QuotaGovernor.settle` closes the reservation against that real figure. So
    /// the metered cost is not a report at the end of the run — it is the input to
    /// the next admission decision.
    ///
    /// Two runs share one tenant, and they fail differently:
    ///
    /// - `run-atlas` estimates well. Each settlement refunds the unused hold, so
    ///   the run gets more steps than a fixed reservation would have allowed, and
    ///   it still stops when the budget is genuinely gone.
    /// - `run-verbose` estimates badly: one answer runs far longer than predicted.
    ///   The overspend has already happened by the time the governor hears about
    ///   it, so the scope goes into arrears and the *next* request is refused.
    ///
    /// The tenant absorbs both and never notices, which is the nesting doing its
    /// job — a run that will not stop cannot reach past its own ceiling.
    static func runQuotaGovernorScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        do {
            let governor = QuotaGovernor(
                policy: GovernorPolicy(pricing: try HeadroomPricing(percent: 20))
            )
            let tenant = ScopeID("tenant-acme")
            let atlas = ScopeID("run-atlas")
            let verbose = ScopeID("run-verbose")
            try await governor.register(
                tenant,
                limits: try ScopeLimits(quota: try Quota(tokens: 100_000, microcents: 20_000_000))
            )
            let runCap = try ScopeLimits(quota: try Quota(tokens: 500))
            try await governor.register(atlas, under: tenant, limits: runCap)
            try await governor.register(verbose, under: tenant, limits: runCap)

            try await runBudgetedLoop(governor, tenant: tenant, run: atlas, decoder: decoder, meter: meter)
            try await runIntoArrears(governor, tenant: tenant, run: verbose, decoder: decoder, meter: meter)

            let snapshot = try await governor.snapshot(of: tenant)
            print(
                "[quota scenario] tenant-acme absorbed both runs: "
                    + "\(snapshot.remaining(on: .tokens) ?? 0) of 100000 tokens and "
                    + "\(snapshot.remaining(on: .microcents) ?? 0) of 20000000 microcents left"
            )
            let events = await governor.events()
            let refusals = events.filter { $0.kind == .refused }.count
            print("[quota scenario] audit trail: \(events.count) events, \(refusals) of them refusals")
        } catch {
            print("[quota scenario] FAILED: \(error)")
        }
    }

    /// A step budget the run cannot argue with. Eight steps are attempted; the
    /// governor decides how many actually run.
    private static func runBudgetedLoop(
        _ governor: QuotaGovernor,
        tenant: ScopeID,
        run: ScopeID,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws {
        let path = try ScopePath([tenant, run])
        let estimate = try Cost(tokens: 150, microcents: 60_000)
        var allowed = 0
        var refusal = "the loop finished on its own"
        for step in 1...8 {
            do {
                let reservation = try await governor.reserve(estimate, for: path, at: step)
                let actual = try await routeBudgetedHop(
                    "Step \(step): summarise the retention findings so far and name your sources.",
                    reply: stepReply(),
                    decoder: decoder,
                    meter: meter
                )
                let settlement = try await governor.settle(reservation.id, actual: actual, at: step)
                allowed += 1
                if step == 1 {
                    describeFirstStep(reservation, estimate: estimate, actual: actual, settlement: settlement)
                }
            } catch {
                refusal = "step \(step) refused: \(error)"
                break
            }
        }
        let snapshot = try await governor.snapshot(of: run)
        print("[quota scenario] run-atlas: \(allowed) of 8 steps ran, then \(refusal)")
        print(
            "[quota scenario] run-atlas settled \(snapshot.spent.tokens) tokens against a 500-token cap; "
                + "refunded holds are what let it get that far"
        )
    }

    /// A moderate answer of a fixed length, so the numbers below are the same on
    /// every run and can be quoted.
    private static func stepReply() -> String {
        let body = String(repeating: "retention applies to cached responses; ", count: 9)
        return "{\"answer\": \"\(body)\", \"sourceCount\": 2}"
    }

    /// The per-axis claim, shown rather than asserted: this settlement comes in
    /// *under* its hold on tokens and *over* it on money, in one request. A single
    /// signed number would have netted the two and reported neither.
    private static func describeFirstStep(
        _ reservation: Reservation,
        estimate: Cost,
        actual: Cost,
        settlement: Settlement
    ) {
        print(
            "[quota scenario] step 1 estimated \(estimate.tokens) tokens / \(estimate.microcents) "
                + "microcents, so 20% headroom held \(reservation.held.tokens) / "
                + "\(reservation.held.microcents)"
        )
        print(
            "[quota scenario] step 1 really cost \(actual.tokens) / \(actual.microcents) — under on "
                + "tokens, over on money: refunded \(settlement.refunded), overran \(settlement.overrun)"
        )
    }

    /// One badly estimated answer, and the honest consequence of it.
    private static func runIntoArrears(
        _ governor: QuotaGovernor,
        tenant: ScopeID,
        run: ScopeID,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws {
        let path = try ScopePath([tenant, run])
        let estimate = try Cost(tokens: 150, microcents: 60_000)
        let padding = String(
            repeating: "the retention window applies to cached responses and derived artefacts; ",
            count: 40
        )
        let reservation = try await governor.reserve(estimate, for: path, at: 20)
        let actual = try await routeBudgetedHop(
            "Explain the retention policy in full.",
            reply: "{\"answer\": \"\(padding)\", \"sourceCount\": 3}",
            decoder: decoder,
            meter: meter
        )
        let settlement = try await governor.settle(reservation.id, actual: actual, at: 20)
        print(
            "[quota scenario] run-verbose held \(reservation.held.tokens) tokens and spent "
                + "\(actual.tokens): overran by \(settlement.overrun.tokens), breaching "
                + "\(settlement.breached.map { "\($0)" }.joined(separator: ","))"
        )
        let snapshot = try await governor.snapshot(of: run)
        print(
            "[quota scenario] run-verbose is in arrears at \(snapshot.remaining(on: .tokens) ?? 0) tokens — "
                + "the spend already happened, so the governor can only refuse what comes next"
        )
        do {
            _ = try await governor.reserve(estimate, for: path, at: 21)
            print("[quota scenario] run-verbose was allowed another step, which it should not have been")
        } catch {
            print("[quota scenario] run-verbose asks for one more step: REFUSED: \(error)")
        }
    }

    /// One real routed hop: `ProviderGatewayKit` answers, `StructuredOutputKit`
    /// decodes, `TokenMeter` prices it, and the priced figure comes back as the
    /// `Cost` the reservation settles against.
    private static func routeBudgetedHop(
        _ prompt: String,
        reply: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws -> Cost {
        let identifier = ProviderIdentifier.quotaHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: identifier, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        _ = try await decoder.decode(RAGAnswer.self, from: response.text)
        let usage = TokenUsage(
            promptTokens: prompt.count / 4,
            completionTokens: response.text.count / 4
        )
        let before = await meter.cost(for: identifier.rawValue)
        await meter.record(usage, for: identifier.rawValue)
        let after = await meter.cost(for: identifier.rawValue)
        return try Cost(
            tokens: usage.promptTokens + usage.completionTokens,
            microcents: microcents(from: after - before)
        )
    }

    /// `TokenMeter` reports cost as a `Decimal`, which is the right type for money
    /// and the wrong type for a budget comparison that has to be exact and cheap.
    /// One microcent is 1e-8 of a dollar, so the conversion is a scale and a round,
    /// done in `Decimal` rather than through `Double` so nothing drifts on the way.
    private static func microcents(from dollars: Decimal) -> Int {
        var scaled = dollars * Decimal(100_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
