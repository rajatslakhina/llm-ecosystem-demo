import ContextCompactionKit
import Foundation
import PromptCacheKit
import ProviderGatewayKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the seventieth scenario bills its measurement against.
extension ProviderIdentifier {
    static let promptCacheHost = ProviderIdentifier("prompt-cache-host")
}

extension EcosystemDemo {
    /// The seventieth scenario: every earlier scenario that talks to a model resends the same
    /// prompt each turn (the tools from `ToolRegistryKit`, the rules, and a history that
    /// `ContextCompactionKit` keeps under budget) and pays full price for the part a provider
    /// could have served from its cache. Whether it can depends on layout, and on one interaction
    /// between two earlier packages that neither could see: compaction rewrites the history, and a
    /// rewritten history is a broken prefix.
    static func runPromptCacheScenario(meter: TokenMeter) async {
        print("[prompt cache scenario] the same prompt is resent every turn. What decides whether the cache pays?")

        await promptCacheToolBlock()
        await promptCacheCompactionCost()

        await meter.record(
            TokenUsage(promptTokens: 380, completionTokens: 140),
            for: ProviderIdentifier.promptCacheHost.rawValue
        )
    }

    private static let cacheToolNames = [
        "update_address", "create_ticket", "search_docs", "refund", "send_email", "lookup_order"
    ]

    // MARK: - A: the tool block

