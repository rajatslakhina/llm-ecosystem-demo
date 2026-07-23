import Foundation
import OutputRepairKit
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

/// A ninth provider identity, used only by the output-repair scenario's
/// routed calls — both the rejected first hop and the repaired second one.
/// Registered with its own explicit rate in `EcosystemDemo.buildMeter()` so
/// every repair round trip's cost is visible rather than silently defaulting
/// to $0.
extension ProviderIdentifier {
    static let repairHost = ProviderIdentifier("repair-host")
}

/// Validates a raw reply into a `WeatherReport`, collecting every missing or
/// mistyped field in one pass so a single repair round can fix all of them.
/// This is `OutputRepairKit`'s `OutputContract` seam — in a fuller stack a
/// `StructuredOutputKit` schema decoder would sit here; the demo keeps it a
/// plain synchronous `Codable` check because `OutputContract.validate` is
/// synchronous by design (validation should never itself do I/O).
struct WeatherRepairContract: OutputContract {
    func validate(_ raw: String) -> ContractResult<WeatherReport> {
        guard let data = raw.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .invalid([RepairIssue(path: "", problem: "not a JSON object", observed: raw)])
        }
        var issues: [RepairIssue] = []
        if !(dict["city"] is String) {
            issues.append(RepairIssue(path: "city", problem: "missing or not a string", expected: "string"))
        }
        if dict["temperatureCelsius"] as? Double == nil && dict["temperatureCelsius"] as? Int == nil {
            issues.append(RepairIssue(
                path: "temperatureCelsius",
                problem: "missing or not a number",
                expected: "number"
            ))
        }
        if !(dict["conditions"] is String) {
            issues.append(RepairIssue(path: "conditions", problem: "missing or not a string", expected: "string"))
        }
        guard issues.isEmpty, let report = try? JSONDecoder().decode(WeatherReport.self, from: data) else {
            return .invalid(issues)
        }
        return .valid(report)
    }
}

/// `OutputRepairKit`'s `ResponseProducing` seam wired to a real routed
/// `LLMSession`: each attempt is a genuine `ProviderRouter` → `LLMSession`
/// call, and every hop — the rejected one and the repaired one — is metered
/// with `TokenMeter`, exactly like every other scenario in this demo.
struct MeteredRepairProducer: ResponseProducing {
    let session: LLMSession
    let meter: TokenMeter
    let providerID: ProviderIdentifier

    func produce(prompt: String) async throws -> String {
        let response = try await session.send(prompt)
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
            for: providerID.rawValue
        )
        return response.text
    }
}

extension EcosystemDemo {
    /// The fifteenth scenario: `OutputRepairKit` drives a bounded, self-healing
    /// repair loop around a real routed model. The scripted provider's first
    /// reply omits a required field; the loop's `WeatherRepairContract` rejects
    /// it with a structured `RepairIssue`, `OutputRepairKit`'s
    /// `DefaultRepairPrompter` folds that reason into a correction prompt, and
    /// the second routed `LLMSession.send()` call repairs it. This is the loop
    /// layer that sits *around* validation: `OutputRepairKit` orchestrates,
    /// `ProviderGatewayKit` produces each attempt, the contract validates, and
    /// `TokenMeter` meters both hops. `OutputRepairKit` has no compile-time
    /// dependency on either — the producer and contract are the only seams.
    static func runOutputRepairScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let providerID = ProviderIdentifier.repairHost
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: providerID,
                script: [
                    #"{"city": "Delhi", "temperatureCelsius": 41.0}"#,
                    #"{"city": "Delhi", "temperatureCelsius": 41.0, "conditions": "clear"}"#
                ]
            )
        ])
        let session = LLMSession(router: router)
        let producer = MeteredRepairProducer(session: session, meter: meter, providerID: providerID)
        let recorder = InMemoryRepairEventRecorder()
        let loop = OutputRepairLoop(
            contract: WeatherRepairContract(),
            policy: RepairPolicy(maxAttempts: 3),
            recorder: recorder
        )
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")

        do {
            let run = try await loop.run(initialPrompt: instructions, producer: producer)
            let firstIssues = run.issueHistory.first?.map(\.path).joined(separator: ", ") ?? "none"
            print(
                "[output-repair scenario] attempt 1 rejected [\(firstIssues)], "
                    + "converged after \(run.attempts) attempts (\(run.repairs) repair): \(run.output)"
            )
            let events = await recorder.count
            let stats = await loop.stats
            print(
                "[output-repair scenario] \(events) repair events recorded; both routed hops metered under "
                    + "\(providerID.rawValue) (succeeded: \(stats.succeeded), totalRepairs: \(stats.totalRepairs))"
            )
        } catch {
            print("[output-repair scenario] FAILED: \(error)")
        }
    }
}
