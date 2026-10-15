import DegenerationGuardKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifiers the eighty-eighth scenario's turns bill against.
extension ProviderIdentifier {
    static let degenerationHost = ProviderIdentifier("degeneration-host")
    static let degenerationFallback = ProviderIdentifier("degeneration-fallback")
}

extension EcosystemDemo {
    /// What a guarded read of one reply produced.
    private struct GuardedRead {
        let shown: String
        let read: Int
        let chunks: Int
        let finding: DegenerationFinding?
    }

    /// The eighty-eighth scenario: the answer that repeats itself.
    ///
    /// A cheap route falls into a loop and would keep writing until its 4,096-token cap.
    /// `ScriptedProvider` returns whole replies, so each reply is cut into 16-scalar chunks the
    /// way a live bubble receives them. A `DegenerationGate` stops reading at the fourth copy and
    /// only what was read is metered: a provider stops generating when its stream is cancelled
    /// (the few tokens already in flight are ignored here). The user keeps one copy of the loop,
    /// the question goes to a second route, and a `DegenerationLedger` records which route looped.
    static func runDegenerationGuardScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let ledger = DegenerationLedger()
            let looping = try await degenerationTurn(degenerationPrompt, route: .degenerationHost)
            print("[degeneration scenario] degeneration-host replies with \(looping.unicodeScalars.count) scalars"
                + " (its 4,096-token cap at the demo's 4 characters per token)")
            let first = await readGuarded(looping, model: ProviderIdentifier.degenerationHost.rawValue, ledger: ledger)
            await meterDegenerationTurn(read: first.read, route: .degenerationHost, meter: meter)
            if let finding = first.finding {
                print("[degeneration scenario] DegenerationGate: \(finding.kind); stopped after \(first.read)"
                    + " scalars (chunk \(first.chunks) of 16)")
            }
            print("[degeneration scenario] kept for the user: \"\(first.shown)\"")
            await printDegenerationSaving(looping: looping, read: first.read)

            let retry = try await degenerationTurn(degenerationPrompt, route: .degenerationFallback)
            let fallback = ProviderIdentifier.degenerationFallback.rawValue
            let second = await readGuarded(retry, model: fallback, ledger: ledger)
            await meterDegenerationTurn(read: second.read, route: .degenerationFallback, meter: meter)
            let outcome = second.finding.map { "\($0.kind)" } ?? "clean after \(second.read) scalars"
            print("[degeneration scenario] retried on degeneration-fallback: \"\(second.shown)\" (\(outcome))")
            for model in await ledger.models {
                let entry = await ledger.entry(for: model)
                print("[degeneration scenario] ledger: \(model) looped in \(entry.loops) of \(entry.streams) answers")
            }
            print("[degeneration scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[degeneration scenario] FAILED: \(error)")
        }
    }

    private static let degenerationPrompt = "System: You are a physics tutor.\n\n"
        + "User: A cyclist rides at 3.2 km/h. What is that in metres per second?"

    /// The looping reply, written until it reaches the route's cap.
    private static let degenerationLoop: String = {
        var reply = "To convert km/h to m/s, divide by 3.6. "
        while reply.unicodeScalars.count < 4_096 * 4 { reply += "Wait, let me reconsider the units. " }
        return reply
    }()

    private static let degenerationAnswer = "Divide by 3.6: 3.2 km/h is 3.2 / 3.6 = 0.889 m/s, about 0.89 m/s."

    private static func readGuarded(_ reply: String, model: String, ledger: DegenerationLedger) async -> GuardedRead {
        let gate = DegenerationGate(model: model, ledger: ledger)
        let scalars = Array(reply.unicodeScalars)
        var received = ""
        var chunks = 0
        for start in stride(from: 0, to: scalars.count, by: 16) {
            var chunk = String.UnicodeScalarView()
            chunk.append(contentsOf: scalars[start..<min(start + 16, scalars.count)])
            received += String(chunk)
            chunks += 1
            if case .stop = await gate.ingest(String(chunk)) { break }
        }
        let read = await gate.scanned
        guard let finding = await gate.finish().finding else {
            return GuardedRead(shown: received, read: read, chunks: chunks, finding: nil)
        }
        let kept = DegenerationGuard.salvage(received, keeping: finding).text
        return GuardedRead(shown: kept, read: read, chunks: chunks, finding: finding)
    }

    /// The same looping reply metered twice on a scratch meter: read to the cap, and read until
    /// the gate stopped it.
    private static func printDegenerationSaving(looping: String, read: Int) async {
        let unguarded = await buildMeter()
        await unguarded.record(
            TokenUsage(promptTokens: degenerationPrompt.count / 4, completionTokens: looping.count / 4),
            for: ProviderIdentifier.degenerationHost.rawValue
        )
        let guarded = await buildMeter()
        await guarded.record(
            TokenUsage(promptTokens: degenerationPrompt.count / 4, completionTokens: read / 4),
            for: ProviderIdentifier.degenerationHost.rawValue
        )
        print("[degeneration scenario] this turn read to the cap: $\(await unguarded.totalCost());"
            + " stopped by the gate: $\(await guarded.totalCost())")
    }

    private static func meterDegenerationTurn(read: Int, route: ProviderIdentifier, meter: TokenMeter) async {
        await meter.record(
            TokenUsage(promptTokens: degenerationPrompt.count / 4, completionTokens: read / 4),
            for: route.rawValue
        )
    }

    private static func degenerationTurn(_ prompt: String, route: ProviderIdentifier) async throws -> String {
        let script = route == .degenerationHost ? [degenerationLoop] : [degenerationAnswer]
        let router = ProviderRouter(providers: [ScriptedProvider(identifier: route, script: script)])
        return try await LLMSession(router: router).send(prompt).text
    }
}
