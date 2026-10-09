import Foundation
import ProviderGatewayKit
import TokenMeterKit
import ToolAuthorityKit
import ToolRegistryKit
import TrajectoryConsistencyKit

/// The identifier the eighty-fourth scenario's routed agent turns bill against.
extension ProviderIdentifier {
    static let trajectoryConsistencyHost = ProviderIdentifier("trajectory-consistency-host")
}

/// A tool call as the wire carries it: `arguments` is the JSON *text* the model wrote.
private struct WireToolCall: Decodable {
    let tool: String
    let arguments: String
}

/// Where a human's signatures are kept, keyed by the digest each one authorizes: the shape of
/// ai-chat-app's `ToolAuthorityGate`. `canonical` decides what the digest is computed over.
private actor SignatureDesk {
    let canonical: Bool
    private let broker = AuthorityBroker()
    private var signatures: [String: Approval] = [:]
    private var pending: ApprovalRequest?
    private var tick = 0

    init(canonical: Bool) async throws {
        self.canonical = canonical
        try await broker.issue(Grant(
            id: "g-billing",
            principal: "billing-agent",
            task: "refund-duplicate-charge",
            capabilities: [Capability(
                tool: ToolName("issue_refund"),
                actions: [.write],
                scope: .subtree(ResourcePath("orders")),
                requiresApproval: true
            )]
        ))
    }

    /// The arguments the desk authorizes and, if allowed, executes.
    func bound(_ call: WireToolCall) -> String {
        guard canonical, let text = ToolStep(tool: call.tool, arguments: call.arguments).canonicalArguments else {
            return call.arguments
        }
        return text
    }

    func decide(_ call: WireToolCall) async throws -> AuthorityDecision {
        tick += 1
        let proposal = ToolProposal(
            id: "call-\(tick)",
            principal: "billing-agent",
            tool: ToolName(call.tool),
            action: .write,
            resource: ResourcePath("orders/A-1042"),
            arguments: bound(call),
            provenance: .modelAuthored
        )
        let decision = try await broker.authorize(proposal, at: tick, approval: signatures[proposal.digest])
        if case .approvalRequired(let request) = decision { pending = request }
        return decision
    }

    func signPending(by approver: String) {
        guard let request = pending else { return }
        signatures[request.digest] = Approval(
            id: "sig-\(signatures.count + 1)", granting: request, approver: approver, validThroughTick: tick + 8
        )
        pending = nil
    }
}

extension EcosystemDemo {
    /// The eighty-fourth scenario: an approval meets a resend. A billing agent may only call
    /// `issue_refund` with a human signature (`ToolAuthorityKit`, `requiresApproval`). The user
    /// signs the call from turn 1 and the host resends; the model then writes the same call again,
    /// spelled differently. A desk that keys signatures on the argument bytes asks the user a second
    /// time. A desk that keys them on `TrajectoryConsistencyKit`'s canonical arguments honours the
    /// signature and runs the refund through `ToolRegistryKit` with exactly the bytes that were
    /// approved. A second conversation's resend changes the amount: both desks ask again, and only
    /// `ReplayCheck` can say why. The three proposals are then read as three runs of one input.
    static func runTrajectoryConsistencyScenario(meter: TokenMeter) async {
        do {
            let first = try await replayConversation(script: approvedResendScript, label: "A", meter: meter)
            let second = try await replayConversation(script: driftedResendScript, label: "B", meter: meter)
            printReplayReport([first.proposal, first.resend, second.resend])
        } catch {
            print("[trajectory consistency scenario] FAILED: \(error)")
        }
    }

    private static let refundPrompt = "System: You are a billing agent. issue_refund needs a human signature.\n\n"
        + "User: Refund the duplicate charge ch_88 on order A-1042."

    private static let approvedCall =
        #"{"tool":"issue_refund","arguments":"{\"order_id\":\"A-1042\",\"charge_id\":\"ch_88\","#
        + #"\"amount_cents\":4999}"}"#

    private static let approvedResendScript = [
        approvedCall,
        #"{"tool":"issue_refund","arguments":"{ \"amount_cents\": 4999.0, "#
            + #"\"charge_id\": \"ch_88\", \"order_id\": \"A-1042\" }"}"#,
        "Refunded $49.99 for the duplicate charge ch_88 on order A-1042."
    ]

    private static let driftedResendScript = [
        approvedCall,
        #"{"tool":"issue_refund","arguments":"{\"order_id\":\"A-1042\",\"charge_id\":\"ch_88\","#
            + #"\"amount_cents\":9998}"}"#,
        "I need your approval again: the refund I would send now is $99.98."
    ]

    private struct ReplayPair {
        let proposal: ToolStep
        let resend: ToolStep
    }

