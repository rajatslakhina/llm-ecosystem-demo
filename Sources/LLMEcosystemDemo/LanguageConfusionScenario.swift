import LanguageConfusionKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the ninety-sixth scenario's turns bill against.
extension ProviderIdentifier {
    static let languageConfusionHost = ProviderIdentifier("language-confusion-host")
}

extension EcosystemDemo {
    /// The ninety-sixth scenario: an answer in the language the user wrote in.
    ///
    /// A user asks in French what separates a list from a tuple. `LanguageSession` turns "you wrote in
    /// French" into a system line before the call, `ProviderGatewayKit` carries the turn and `TokenMeterKit`
    /// meters it. The answer still switches to English for the sentence that matters; `LanguageConfusionKit`
    /// finds it, the report's feedback gets a rewrite in French, and a three-word follow-up ("ok — et un
    /// set ?") is still expected in French because the session remembers the conversation's language.
    static func runLanguageConfusionScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .languageConfusionHost, script: languageConfusionScript)
            ])
            let session = LanguageSession()
            let question = "Quelle est la différence entre une liste et un tuple en Python ?"
            let hint = await session.expectation(for: question)?.instruction ?? ""
            print("[language confusion scenario] user: \(question)")
            print("[language confusion scenario] system line before the call: \(hint)")

            let first = try await languageConfusionTurn(hint + "\n" + question, router: router, meter: meter)
            let report = await session.review(answer: first, question: question)
            print("[language confusion scenario] answer 1: \(first)")
            printLanguageFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await languageConfusionTurn(repair, router: router, meter: meter)
            let fixed = await session.review(answer: second, question: question)
            print("[language confusion scenario] answer 2 (after the feedback): \(second)")
            print("[language confusion scenario] verdict \(fixed.verdict.rawValue); the app shows answer 2")

            let followUp = "ok — et un set ?"
            let expected = await session.expectation(for: followUp)
            print("[language confusion scenario] user: \(followUp)")
            print("[language confusion scenario] expected \(expected?.language.name ?? "none") "
                + "(\(expected?.source.rawValue ?? "-")): too short to identify, so the conversation's language")
            let third = try await languageConfusionTurn(followUp, router: router, meter: meter)
            let carried = await session.review(answer: third, question: followUp)
            print("[language confusion scenario] answer 3: \(third)")
            printLanguageFindings(carried)
            let totals = await session.totals
            print("[language confusion scenario] session: \(totals.turns) turns, \(totals.judgedSentences) sentences "
                + "judged, \(totals.wrongSentences) wrong, \(totals.strayWords) stray words")
            print("[language confusion scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[language confusion scenario] FAILED: \(error)")
        }
    }

    private static func printLanguageFindings(_ report: LanguageReport) {
        for sentence in report.sentences {
            let status = switch sentence.status {
            case .wrong(let language): "wrong (\(language.name))"
            case .expected: "ok"
            default: "not judged"
            }
            print("[language confusion scenario]   \(status): \(sentence.text)")
        }
        print("[language confusion scenario] verdict \(report.verdict.rawValue); note: \(report.note ?? "-")")
    }

    private static let languageConfusionScript = [
        "Une liste est modifiable, alors qu'un tuple ne l'est pas. "
            + "In practice, you should use a tuple when the data must not change.",
        "Une liste est modifiable, alors qu'un tuple ne l'est pas. "
            + "En pratique, utilisez un tuple quand les données ne doivent pas changer.",
        "A set stores unique values with no order, so checking whether it contains a value is fast."
    ]

    private static func languageConfusionTurn(
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
