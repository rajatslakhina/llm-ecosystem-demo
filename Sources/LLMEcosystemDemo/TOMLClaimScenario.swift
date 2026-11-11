import Foundation
import ProviderGatewayKit
import TokenMeterKit
import TOMLClaimKit

/// The identifier the hundred-and-fourth scenario's turns bill against.
extension ProviderIdentifier {
    static let tomlClaimHost = ProviderIdentifier("toml-claim-host")
}

extension EcosystemDemo {
    /// The hundred-and-fourth scenario: what an answer says about TOML, parsed and loaded as Python's
    /// `tomllib` would.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer sets up mypy
    /// in `pyproject.toml` with `python_version = 3.10` unquoted, says it is read as the string "3.10", and
    /// reads it back with `tomllib.load` on a file opened in text mode. `TOMLClaimKit` reads the value as
    /// TOML does (the float 3.1) and runs the snippet as `tomllib` does (a text-mode file raises
    /// `TypeError`), and its feedback gets a rewrite that holds. The follow-up gives Poetry dependencies
    /// with `python = ^3.10` unquoted and calls the block valid TOML; asked again, the model repeats it, and
    /// the conversation's one `TOMLLedger` marks the repeat.
    static func runTOMLClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .tomlClaimHost, script: tomlClaimScript)
            ])
            let ledger = TOMLLedger()
            let question = "Set mypy to Python 3.10 in pyproject.toml, and show how to read the setting in Python."
            print("[toml claim scenario] user: \(question)")
            let first = try await tomlTurn(question, router: router, meter: meter)
            print("[toml claim scenario] answer 1: \(flatTOML(first))")
            let report = await ledger.review(first)
            printTOMLFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await tomlTurn(repair, router: router, meter: meter)
            print("[toml claim scenario] answer 2 (after the feedback): \(flatTOML(second))")
            let fixed = await ledger.review(second)
            print("[toml claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "Add Python and requests to the Poetry dependencies."
            print("[toml claim scenario] user: \(followUp)")
            let third = try await tomlTurn(followUp, router: router, meter: meter)
            print("[toml claim scenario] answer 3: \(flatTOML(third))")
            let dependencies = await ledger.review(third)
            printTOMLFindings(dependencies)

            let retry = followUp + "\n" + third + "\n" + (dependencies.feedback ?? "")
            let fourth = try await tomlTurn(retry, router: router, meter: meter)
            print("[toml claim scenario] answer 4 (after the feedback): \(flatTOML(fourth))")
            let again = await ledger.review(fourth)
            printTOMLFindings(again)
            if again.repeatedCount > 0 {
                print("[toml claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[toml claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[toml claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[toml claim scenario] FAILED: \(error)")
        }
    }

    private static func flatTOML(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printTOMLFindings(_ report: TOMLReport) {
        for finding in report.findings {
            let excerpt = flatTOML(finding.claim.excerpt)
            print("[toml claim scenario]   \(finding.severity): \(excerpt) -> " + finding.explanation)
        }
        print("[toml claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let tomlClaimScript = [
        """
        ```toml
        [tool.mypy]
        python_version = 3.10
        strict = true
        ```
        In TOML, `python_version = 3.10` is read as the string "3.10". To read it back:
        ```python
        import tomllib
        with open("pyproject.toml") as f:
            data = tomllib.load(f)
        print(data["tool"]["mypy"]["python_version"])  # 3.10
        ```
        """,
        """
        ```toml
        [tool.mypy]
        python_version = "3.10"
        strict = true
        ```
        Quoted, `python_version = "3.10"` is read as the string "3.10". `tomllib` needs a binary file:
        ```python
        import tomllib
        with open("pyproject.toml", "rb") as f:
            data = tomllib.load(f)
        print(data["tool"]["mypy"]["python_version"])  # 3.10
        ```
        """,
        """
        This is valid TOML:
        ```toml
        [tool.poetry.dependencies]
        python = ^3.10
        requests = "^2.31"
        ```
        """,
        """
        Checked again, this is valid TOML:
        ```toml
        [tool.poetry.dependencies]
        python = ^3.10
        requests = "^2.31"
        ```
        """
    ]

    private static func tomlTurn(
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
