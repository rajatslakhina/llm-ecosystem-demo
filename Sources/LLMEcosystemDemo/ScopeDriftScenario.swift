import Foundation
import ProviderGatewayKit
import ScopeDriftKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the seventy-fourth scenario's routed hop bills against.
extension ProviderIdentifier {
    static let scopeDriftHost = ProviderIdentifier("scope-drift-host")
}

extension EcosystemDemo {
    /// The seventy-fourth scenario: `ToolAuthorityKit` (scenario 21) decides one call and
    /// `ToolIntegrityKit` (scenario 73) decides one definition. Neither sees a session. This
    /// scenario puts `ScopeDriftKit`'s ledger between a routed turn and `ToolRegistryKit`'s
    /// dispatch: the model's proposed push is checked against the agent's manifest, refused,
    /// elevated with a justification, then dispatched. Two more small grants later, the drift
    /// report names the fan-out no single grant showed (OWASP MCP02:2025).
    static func runScopeDriftScenario(meter: TokenMeter) async {
        let clock = ManualScopeClock(start: Date(timeIntervalSince1970: 1_790_000_000))
        let ledger = ScopeLedger(manifest: releaseBotManifest(), clock: clock)
        let session = SessionBinding(agent: "release-bot", session: "demo-74")
        await gateARoutedPush(ledger: ledger, session: session, meter: meter)
        await creepThenReport(ledger: ledger, session: session)
        let borrowed = await ledger.check(
            Scope(resource: "repo", action: .write, qualifiers: ["branch": ScopePattern("release/2.4")]),
            for: SessionBinding(agent: "release-bot", session: "demo-74b")
        )
        print("[scope drift scenario] C. a second session reuses release/2.4: \(describeScopeDecision(borrowed))")
    }

    private static func releaseBotManifest() -> ScopeManifest {
        ScopeManifest(
            agent: "release-bot",
            baseline: [
                Scope(resource: "repo", action: .read),
                Scope(resource: "repo", action: .write, qualifiers: ["branch": ScopePattern("feature/*")])
            ],
            ceilings: ["repo": .write],
            budget: CreepBudget(maxElevationTTL: 900, maxConcurrentElevations: 4, maxElevationsPerSession: 5)
        )
    }

    /// A. a real routed turn proposes a push; the ledger decides before the registry dispatches.
    private static func gateARoutedPush(ledger: ScopeLedger, session: SessionBinding, meter: TokenMeter) async {
        let providerID = ProviderIdentifier.scopeDriftHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [#"{"tool": "push_branch", "arguments": {"branch": "release/2.4"}}"#]
            )
        ])
        do {
            let prompt = "Cut release 2.4: push the release branch."
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
                for: providerID.rawValue
            )
            let call = try JSONDecoder().decode(ScriptedToolCall.self, from: Data(response.text.utf8))
            let branch = call.arguments["branch", default: ""]
            let needed = Scope(resource: "repo", action: .write, qualifiers: ["branch": ScopePattern(branch)])
            let first = await ledger.check(needed, for: session)
            print("[scope drift scenario] A. model proposes \(call.tool)(\(branch)): \(describeScopeDecision(first))")
            let elevation = await ledger.requestElevation(
                needed, for: session, ttl: 600, justification: "cut release 2.4"
            )
            print("   elevation requested with a reason and a 600s TTL: \(describeElevation(elevation))")
            let second = await ledger.check(needed, for: session)
            guard second.isAllowed else {
                print("   FAILED: still not allowed after elevation")
                return
            }
            let dispatch = await pushRegistry().dispatch(ToolRegistryKit.ToolCallRequest(
                id: "call-74", toolName: call.tool, argumentsJSON: try JSONEncoder().encode(call.arguments)
            ))
            let dispatched: String
            if case .success = dispatch.outcome {
                dispatched = "dispatch succeeded"
            } else {
                dispatched = "dispatch FAILED: \(dispatch.outcome)"
            }
            print("   re-checked: \(describeScopeDecision(second)) — \(dispatched)")
        } catch {
            print("[scope drift scenario] A. FAILED: \(error)")
        }
    }

    /// B. two more small, individually reasonable grants; the report looks at all three together.
    private static func creepThenReport(ledger: ScopeLedger, session: SessionBinding) async {
        for (branch, reason) in [("hotfix/2.3.1", "patch crash in 2.3"), ("main", "merge release notes")] {
            _ = await ledger.requestElevation(
                Scope(resource: "repo", action: .write, qualifiers: ["branch": ScopePattern(branch)]),
                for: session, ttl: 600, justification: reason
            )
        }
        let report = await ledger.driftReport(for: session)
        print("[scope drift scenario] B. after 3 small grants: \(report.liveElevations.count) live, " +
            "\(report.findings.count) finding(s)")
        for finding in report.findings {
            print("   FINDING \(finding)")
        }
    }

    private static func pushRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "push_branch",
                description: "Push the named branch to origin.",
                parameters: JSONSchema.object(
                    properties: ["branch": .string(description: "Branch name")],
                    required: ["branch"]
                )
            ),
            handler: ClosureToolHandler { arguments in
                guard case .object(let fields) = arguments, case .string(let branch) = fields["branch"] ?? .null else {
                    return .object(["error": .string("missing branch")])
                }
                return .object(["pushed": .string(branch)])
            }
        )
        return registry
    }

    private static func describeScopeDecision(_ decision: AccessDecision) -> String {
        switch decision {
        case .withinManifest(let scope):
            return "ALLOWED (manifest \(scope))"
        case .withinElevation(let elevation):
            return "ALLOWED (elevation #\(elevation.id))"
        case .denied(.elevationBoundToOtherSession(let elevation)):
            return "DENIED (elevation #\(elevation.id) belongs to \(elevation.binding))"
        case .denied(.elevationExpired(let elevation)):
            return "DENIED (elevation #\(elevation.id) expired)"
        case .denied(let reason):
            return "DENIED (\(reason))"
        }
    }

    private static func describeElevation(_ decision: ElevationDecision) -> String {
        switch decision {
        case .granted(let elevation):
            return "GRANTED #\(elevation.id)"
        case .alreadyCovered(let scope):
            return "NOT NEEDED (\(scope))"
        case .refused(let refusal):
            return "REFUSED (\(refusal))"
        }
    }
}