    private static func replayConversation(
        script: [String],
        label: String,
        meter: TokenMeter
    ) async throws -> ReplayPair {
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .trajectoryConsistencyHost, script: script)
        ])
        let byteDesk = try await SignatureDesk(canonical: false)
        let canonicalDesk = try await SignatureDesk(canonical: true)
        let call = try decodeWireCall(try await consistencyTurn(refundPrompt, router: router, meter: meter))
        print("[trajectory consistency scenario] \(label) turn 1: \(call.tool) \(call.arguments)")
        for desk in [byteDesk, canonicalDesk] {
            _ = try await desk.decide(call)
            await desk.signPending(by: "ops@billing")
        }
        print("[trajectory consistency scenario] \(label) both desks asked; the user signed the call above")

        let resendPrompt = refundPrompt + "\n\nHost: the user approved issue_refund. Send the call again."
        let resend = try decodeWireCall(try await consistencyTurn(resendPrompt, router: router, meter: meter))
        let verdict = ReplayCheck.compare(
            reference: ToolStep(tool: call.tool, arguments: call.arguments),
            replay: ToolStep(tool: resend.tool, arguments: resend.arguments)
        )
        print("[trajectory consistency scenario] \(label) resend: \(resend.tool) \(resend.arguments)")
        print("[trajectory consistency scenario] \(label) ReplayCheck: \(verdict)")
        var refunded = false
        for desk in [byteDesk, canonicalDesk] {
            let decision = try await desk.decide(resend)
            let name = desk.canonical ? "canonical-keyed desk" : "byte-keyed desk     "
            print("[trajectory consistency scenario] \(label) \(name): \(signatureText(decision, verdict: verdict))")
            if case .allowed = decision, !refunded {
                print("[trajectory consistency scenario] \(label) issue_refund ran with the approved bytes: "
                    + (try await runRefund(arguments: await desk.bound(resend))))
                refunded = true
            }
        }
        let outcome = refunded ? "The refund ran." : "Nothing ran."
        let answer = try await consistencyTurn(resendPrompt + "\n\nHost: " + outcome, router: router, meter: meter)
        print("[trajectory consistency scenario] \(label) answer: \"\(answer)\"")
        return ReplayPair(
            proposal: ToolStep(tool: call.tool, arguments: call.arguments),
            resend: ToolStep(tool: resend.tool, arguments: resend.arguments)
        )
    }

    private static func signatureText(_ decision: AuthorityDecision, verdict: ReplayVerdict) -> String {
        switch decision {
        case .allowed(let authorization):
            return "ALLOWED, signed by \(authorization.approvedBy ?? "nobody")"
        case .denied(let reason):
            return "DENIED - \(reason)"
        case .approvalRequired:
            return verdict.isSameCall
                ? "asks the user AGAIN for the call they already signed"
                : "asks again, and can say why: \(verdict)"
        }
    }

    private static func printReplayReport(_ proposals: [ToolStep]) {
        let runs = proposals.enumerated().map { Trajectory(id: "proposal \($0.offset + 1)", steps: [$0.element]) }
        guard let report = ConsistencyReport(trajectories: runs) else { return }
        print("[trajectory consistency scenario] the three issue_refund proposals as runs of one input: "
            + "\(report.distinctToolPaths) tool path, \(report.distinctCallPathsBySpelling) calls as bytes, "
            + "\(report.distinctCallPaths) canonically")
        for volatile in report.volatileArguments {
            print("      volatile: \(volatile.tool).\(volatile.path), \(volatile.distinctValues) values")
        }
        switch ConsistencyPolicy().evaluate(report) {
        case .consistent:
            print("      policy: consistent")
        case .inconsistent(let reasons):
            print("      policy: inconsistent - " + reasons.map(\.description).joined(separator: "; "))
        }
    }

    private static func decodeWireCall(_ text: String) throws -> WireToolCall {
        try JSONDecoder().decode(WireToolCall.self, from: Data(text.utf8))
    }

    private static func consistencyTurn(
        _ prompt: String,
        router: ProviderRouter,
        meter: TokenMeter
    ) async throws -> String {
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: response.providerID.rawValue
        )
        return response.text
    }

    private static func runRefund(arguments: String) async throws -> String {
        let registry = ToolRegistryKit.ToolRegistry()
        await registry.register(
            ToolRegistryKit.ToolDefinition(
                name: "issue_refund",
                description: "Refund one charge on an order.",
                parameters: .object(
                    properties: [
                        "order_id": .string(description: "Order id"),
                        "charge_id": .string(description: "Charge id"),
                        "amount_cents": .integer(description: "Amount in cents")
                    ],
                    required: ["order_id", "charge_id", "amount_cents"]
                )
            ),
            handler: ClosureToolHandler { _ in .string("refund rf_301 queued") }
        )
        let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
            id: "r1", toolName: "issue_refund", argumentsJSON: Data(arguments.utf8)
        ))
        guard case .success(.string(let text)) = result.outcome else { return "\(result.outcome)" }
        return "\(arguments) -> \(text)"
    }
}
