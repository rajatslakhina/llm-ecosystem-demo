import CompactionPlannerKit
import ContextCompactionKit
import Foundation
import PromptCacheKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the seventy-first scenario bills its measurement against.
extension ProviderIdentifier {
    static let compactionPlannerHost = ProviderIdentifier("compaction-planner-host")
}

extension EcosystemDemo {
    /// The seventy-first scenario: scenario 70 found compacting in batches 2.11x cheaper than sliding
    /// the window every turn, and said itself that the comparison was not like for like, because the
    /// batch schedule also kept less history. `CompactionPlannerKit` holds the history fixed and asks
    /// again, prices what lies between the two, then runs three schedules through the real
    /// `ContextCompactor` and prices them with `PromptCacheKit`'s simulator, a second and independent
    /// model of the same cache, to see whether the two models agree.
    static func runCompactionPlannerScenario(meter: TokenMeter) async {
        print("[compaction planner scenario] scenario 70 compared schedules that kept different amounts"
            + " of history. Held equal, which is cheaper?")
        let contents = (1...20).map { "Tool result \($0): " + String(repeating: "order-line ", count: 163) }
        let estimator = CharacterCountTokenEstimator()
        let tokens = contents.map { estimator.estimatedTokenCount(for: $0) }
        let baselines = plannerBaselines()

        if let trace = plannerTrace(tokens), let grid = plannerGrid(), baselines.count == 2 {
            let planner = CompactionPlanner(terms: .explicitFiveMinute)
            await compactionLikeForLike(planner, trace, grid, baselines)
            if let halfway = await compactionBetween(planner, trace, grid, baselines) {
                let schedules = [baselines[0], ("halfway pick", halfway), baselines[1]]
                await compactionExecute(contents: contents, schedules: schedules, planner: planner, trace: trace)
            }
            await compactionAfterAPause(tokens: tokens, grid: grid, batch: baselines[1].1)
        } else {
            print("  planner inputs rejected")
        }

        await meter.record(
            TokenUsage(promptTokens: 420, completionTokens: 150),
            for: ProviderIdentifier.compactionPlannerHost.rawValue
        )
    }

    /// Scenario 70's 1,200 tokens of house rules plus six 260-token tool schemas.
    private static let plannerStablePrefix = 2_760
    /// Scenario 70's 5,000-token budget counts its 1,200-token system message, which the compactor
    /// pins, so the history itself gets 3,800. Its batch target of 3,200 leaves 2,000 of history.
    private static let plannerHistoryBudget = 3_800

    private static func plannerTrace(_ tokens: [Int], pauseBeforeTurn pause: Int? = nil) -> ConversationTrace? {
        let turns = tokens.enumerated().map { index, count in
            let late = pause.map { index + 1 >= $0 ? 400.0 : 0 } ?? 0
            return TurnArrival(tokens: count, time: Double(index + 1) * 20 + late)
        }
        return try? ConversationTrace(stablePrefixTokens: plannerStablePrefix, turns: turns)
    }

    private static func plannerGrid() -> PlanningGrid? {
        try? PlanningGrid(budget: plannerHistoryBudget, floor: 900, step: 100)
    }

    private static func plannerBaselines() -> [(String, CompactionPolicy)] {
        let slide = try? CompactionPolicy.slidingWindow(budget: plannerHistoryBudget)
        let batch = try? CompactionPolicy(trigger: plannerHistoryBudget, target: 2_000)
        return [("slide the window every turn", slide), ("compact in batches, to 2,000", batch)]
            .compactMap { label, policy in policy.map { (label, $0) } }
    }

    private static func dollars(_ value: Double) -> String {
        "$" + String(format: "%.6f", value)
    }

    // MARK: - A: the like-for-like question

    private static func compactionLikeForLike(
        _ planner: CompactionPlanner,
        _ trace: ConversationTrace,
        _ grid: PlanningGrid,
        _ baselines: [(String, CompactionPolicy)]
    ) async {
        print("  A. scenario 70's two schedules as history budgets, each against the cheapest of"
            + " \(grid.policies().count) schedules keeping at least as much")
        for (label, baseline) in baselines {
            guard let comparison = await planner.likeForLike(trace, grid: grid, baseline: baseline) else { continue }
            let base = comparison.baseline
            let saved = String(format: "%.2f", comparison.savedFraction * 100)
            let verdict = comparison.match == base
                ? "nothing cheaper keeps as much"
                : "\(comparison.match.policy) keeps as much for \(saved)% less"
            print("     \(label.padding(toLength: 29, withPad: " ", startingAt: 0))\(base.policy): "
                + "\(base.compactions) compactions, keeps \(Int(base.meanHistoryTokens.rounded())),"
                + " \(dollars(base.totalUSD)) -> \(verdict)")
        }
    }

    // MARK: - B: what the history between them costs

    private static func compactionBetween(
        _ planner: CompactionPlanner,
        _ trace: ConversationTrace,
        _ grid: PlanningGrid,
        _ baselines: [(String, CompactionPolicy)]
    ) async -> CompactionPolicy? {
        let slide = await planner.evaluate(baselines[0].1, on: trace)
        let batch = await planner.evaluate(baselines[1].1, on: trace)
        let lessKept = 1 - batch.meanHistoryTokens / slide.meanHistoryTokens
        print("  B. so scenario 70's 2.11x is a trade, not a free saving: the batch schedule keeps"
            + " \(String(format: "%.2f", lessKept * 100))% less history. What lies between:")
        let between = await planner.frontier(trace, grid: grid).filter {
            $0.meanHistoryTokens > batch.meanHistoryTokens && $0.meanHistoryTokens < slide.meanHistoryTokens
        }
        for point in between {
            print("     keeps \(Int(point.meanHistoryTokens.rounded()))   \(dollars(point.totalUSD))"
                + "   \(point.compactions) compactions   \(point.policy)")
        }
        let halfway = (slide.meanHistoryTokens + batch.meanHistoryTokens) / 2
        let outcome = await planner.recommend(trace, grid: grid, minimumMeanHistoryTokens: halfway)
        guard case let .recommended(pick) = outcome else {
            print("     no schedule keeps \(Int(halfway.rounded())) inside the budget")
            return nil
        }
        print("     keep at least \(Int(halfway.rounded())) (halfway) -> \(pick.policy),"
            + " \(dollars(pick.totalUSD))")
        return pick.policy
    }

