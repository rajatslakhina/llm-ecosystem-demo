import Foundation
import LoopGuardKit
import ProgressGateKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit

/// The identifier the eighty-second scenario's routed agent turns bill against.
extension ProviderIdentifier {
    static let progressGateHost = ProviderIdentifier("progress-gate-host")
}

private struct ScriptedRefundCall: Decodable {
    let tool: String
    let arguments: [String: String]
}

extension EcosystemDemo {
    /// The eighty-second scenario: every agent loop in this demo so far stops when the model stops
    /// calling tools, which is the model reporting "done". `ProgressGateKit` moves that decision onto
    /// evidence. A refund agent's tool results are mapped into `Evidence`, a `StageLadder` says what
    /// each stage needs, and the agent's `PROGRESS:` lines are audited rather than obeyed. The
    /// refund's create call times out (status `pending`); the agent emails the customer and answers
    /// "done". The gate refuses that stop, feeds back the missing facts, and only stops once the
    /// ledger confirms the refund. `LoopGuardKit` runs alongside as the control: nothing repeats, so
    /// it sees nothing wrong, because the agent is not stuck. It is wrong about where it is.
    static func runProgressGateScenario(meter: TokenMeter) async {
        let providerID = ProviderIdentifier.progressGateHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: refundAgentScript)
        ])
        let registry = await refundRegistry()
        let guardian = LoopGuard()
        var transcript = "Refund order A-1042 and tell the customer. End each reply with PROGRESS: <stage>."
        var evidence = Evidence()
        var selfReportStop: (turn: Int, evidence: Evidence)?
        do {
            let gate = ProgressGate(ladder: try refundTaskLadder(), stallLimit: 4)
            print("[progress gate scenario] stages: " + gate.ladder.names.joined(separator: " -> "))
            for turn in 1...refundAgentScript.count {
                let response = try await LLMSession(router: router).send(transcript)
                await meter.record(
                    TokenUsage(promptTokens: transcript.count / 4, completionTokens: response.text.count / 4),
                    for: providerID.rawValue
                )
                let claim = ProgressClaim.parse(response.text)
                let firstLine = String(response.text.split(separator: "\n").first ?? "")
                let step: String
                if let call = try? JSONDecoder().decode(ScriptedRefundCall.self, from: Data(firstLine.utf8)) {
                    let observation = try await dispatchRefundCall(call, turn: turn, registry: registry)
                    evidence = evidence.merging(refundEvidence(tool: call.tool, observation: observation))
                    let verdict = await guardian.record(LoopGuardKit.ToolStep(
                        toolName: call.tool, arguments: sortedJSON(call.arguments), observation: observation
                    ))
                    step = "\(call.tool) -> \(observation)  [loop guard: \(verdict == .proceed ? "proceed" : "flag")]"
                    transcript += "\n\nTool \(call.tool) returned: \(observation)"
                } else {
                    step = "answer: \"\(firstLine)\""
                    if selfReportStop == nil { selfReportStop = (turn, evidence) }
                }
                let decision = await gate.check(claim, evidence: evidence)
                print("   turn \(turn) \(step)")
                print("      claim \(progressClaimText(claim)), evidence '\(decision.audit.reading.name)' "
                    + "(\(decision.audit.label)) -> \(decision.shouldStop ? "STOP" : "continue")")
                if decision.shouldStop {
                    print("      \(decision.guidance)")
                    break
                }
                if case .overclaims = decision.audit { print("      fed back: \(decision.guidance)") }
                transcript += "\n\n\(decision.guidance)"
            }
            await printProgressGateSummary(gate: gate, selfReportStop: selfReportStop)
        } catch {
            print("[progress gate scenario] FAILED: \(error)")
        }
    }

    private static let refundAgentScript = [
        #"{"tool": "lookup_order", "arguments": {"order": "A-1042"}}"# + "\nPROGRESS: order located",
        #"{"tool": "create_refund", "arguments": {"order": "A-1042"}}"# + "\nPROGRESS: refund issued",
        #"{"tool": "send_email", "arguments": {"order": "A-1042"}}"# + "\nPROGRESS: customer notified",
        "Refund issued for A-1042 and the customer has been emailed.\nPROGRESS: done",
        #"{"tool": "get_refund", "arguments": {"refund": "R-77"}}"# + "\nPROGRESS: refund issued",
        #"{"tool": "check_ledger", "arguments": {"refund": "R-77"}}"# + "\nPROGRESS: refund confirmed"
    ]

    private static func refundTaskLadder() throws -> StageLadder {
        try StageLadder(baseline: "received", stages: [
            Stage("order located", requires: .present("order.id")),
            Stage("refund issued", requires: .equals("refund.status", "issued")),
            Stage("refund confirmed", requires: .isTrue("ledger.confirmed")),
            Stage("customer notified", requires: .isTrue("email.sent"))
        ])
    }

    /// The host's half of the contract: which tool result fields are evidence for which facts.
    private static func refundEvidence(tool: String, observation: String) -> Evidence {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(observation.utf8)),
              case let .object(fields) = value else { return Evidence() }
        let mapping: [String: [(field: String, fact: String)]] = [
            "lookup_order": [("order", "order.id")],
            "create_refund": [("status", "refund.status")],
            "get_refund": [("status", "refund.status")],
            "check_ledger": [("confirmed", "ledger.confirmed")],
            "send_email": [("sent", "email.sent")]
        ]
        var evidence = Evidence()
        for (field, fact) in mapping[tool, default: []] {
            switch fields[field] {
            case let .string(text)?: evidence.record(fact, .text(text))
            case let .bool(flag)?: evidence.record(fact, .bool(flag))
            case let .number(number)?: evidence.record(fact, .number(number))
            default: continue
            }
        }
        return evidence
    }

    private static func dispatchRefundCall(
        _ call: ScriptedRefundCall,
        turn: Int,
        registry: ToolRegistryKit.ToolRegistry
    ) async throws -> String {
        let result = await registry.dispatch(ToolRegistryKit.ToolCallRequest(
            id: "r\(turn)", toolName: call.tool, argumentsJSON: try JSONEncoder().encode(call.arguments)
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch result.outcome {
        case .success(let value):
            return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        case .failure(let error):
            return "error: \(error)"
        }
    }

    /// Five tools over one simulated back office. `create_refund` times out after queueing, so it
    /// answers `pending`; `get_refund` later reads `issued`.
    private static func refundRegistry() async -> ToolRegistryKit.ToolRegistry {
        let registry = ToolRegistryKit.ToolRegistry()
        let replies: [(String, JSONValue)] = [
            ("lookup_order", .object(["order": .string("A-1042"), "total_cents": .number(4200)])),
            ("create_refund", .object(["refund": .string("R-77"), "status": .string("pending"),
                                       "note": .string("gateway timed out; refund queued")])),
            ("send_email", .object(["sent": .bool(true), "to": .string("customer of A-1042")])),
            ("get_refund", .object(["refund": .string("R-77"), "status": .string("issued")])),
            ("check_ledger", .object(["refund": .string("R-77"), "confirmed": .bool(true)]))
        ]
        for (name, reply) in replies {
            await registry.register(
                ToolRegistryKit.ToolDefinition(name: name, description: "Refund back office: \(name).",
                                               parameters: .object(properties: [:], required: [])),
                handler: ClosureToolHandler { _ in reply }
            )
        }
        return registry
    }

    private static func progressClaimText(_ claim: ProgressClaim?) -> String {
        switch claim {
        case .done?: return "'done'"
        case let .stage(name)?: return "'\(name)'"
        case nil: return "(none)"
        }
    }

    private static func sortedJSON(_ arguments: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(arguments)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
    }

    private static func printProgressGateSummary(
        gate: ProgressGate,
        selfReportStop: (turn: Int, evidence: Evidence)?
    ) async {
        let report = await gate.report()
        if let stop = selfReportStop {
            let status = stop.evidence["refund.status"]?.description ?? "unobserved"
            let ledger = stop.evidence["ledger.confirmed"]?.description ?? "unobserved"
            print("   a loop that stopped on the model's word would have answered at turn \(stop.turn): "
                + "refund.status = \(status), ledger.confirmed \(ledger)")
        }
        print("   gate: \(report.checks) checks, \(report.refusedStops) refused stops, report reliability "
            + "\(Int(((report.overallRate ?? 0) * 100).rounded()))%; loop guard flagged nothing")
    }
}
