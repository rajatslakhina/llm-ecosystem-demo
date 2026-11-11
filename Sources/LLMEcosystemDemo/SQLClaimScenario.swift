import Foundation
import ProviderGatewayKit
import SQLClaimKit
import TokenMeterKit

/// The identifier the hundred-and-fifth scenario's turns bill against.
extension ProviderIdentifier {
    static let sqlClaimHost = ProviderIdentifier("sql-claim-host")
}

extension EcosystemDemo {
    /// The hundred-and-fifth scenario: what an answer says its SQL returns, checked by running the SQL on the
    /// data the answer shows.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer creates a small
    /// `customers` table, filters it with `WHERE email = NULL`, and shows two customers coming back.
    /// `SQLClaimKit` runs the answer's SQL in a private in-memory SQLite database: no rows come back, because
    /// `= NULL` is never true, and its feedback gets a rewrite with `IS NULL` that holds. The follow-up lists
    /// every customer with their paid orders through a `LEFT JOIN` filtered in `WHERE`, which drops the
    /// customers with no paid order; asked again, the model repeats it, and the conversation's one `SQLLedger`
    /// marks the repeat.
    static func runSQLClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .sqlClaimHost, script: sqlClaimScript)
            ])
            let ledger = SQLLedger()
            let question = "Which customers have no email on file? Show the query and what it returns."
            print("[sql claim scenario] user: \(question)")
            let first = try await sqlTurn(question, router: router, meter: meter)
            print("[sql claim scenario] answer 1: \(flatSQL(first))")
            let report = await ledger.review(first)
            printSQLFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await sqlTurn(repair, router: router, meter: meter)
            print("[sql claim scenario] answer 2 (after the feedback): \(flatSQL(second))")
            let fixed = await ledger.review(second)
            print("[sql claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "Now list every customer with their paid order totals, including customers with none."
            print("[sql claim scenario] user: \(followUp)")
            let third = try await sqlTurn(followUp, router: router, meter: meter)
            print("[sql claim scenario] answer 3: \(flatSQL(third))")
            let joined = await ledger.review(third)
            printSQLFindings(joined)

            let retry = followUp + "\n" + third + "\n" + (joined.feedback ?? "")
            let fourth = try await sqlTurn(retry, router: router, meter: meter)
            print("[sql claim scenario] answer 4 (after the feedback): \(flatSQL(fourth))")
            let again = await ledger.review(fourth)
            printSQLFindings(again)
            if again.repeatedCount > 0 {
                print("[sql claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[sql claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[sql claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[sql claim scenario] FAILED: \(error)")
        }
    }

    private static func flatSQL(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printSQLFindings(_ report: SQLReport) {
        for finding in report.findings {
            print("[sql claim scenario]   \(finding.severity): \(finding.claim.excerpt) -> " + finding.explanation)
        }
        print("[sql claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let sqlClaimSchema = """
        CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT);
        INSERT INTO customers VALUES (1, 'Asha', 'asha@example.com'), (2, 'Ben', NULL), (3, 'Chen', NULL);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, total INTEGER, status TEXT);
        INSERT INTO orders VALUES (10, 1, 120, 'paid'), (11, 3, 45, 'refunded');
        """

    private static let sqlClaimScript = [
        """
        ```sql
        \(sqlClaimSchema)
        SELECT name FROM customers WHERE email = NULL;
        ```
        This returns:

        | name |
        |------|
        | Ben  |
        | Chen |
        """,
        """
        ```sql
        \(sqlClaimSchema)
        SELECT name FROM customers WHERE email IS NULL;
        ```
        This returns:

        | name |
        |------|
        | Ben  |
        | Chen |
        """,
        """
        ```sql
        \(sqlClaimSchema)
        SELECT c.name, o.total FROM customers c LEFT JOIN orders o ON o.customer_id = c.id
        WHERE o.status = 'paid' ORDER BY c.id;
        ```

        | name | total |
        |------|-------|
        | Asha | 120   |
        | Ben  | NULL  |
        | Chen | NULL  |
        """,
        """
        The LEFT JOIN keeps every customer:
        ```sql
        \(sqlClaimSchema)
        SELECT c.name, o.total FROM customers c LEFT JOIN orders o ON o.customer_id = c.id
        WHERE o.status = 'paid' ORDER BY c.id;
        ```

        | name | total |
        |------|-------|
        | Asha | 120   |
        | Ben  | NULL  |
        | Chen | NULL  |
        """
    ]

    private static func sqlTurn(
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