    // MARK: - C: run it for real, priced by the other model

    private static func compactionExecute(
        contents: [String],
        schedules: [(String, CompactionPolicy)],
        planner: CompactionPlanner,
        trace: ConversationTrace
    ) async {
        print("  C. the three through the real ContextCompactor, priced by both cache models"
            + " (PromptCacheKit's simulator plans its own breakpoints and tiers)")
        var simulated: [Double] = []
        var replayed: [Double] = []
        for (label, policy) in schedules {
            let run = await compactionLiveRun(policy: policy, contents: contents)
            let replay = await planner.evaluate(policy, on: trace)
            simulated.append(run.spend)
            replayed.append(replay.totalUSD)
            print("     \(label.padding(toLength: 29, withPad: " ", startingAt: 0))" + run.line
                + "   replay \(dollars(replay.totalUSD))")
        }
        let sameOrder = simulated.indices.sorted { simulated[$0] < simulated[$1] }
            == replayed.indices.sorted { replayed[$0] < replayed[$1] }
        print("     the two models rank the three the same way: \(sameOrder ? "yes" : "no")")
    }

    private static let plannerStableSegments: [PromptSegment] = {
        let rules = PromptSegment(
            id: "rules", content: String(repeating: "house rule. ", count: 400), volatility: .frozen, tokens: 1_200
        )
        let tools = ["create_ticket", "lookup_order", "refund", "search_docs", "send_email", "update_address"]
            .map { PromptSegment(id: "tool:\($0)", content: "schema for \($0)", volatility: .frozen, tokens: 260) }
        return [rules] + tools
    }()

    private static func compactionLiveRun(
        policy: CompactionPolicy,
        contents: [String]
    ) async -> (line: String, spend: Double) {
        let estimator = CharacterCountTokenEstimator()
        let compactor = ContextCompactor(strategies: [SlidingWindowCompactionStrategy()])
        let scheduler = CompactionScheduler(policy: policy, terms: .explicitFiveMinute)
        let session = CachingSession(
            strategy: .planned, policy: .explicitTwoTier, pricing: CachePricing(inputUSDPerMillionTokens: 3)
        )
        var messages: [CompactableMessage] = []
        var names: [UUID: String] = [:]
        var historySent = 0
        var compactions = 0
        for (index, content) in contents.enumerated() {
            let message = CompactableMessage(role: .tool, content: content)
            names[message.id] = "turn:\(index + 1)"
            messages.append(message)
            let size = messages.reduce(0) { $0 + estimator.estimatedTokenCount(for: $1.content) }
            let time = Double(index + 1) * 20
            if case let .compact(target, _) = await scheduler.decide(historyTokens: size, at: time),
               let result = try? await compactor.compact(messages, budget: CompactionBudget(maxTokens: target)) {
                messages = result.messages
                compactions += 1
            }
            let history = messages.map { message in
                PromptSegment(
                    id: names[message.id] ?? "unknown", content: message.content, volatility: .turn,
                    tokens: estimator.estimatedTokenCount(for: message.content)
                )
            }
            historySent += history.reduce(0) { $0 + $1.tokens }
            let query = PromptSegment(id: "query", content: "message \(index + 1)", volatility: .ephemeral, tokens: 60)
            let forecast = WorkloadForecast(requestsPerMinute: 3, remainingRequests: contents.count - index - 1)
            _ = await session.send(
                AssembledPrompt(segments: plannerStableSegments + history + [query]), forecast: forecast, at: time
            )
        }
        let summary = await session.summary()
        let line = "compactions \(String(format: "%2d", compactions))   keeps \(historySent / contents.count)"
            + "   hit \(String(format: "%.2f", summary.hitRate * 100))%   simulated \(dollars(summary.actualUSD))"
        return (line, summary.actualUSD)
    }

    // MARK: - D: a pause the cache does not survive

    private static func compactionAfterAPause(tokens: [Int], grid: PlanningGrid, batch: CompactionPolicy) async {
        print("  D. the same conversation with a 400-second pause before turn 11, longer than the"
            + " five-minute cache")
        guard let trace = plannerTrace(tokens, pauseBeforeTurn: 11) else { return }
        let planner = CompactionPlanner(terms: .explicitFiveMinute)
        guard let comparison = await planner.likeForLike(trace, grid: grid, baseline: batch) else { return }
        let base = comparison.baseline
        let match = comparison.match
        print("     batch baseline \(base.policy): \(base.compactions) compactions, keeps"
            + " \(Int(base.meanHistoryTokens.rounded())), \(dollars(base.totalUSD))")
        print("     cheapest keeping as much: \(match.policy), \(match.compactions) compactions"
            + " (\(match.coldCompactions) on the lapsed cache), keeps \(Int(match.meanHistoryTokens.rounded())),"
            + " \(dollars(match.totalUSD)), \(String(format: "%.2f", comparison.savedFraction * 100))% less")
    }
}
