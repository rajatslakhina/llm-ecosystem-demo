import Foundation
import ProviderGatewayKit
import SelectionTrustKit
import TokenMeterKit
import ToolAuthorityKit

/// The identifier the forty-seventh scenario's accounting bills against. Registered with an
/// explicit rate in `Pricing`, without which it meters $0 in silence.
extension ProviderIdentifier {
    static let selectionTrustHost = ProviderIdentifier("selection-trust-host")
}

/// Approves whatever it is shown, so the scenario measures what the broker *decides* rather than
/// what a person would have done. The point of panel B is that the sheet a person sees is the
/// same either way.
struct ScenarioApprover: SelectionTrustKit.ConfirmationPresenter {
    func confirm(_ request: SelectionTrustKit.ConfirmationRequest) async -> Bool { true }
}

extension EcosystemDemo {
    /// The forty-seventh scenario: **a refund whose every argument is authentic, and whose choice
    /// of which order to refund was made by an injected passage.**
    ///
    /// Scenario 21 already showed `ToolAuthorityKit` refusing an outbound send because its
    /// arguments came from a poisoned knowledge-base passage. That is content trust, and it works.
    /// This scenario is the case it cannot see. The planner reads the same passage, and then
    /// proposes refunding order **9001** — a real order, read out of the app's own order table.
    /// The bytes are ours. The *selection* is the attacker's.
    ///
    /// `ToolAuthorityKit`'s provenance ladder is `operatorAuthored < modelAuthored < untrusted`,
    /// and it has no case for "our own data, chosen by the planner" — the closest is
    /// `.modelAuthored`, which reads as "written from trusted context" and sits under the refund
    /// capability's ceiling. So the call clears the ceiling and escalates to a human, which is
    /// exactly what that package promises and is not a bug in it.
    ///
    /// What a human then sees is a sheet reading *refund order 9001, $40*, every field of it true.
    /// Nothing on that sheet says the order id was chosen after reading `kb-refund-policy`.
    static func runSelectionTrustScenario(meter: TokenMeter) async {
        print("[selection-trust scenario] the refund the provenance ceiling admits")
        let broker = AuthorityBroker()
        do {
            try await issueRefundGrant(broker)
        } catch {
            print("[selection-trust scenario] FAILED to issue grant: \(error)")
            return
        }
        let session = await poisonedSession()
        await selectionTrustPartA(broker: broker, session: session)
        await selectionTrustPartB(session: session)
        await selectionTrustPartC(broker: broker)
        await meter.record(
            TokenUsage(promptTokens: 620, completionTokens: 180),
            for: ProviderIdentifier.selectionTrustHost.rawValue
        )
    }

    // MARK: - A: the two brokers disagree

    /// Both brokers are asked about the same refund. One clears it to a human; the other declines
    /// to put it in front of one.
    private static func selectionTrustPartA(broker: AuthorityBroker, session: BrokerSession) async {
        print("  A. the planner read kb-refund-policy, then proposed refunding order 9001")
        let proposal = ToolProposal(
            id: "call-refund-9001",
            principal: supportAgent,
            tool: issueRefundTool,
            action: .write,
            resource: ResourcePath("orders/9001"),
            arguments: #"{"orderId":"9001","amount":40}"#,
            // Read out of our own order table. Not untrusted by any reading of that ladder.
            provenance: .modelAuthored
        )
        do {
            let decision = try await broker.authorize(proposal, at: 1)
            print("     ToolAuthorityKit  : \(describeAuthority(decision))")
        } catch {
            print("     ToolAuthorityKit  : FAILED \(error)")
            return
        }
        let result = await session.authorize(plannerChosenRefund(), key: CommitKey("refund-9001"))
        print("     SelectionTrustKit : \(describeSelectionTrust(result))")
        print("     The ladder has no case for \"our data, their choice\" — .modelAuthored is the")
        print("     nearest, and it sits under the ceiling. The second axis is where it lands.")
    }

    // MARK: - B: what the sheet could say

    /// The confirmation request carries no parameter values, deliberately. That is the package's
    /// position: a sheet that renders the attacker's string cannot be the security boundary.
    private static func selectionTrustPartB(session: BrokerSession) async {
        print("  B. what a human would have been shown, had it reached them")
        let transcript = await session.transcript
        guard let entry = transcript.last else {
            print("     nothing was recorded")
            return
        }
        print("     recorded: tick \(entry.tick), \(entry.intentName), parameters \(entry.parameterNames)")
        print("     worst parameter provenance \(entry.worstProvenance), session floor \(entry.floorAfter)")
        print("     outcome \(entry.outcome)")
        print("     The audit line names parameters and never their values, and the floor is the")
        print("     only field on it that knows an injected passage was read at all.")
    }

