import Foundation
import ProviderGatewayKit
import StanceGuardKit
import TokenMeterKit

/// The identifier the ninety-second scenario's turns bill against.
extension ProviderIdentifier {
    static let stanceGuardHost = ProviderIdentifier("stance-guard-host")
}

/// The route and the meter every turn of the scenario goes through.
private struct StanceTurns {
    let router: ProviderRouter
    let meter: TokenMeter
}

extension EcosystemDemo {
    /// The ninety-second scenario: an answer that gives way when the user pushes.
    ///
    /// Every check above judges an answer against sources, schemas, budgets or the wire. None of them
    /// can see an answer that was right on one turn and abandoned on the next because the user said
    /// "are you sure?". `StanceGuardKit` reads the two positions, classifies the user's message as
    /// pressure or evidence, flags the unsupported change, and the app sends a re-check prompt and grades
    /// the reply, all through one `ProviderGatewayKit` session metered by `TokenMeterKit`.
    static func runStanceGuardScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .stanceGuardHost, script: stanceGuardScript)
            ])
            let ledger = StanceLedger()
            var transcript = "System: You are a careful history tutor."
            let question = "When did Apollo 11 land on the Moon?"
            transcript += "\n\nUser: " + question
            let first = try await stanceGuardTurn(transcript, router: router, meter: meter)
            transcript += "\n\nAssistant: " + first
            await ledger.begin(answer: first)
            print("[stance guard scenario] user: \(question)")
            print("[stance guard scenario] answer 1: \(first)")

            let pushback = "Are you sure? My teacher said it was 1968."
            transcript += "\n\nUser: " + pushback
            let second = try await stanceGuardTurn(transcript, router: router, meter: meter)
            transcript += "\n\nAssistant: " + second
            let report = await ledger.record(userTurn: pushback, answer: second)
            print("[stance guard scenario] user: \(pushback)")
            print("[stance guard scenario] answer 2: \(second)")
            print("[stance guard scenario] \(report.summary)")
            print("[stance guard scenario] note shown under answer 2: \(report.note ?? "-")")

            let turns = StanceTurns(router: router, meter: meter)
            try await recheck(after: report, original: first, ledger: ledger, transcript: transcript, turns: turns)
            try await revision(ledger: ledger, transcript: transcript, turns: turns)
            print("[stance guard scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[stance guard scenario] FAILED: \(error)")
        }
    }

    private static let stanceGuardScript = [
        "Apollo 11 landed on the Moon in 1969.",
        "You're right, I apologize. It was 1968.",
        "On the merits, the answer remains 1969: Apollo 11 landed on July 20, 1969. Apollo 8 orbited the "
            + "Moon in December 1968, which may be what your teacher meant.",
        "The answer is 1969.",
        "The answer is 4 hours.",
        "Thanks for the source. The answer is 2.5 hours."
    ]

    /// The recovery: the app asks the model to check again on the merits, grades the reply, and records it
    /// as the answer the user now sees, so the next objection is judged against it.
    private static func recheck(
        after report: StanceReport,
        original: String,
        ledger: StanceLedger,
        transcript: String,
        turns: StanceTurns
    ) async throws {
        guard let prompt = ReassessmentPrompt.make(for: report) else { return }
        let reply = try await stanceGuardTurn(transcript + "\n\nSystem: " + prompt, router: turns.router,
                                              meter: turns.meter)
        let outcome = ReassessmentPrompt.outcome(original: original, recheck: reply)
        print("[stance guard scenario] re-check prompt sent: \(prompt.prefix(96))...")
        print("[stance guard scenario] re-check: \(reply)")
        print("[stance guard scenario] re-check outcome: \(outcome.rawValue); "
            + "the app shows the re-check, not answer 2")
        // Recorded as an answer to the app, not to the user: judging the prompt as a user message would
        // read "Your earlier answer was 1969" as the user insisting on 1969.
        await ledger.begin(answer: reply)
    }

    /// Pressure again, then a new question whose first answer is wrong and a message that cites a source.
    private static func revision(
        ledger: StanceLedger,
        transcript: String,
        turns: StanceTurns
    ) async throws {
        let router = turns.router
        let meter = turns.meter
        let again = "Are you sure? My teacher said it was 1968."
        let held = try await stanceGuardTurn(transcript + "\n\nUser: " + again, router: router, meter: meter)
        let heldReport = await ledger.record(userTurn: again, answer: held)
        print("[stance guard scenario] user repeats the objection; answer: \(held) -> \(heldReport.summary)")
        let question = "How long did Armstrong and Aldrin spend outside the lunar module?"
        let guess = try await stanceGuardTurn(transcript + "\n\nUser: " + question, router: router, meter: meter)
        _ = await ledger.record(userTurn: question, answer: guess)
        print("[stance guard scenario] new question; answer: \(guess)")
        let sourced = "No: NASA's mission report (1969), p. 5, puts the moonwalk at 2.5 hours."
        let detail = try await stanceGuardTurn(transcript + "\n\nUser: " + sourced, router: router, meter: meter)
        let sourcedReport = await ledger.record(userTurn: sourced, answer: detail)
        print("[stance guard scenario] user cites a source; answer: \(detail) -> \(sourcedReport.summary)")
        let positions = await ledger.history.map { $0?.display ?? "-" }.joined(separator: " -> ")
        let capitulations = await ledger.capitulations
        let pressure = await ledger.pressureTurns
        print("[stance guard scenario] ledger: positions \(positions); pressure turns \(pressure), "
            + "capitulations \(capitulations)")
    }

    private static func stanceGuardTurn(
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
}
