import Foundation
import JSONClaimKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the hundred-and-second scenario's turns bill against.
extension ProviderIdentifier {
    static let jsonClaimHost = ProviderIdentifier("json-claim-host")
}

extension EcosystemDemo {
    /// The hundred-and-second scenario: what an answer says about JSON, parsed and run.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer gives a
    /// webhook body with a trailing comma in a block labeled `json`, and says `JSON.stringify` sends the
    /// `undefined` secret as `null`. `JSONClaimKit` parses the block (naming the comma's line and column)
    /// and runs the `JSON.stringify` call, and its feedback gets a rewrite that holds. The follow-up reads
    /// the webhook id back with `JSON.parse` and claims the 2^53-plus integer survives; asked again, the
    /// model repeats it, and the conversation's one `JSONLedger` marks the repeat.
    static func runJSONClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .jsonClaimHost, script: jsonClaimScript)
            ])
            let ledger = JSONLedger()
            let question = "What body do I POST to create the webhook, and what does JSON.stringify send?"
            print("[json claim scenario] user: \(question)")
            let first = try await jsonTurn(question, router: router, meter: meter)
            print("[json claim scenario] answer 1: \(flatJSON(first))")
            let report = await ledger.review(first)
            printJSONFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await jsonTurn(repair, router: router, meter: meter)
            print("[json claim scenario] answer 2 (after the feedback): \(flatJSON(second))")
            let fixed = await ledger.review(second)
            print("[json claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "How do I read the new webhook's id from the response?"
            print("[json claim scenario] user: \(followUp)")
            let third = try await jsonTurn(followUp, router: router, meter: meter)
            print("[json claim scenario] answer 3: \(flatJSON(third))")
            let parsed = await ledger.review(third)
            printJSONFindings(parsed)

            let retry = followUp + "\n" + third + "\n" + (parsed.feedback ?? "")
            let fourth = try await jsonTurn(retry, router: router, meter: meter)
            print("[json claim scenario] answer 4 (after the feedback): \(flatJSON(fourth))")
            let again = await ledger.review(fourth)
            printJSONFindings(again)
            if again.repeatedCount > 0 {
                print("[json claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[json claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[json claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[json claim scenario] FAILED: \(error)")
        }
    }

    private static func flatJSON(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printJSONFindings(_ report: JSONReport) {
        for finding in report.findings {
            let excerpt = flatJSON(finding.claim.excerpt)
            print("[json claim scenario]   \(finding.severity): \(excerpt) -> " + finding.explanation)
        }
        print("[json claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let jsonClaimScript = [
        """
        POST this body:
        ```json
        {
          "url": "https://example.com/hook",
          "events": ["order.created"],
        }
        ```
        From JavaScript:
        ```javascript
        const payload = { url: "https://example.com/hook", events: ["order.created"], secret: undefined };
        JSON.stringify(payload)  // '{"url":"https://example.com/hook","events":["order.created"],"secret":null}'
        ```
        """,
        """
        POST this body (no comma after the last member):
        ```json
        {
          "url": "https://example.com/hook",
          "events": ["order.created"]
        }
        ```
        From JavaScript, `secret: undefined` is left out:
        ```javascript
        const payload = { url: "https://example.com/hook", events: ["order.created"], secret: undefined };
        JSON.stringify(payload)  // '{"url":"https://example.com/hook","events":["order.created"]}'
        ```
        """,
        """
        ```javascript
        const body = '{"id": 9007199254740993, "status": "active"}';
        JSON.parse(body).id  // 9007199254740993
        ```
        """,
        """
        Checked again:
        ```javascript
        const body = '{"id": 9007199254740993, "status": "active"}';
        JSON.parse(body).id  // 9007199254740993
        ```
        """
    ]

    private static func jsonTurn(
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