    // MARK: - C: the repair

    /// The escape hatch the README names: re-entry through a system-mediated picker mints a
    /// `.userConfirmed` value, and a user-selected value is exempt from the floor.
    ///
    /// Worth reading the two `ToolAuthorityKit` lines together: it answers `APPROVAL REQUIRED` in
    /// both A and C. That is not a failure — it is a ceiling doing exactly what a ceiling does, and
    /// the point is that the two cases are indistinguishable to it while being the whole question.
    private static func selectionTrustPartC(broker: AuthorityBroker) async {
        print("  C. the same refund, after the user picked the order themselves")
        let session = await poisonedSession()
        let result = await session.authorize(userChosenRefund(), key: CommitKey("refund-9001-picked"))
        print("     SelectionTrustKit : \(describeSelectionTrust(result))")
        print("     prompts raised    : \(await session.promptsRaised) (critical tier)")
        let proposal = ToolProposal(
            id: "call-refund-9001-picked",
            principal: supportAgent,
            tool: issueRefundTool,
            action: .write,
            resource: ResourcePath("orders/9001"),
            arguments: #"{"orderId":"9001","amount":40}"#,
            provenance: .operatorAuthored
        )
        do {
            let decision = try await broker.authorize(proposal, at: 2)
            print("     ToolAuthorityKit  : \(describeAuthority(decision))")
        } catch {
            print("     ToolAuthorityKit  : FAILED \(error)")
        }
        print("     ToolAuthorityKit returns the same verdict here as in A — its ceiling cannot")
        print("     tell the two cases apart, because on its ladder nothing about them differs.")
        print("     SelectionTrustKit moved from refused to a prompt. That gap is the second axis.")
    }

    // MARK: - Fixtures

    /// A session that has read the poisoned passage, which is what puts the floor on the floor.
    private static func poisonedSession() async -> BrokerSession {
        let session = BrokerSession(
            id: SessionID("ticket-8842"),
            presenter: ScenarioApprover(),
            budget: CommitBudget(capacity: 3)
        )
        await session.noteContentIngested(from: SourceID("kb-refund-policy"))
        return session
    }

    /// The order id is real and ours; the planner chose which one.
    private static func plannerChosenRefund() -> Invocation {
        Invocation(
            intentName: "IssueRefund",
            effect: .commit,
            tier: .critical,
            blastRadius: 1,
            parameters: [
                ParameterName("orderId"): .literal("9001", .appDerived),
                ParameterName("amount"): .literal("40", .appDerived)
            ]
        )
    }

    /// The same two values, picked by the user in a system-mediated surface.
    private static func userChosenRefund() -> Invocation {
        Invocation(
            intentName: "IssueRefund",
            effect: .commit,
            tier: .critical,
            blastRadius: 1,
            parameters: [
                ParameterName("orderId"): .literal("9001", .userConfirmed),
                ParameterName("amount"): .literal("40", .userConfirmed)
            ]
        )
    }

    private static func issueRefundGrant(_ broker: AuthorityBroker) async throws {
        try await broker.issue(Grant(
            id: "g-refund-9001",
            principal: supportAgent,
            task: "answer-ticket-8842",
            capabilities: [
                Capability(
                    tool: issueRefundTool,
                    actions: [.write],
                    scope: .subtree(ResourcePath("orders")),
                    maxProvenance: .modelAuthored,
                    requiresApproval: true
                )
            ],
            validThroughTick: 100,
            maxUses: 10
        ))
    }

    private static func describeAuthority(_ decision: AuthorityDecision) -> String {
        switch decision {
        case .allowed(let authorization): return "ALLOWED via \(authorization.grantID)"
        case .denied(let reason): return "DENIED — \(reason)"
        case .approvalRequired(let request): return "APPROVAL REQUIRED — \(request.action) on \(request.resource)"
        }
    }

    private static func describeSelectionTrust(_ result: AuthorizationResult) -> String {
        switch result.decision {
        case .allowedCommit: return "ALLOWED COMMIT (requirement \(result.requirement))"
        case .allowedInert: return "ALLOWED INERT"
        case .replayed: return "REPLAYED"
        case .declined: return "DECLINED by the user"
        case .refused(let reason): return "REFUSED — \(reason.check): \(reason.detail)"
        }
    }
}
