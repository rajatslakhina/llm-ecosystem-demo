import Foundation
import ModelCascadeKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifiers the seventy-eighth scenario's three cascade tiers bill against.
extension ProviderIdentifier {
    static let cascadeSmallHost = ProviderIdentifier("cascade-small-host")
    static let cascadeMidHost = ProviderIdentifier("cascade-mid-host")
    static let cascadeFrontierHost = ProviderIdentifier("cascade-frontier-host")
}

extension EcosystemDemo {
    /// The seventy-eighth scenario: `SemanticRouterKit` (scenario 14) picks a model from the
    /// *question*. `ModelCascadeKit` picks one from the *answer*: each of four questions goes to a
    /// cheap routed tier first, and climbs to a pricier tier only when the reply's self-rated
    /// confidence is under 0.80. Each tier is its own `ProviderRouter` behind an `LLMSession`, every
    /// call made is billed through `TokenMeterKit`, and `CascadeLedger` compares the spend with
    /// sending all four questions straight to the frontier tier.
    static func runModelCascadeScenario(meter: TokenMeter) async {
        let hosts: [(ProviderIdentifier, [String])] = [
            (.cascadeSmallHost, ["Paris || 0.95", "1945 || 0.92", "maybe 6 || 0.40", "not sure || 0.30"]),
            (.cascadeMidHost, ["7 || 0.88", "Bernoulli? || 0.55"]),
            (.cascadeFrontierHost, ["Kolmogorov || 0.93"])
        ]
        let routers = Dictionary(uniqueKeysWithValues: hosts.map { identifier, script in
            (identifier.rawValue, ProviderRouter(providers: [ScriptedProvider(identifier: identifier, script: script)]))
        })
        let questions = [
            "What is the capital of France? One word.",
            "In what year did the Second World War end?",
            "How many primes are below 18?",
            "Who axiomatised probability theory in 1933?"
        ]
        let typical = TokenUsage(promptTokens: questions[0].count / 4, completionTokens: 4)
        var tiers: [CascadeTier] = []
        for (identifier, _) in hosts {
            let pricing = rates.first { $0.0 == identifier }?.1
            let estimate = pricing.map { NSDecimalNumber(decimal: $0.cost(for: typical)).doubleValue } ?? 0
            tiers.append(CascadeTier(id: identifier.rawValue, modelID: identifier.rawValue, estimatedCost: estimate))
        }
        do {
            let cascade = try CascadeExecutor(tiers: tiers, rule: ConfidenceFloor(0.80))
            let ledger = CascadeLedger(tiers: tiers)
            for (index, question) in questions.enumerated() {
                let outcome = try await cascade.run { tier in
                    try await askTier(tier, question: question, routers: routers, meter: meter)
                }
                await ledger.record(outcome)
                let path = outcome.steps.map { step in
                    if case .accepted = step.kind { return "\(step.tierID) accepted" }
                    return "\(step.tierID) deferred"
                }.joined(separator: " -> ")
                print("[model cascade scenario] q\(index + 1): \"\(outcome.answer?.text ?? "-")\" via " +
                    "\(outcome.answeredBy?.id ?? "nobody") (\(path))")
            }
            let report = await ledger.report()
            let saved = report.savingsFraction.map { Int(($0 * 100).rounded()) } ?? 0
            print("   frontier called \(report.tiers[2].calls)/\(report.requests) times; cascade spend is " +
                "\(saved)% below frontier-only; small-tier escalation yield " +
                "\(Int(((report.tiers[0].escalationYield ?? 0) * 100).rounded()))%")
        } catch {
            print("[model cascade scenario] FAILED: \(error)")
        }
    }

    /// Sends `question` to `tier`'s router, bills the call, and splits the reply's
    /// `"answer || confidence"` self-rating into a `TierAnswer`.
    private static func askTier(
        _ tier: CascadeTier, question: String, routers: [String: ProviderRouter], meter: TokenMeter
    ) async throws -> TierAnswer {
        guard let router = routers[tier.id] else { throw RouterError.noProvidersRegistered }
        let response = try await LLMSession(router: router).send(question)
        let usage = TokenUsage(promptTokens: question.count / 4, completionTokens: response.text.count / 4)
        await meter.record(usage, for: response.providerID.rawValue)
        let parts = response.text.components(separatedBy: " || ")
        let pricing = rates.first { $0.0.rawValue == tier.id }?.1
        let cost = pricing.map { NSDecimalNumber(decimal: $0.cost(for: usage)).doubleValue } ?? 0
        return TierAnswer(text: parts[0], confidence: parts.count > 1 ? Double(parts[1]) : nil, cost: cost)
    }
}
