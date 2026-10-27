import CalendarClaimKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the ninety-fifth scenario's turns bill against.
extension ProviderIdentifier {
    static let calendarClaimHost = ProviderIdentifier("calendar-claim-host")
}

extension EcosystemDemo {
    /// The ninety-fifth scenario: the calendar arithmetic in an answer, done again.
    ///
    /// A user asks when a 90-day trial that started on March 3, 2026 ends. `ProviderGatewayKit` carries
    /// the turn and `TokenMeterKit` meters it. The answer says June 2, 2026, a Tuesday: the weekday is
    /// right for that date and the date is wrong. `CalendarClaimKit` recomputes it, the report's feedback
    /// goes back to the model with June 1, and the rewrite holds. A follow-up names no year at all; the
    /// session carries 2026 from the first question, so "two weeks before June 1 is May 18, a Monday" is
    /// checked against the right year.
    static func runCalendarClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .calendarClaimHost, script: calendarClaimScript)
            ])
            let session = CalendarSession(checker: CalendarChecker(timeZone: .gmt))
            let question = "My 90-day trial started on March 3, 2026. When does it end, and what weekday is that?"
            print("[calendar claim scenario] user: \(question)")

            let first = try await calendarClaimTurn(question, router: router, meter: meter)
            let report = await session.review(answer: first, question: question, now: calendarClaimNow)
            print("[calendar claim scenario] answer 1: \(first)")
            for check in report.checks {
                print("[calendar claim scenario] \(check.status.rawValue): \(check.statement)"
                    + (check.status == .verified ? "" : " -> \(check.truth)"))
            }
            print("[calendar claim scenario] verdict \(report.verdict.rawValue); note: \(report.note ?? "-")")

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await calendarClaimTurn(repair, router: router, meter: meter)
            let fixed = await session.review(answer: second, question: question, now: calendarClaimNow)
            print("[calendar claim scenario] answer 2 (after the feedback): \(second)")
            print("[calendar claim scenario] verdict \(fixed.verdict.rawValue); the app shows answer 2")

            let followUp = "When should the reminder go out, two weeks before it ends?"
            let third = try await calendarClaimTurn(followUp, router: router, meter: meter)
            let carried = await session.review(answer: third, question: followUp, now: calendarClaimNow)
            print("[calendar claim scenario] user: \(followUp)")
            print("[calendar claim scenario] answer 3: \(third)")
            for check in carried.checks {
                print("[calendar claim scenario] \(check.status.rawValue): \(check.statement)")
            }
            print("[calendar claim scenario] year carried from turn 1: "
                + "\(await session.contextYear.map(String.init) ?? "none")")
            let totals = await session.totals
            print("[calendar claim scenario] session: \(totals.turns) turns, \(totals.checks) checks, "
                + "\(totals.verified) verified, \(totals.contradicted) contradicted")
            print("[calendar claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[calendar claim scenario] FAILED: \(error)")
        }
    }

    /// The clock the checks run against: Tuesday, October 27, 2026, 06:30 UTC.
    private static let calendarClaimNow = Date(timeIntervalSince1970: 1_793_082_600)

    private static let calendarClaimScript = [
        "Your trial ends 90 days later, on June 2, 2026, a Tuesday.",
        "Your trial ends on Monday, June 1, 2026, 90 days after March 3.",
        "Send it on May 18, a Monday: two weeks before June 1 is May 18."
    ]

    private static func calendarClaimTurn(
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