    private static func promptCacheRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        for name in cacheToolNames {
            await registry.register(
                ToolRegistryKit.ToolDefinition(
                    name: name,
                    description: "Support tool \(name).",
                    parameters: .object(
                        properties: ["orderId": .string(description: "Order identifier")],
                        required: ["orderId"]
                    )
                ),
                handler: ClosureToolHandler { _ in .null }
            )
        }
        return registry
    }

    /// The registry's definitions as frozen segments, optionally rotated the way an unordered
    /// collection's iteration order differs from one launch to the next.
    private static func promptCacheTools(
        from registry: ToolRegistryKit.ToolRegistry,
        rotation: Int
    ) async -> [PromptSegment] {
        let definitions = await registry.registeredDefinitions
        let shift = rotation % definitions.count
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (definitions[shift...] + definitions[..<shift]).map { definition in
            let data = (try? encoder.encode(definition)) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            return PromptSegment(id: "tool:\(definition.name)", content: text, volatility: .frozen, tokens: 260)
        }
    }

    private static let cacheRules = PromptSegment(
        id: "rules",
        content: String(repeating: "house rule. ", count: 400),
        volatility: .frozen,
        tokens: 1_200
    )

    private static func promptCacheToolBlock() async {
        print("  A. six tools from a real ToolRegistry, registered out of order, over six turns")
        let registry = await promptCacheRegistry()
        var sorted: [AssembledPrompt] = []
        var rotating: [AssembledPrompt] = []
        for turn in 1...6 {
            let history = (1..<turn).map {
                PromptSegment(id: "turn:\($0)", content: "result \($0)", volatility: .turn, tokens: 420)
            }
            let query = [PromptSegment(id: "query", content: "message \(turn)", volatility: .ephemeral, tokens: 60)]
            let stable = await promptCacheTools(from: registry, rotation: 0)
            let shuffled = await promptCacheTools(from: registry, rotation: turn)
            sorted.append(AssembledPrompt(segments: [cacheRules] + stable + history + query))
            rotating.append(AssembledPrompt(segments: [cacheRules] + shuffled + history + query))
        }
        let auditor = PrefixStabilityAuditor()
        let layouts = [("registry order (sorted by name)", sorted), ("order that rotates per turn", rotating)]
        for (label, prompts) in layouts {
            let report = auditor.audit(prompts)
            let healthy = report.transitions.filter(\.isHealthy).count
            let retained = String(format: "%.2f", report.retainedRatio * 100)
            print(
                "     \(label.padding(toLength: 32, withPad: " ", startingAt: 0))"
                    + "healthy \(healthy)/\(report.transitions.count)   retained \(retained)%"
                    + "   stable \(report.isStable)"
            )
        }
    }

    // MARK: - B: what compaction costs the cache

    private static func promptCacheCompactionCost() async {
        print("  B. twenty turns of 450-token tool results under a 5,000-token history budget,"
            + " three compaction policies")
        let registry = await promptCacheRegistry()
        let tools = await promptCacheTools(from: registry, rotation: 0)
        let policies = [
            CacheCompactionPolicy(label: "history never compacted (over budget)", ceiling: nil, target: 0),
            CacheCompactionPolicy(label: "slide the window every turn", ceiling: 5_000, target: 5_000),
            CacheCompactionPolicy(label: "compact in batches, down to 3,200", ceiling: 5_000, target: 3_200)
        ]
        for policy in policies {
            let line = await promptCacheCompactionRun(
                label: policy.label,
                ceiling: policy.ceiling,
                target: policy.target,
                tools: tools
            )
            print(line)
        }
    }

    /// When to compact and how far down to go. A `nil` ceiling never compacts.
    private struct CacheCompactionPolicy {
        let label: String
        let ceiling: Int?
        let target: Int
    }

    private static func promptCacheCompactionRun(
        label: String,
        ceiling: Int?,
        target: Int,
        tools: [PromptSegment]
    ) async -> String {
        let estimator = CharacterCountTokenEstimator()
        let compactor = ContextCompactor(strategies: [SlidingWindowCompactionStrategy()])
        let session = CachingSession(
            strategy: .planned,
            policy: .explicitTwoTier,
            pricing: CachePricing(inputUSDPerMillionTokens: 3)
        )
        var messages = [CompactableMessage(role: .system, content: cacheRules.content)]
        var names: [UUID: String] = [:]
        var prompts: [AssembledPrompt] = []
        var compactions = 0
        for turn in 1...20 {
            let message = CompactableMessage(
                role: .tool,
                content: "Tool result \(turn): " + String(repeating: "order-line ", count: 163)
            )
            names[message.id] = "turn:\(turn)"
            messages.append(message)
            let size = messages.reduce(0) { $0 + estimator.estimatedTokenCount(for: $1.content) }
            if let ceiling, size > ceiling,
               let result = try? await compactor.compact(messages, budget: CompactionBudget(maxTokens: target)) {
                messages = result.messages
                compactions += 1
            }
            let history = messages.filter { $0.role != .system }.map { message in
                let tokens = estimator.estimatedTokenCount(for: message.content)
                return PromptSegment(
                    id: names[message.id] ?? "unknown",
                    content: message.content,
                    volatility: .turn,
                    tokens: tokens
                )
            }
            let query = PromptSegment(id: "query", content: "message \(turn)", volatility: .ephemeral, tokens: 60)
            let prompt = AssembledPrompt(segments: [cacheRules] + tools + history + [query])
            prompts.append(prompt)
            let forecast = WorkloadForecast(requestsPerMinute: 3, remainingRequests: 20 - turn)
            _ = await session.send(prompt, forecast: forecast, at: Double(turn) * 20)
        }
        return await promptCacheSummaryLine(label, compactions, session, prompts)
    }

    private static func promptCacheSummaryLine(
        _ label: String,
        _ compactions: Int,
        _ session: CachingSession,
        _ prompts: [AssembledPrompt]
    ) async -> String {
        let summary = await session.summary()
        let broken = PrefixStabilityAuditor().audit(prompts).transitions.filter { !$0.isHealthy }.count
        let hit = String(format: "%.2f", summary.hitRate * 100)
        let spend = String(format: "%.6f", summary.actualUSD)
        return "     \(label.padding(toLength: 40, withPad: " ", startingAt: 0))"
            + "compactions \(String(format: "%2d", compactions))   prompt tokens \(summary.totalTokens)"
            + "   broken prefixes \(String(format: "%2d", broken))/19   hit \(hit)%   spend $\(spend)"
    }
}
