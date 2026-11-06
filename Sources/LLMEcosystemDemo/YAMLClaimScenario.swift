import Foundation
import ProviderGatewayKit
import TokenMeterKit
import YAMLClaimKit

/// The identifier the hundred-and-third scenario's turns bill against.
extension ProviderIdentifier {
    static let yamlClaimHost = ProviderIdentifier("yaml-claim-host")
}

extension EcosystemDemo {
    /// The hundred-and-third scenario: what an answer says about YAML, parsed and loaded as PyYAML would.
    ///
    /// `ProviderGatewayKit` carries four turns and `TokenMeterKit` meters them. The first answer gives a
    /// GitHub Actions workflow with `python-version: 3.10` unquoted, says it is read as the string "3.10",
    /// and shows a Python snippet reading `workflow["on"]`. `YAMLClaimKit` reads the value as YAML does
    /// (the float 3.1) and runs the snippet as PyYAML does (the key `on` became `True`, so the lookup raises
    /// `KeyError`), and its feedback gets a rewrite that holds. The follow-up loads a list of country codes
    /// with `NO` unquoted and claims it stays a string; asked again, the model repeats it, and the
    /// conversation's one `YAMLLedger` marks the repeat.
    static func runYAMLClaimScenario(meter: TokenMeter) async {
        do {
            let costBefore = await meter.totalCost()
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .yamlClaimHost, script: yamlClaimScript)
            ])
            let ledger = YAMLLedger()
            let question = "Write a CI workflow for Python 3.10, and show how to read its trigger in Python."
            print("[yaml claim scenario] user: \(question)")
            let first = try await yamlTurn(question, router: router, meter: meter)
            print("[yaml claim scenario] answer 1: \(flatYAML(first))")
            let report = await ledger.review(first)
            printYAMLFindings(report)

            let repair = question + "\n" + first + "\n" + (report.feedback ?? "")
            let second = try await yamlTurn(repair, router: router, meter: meter)
            print("[yaml claim scenario] answer 2 (after the feedback): \(flatYAML(second))")
            let fixed = await ledger.review(second)
            print("[yaml claim scenario] verdict \(fixed.verdict.rawValue): \(fixed.summary); the app shows answer 2")

            let followUp = "Can I list the deploy regions by country code without quotes?"
            print("[yaml claim scenario] user: \(followUp)")
            let third = try await yamlTurn(followUp, router: router, meter: meter)
            print("[yaml claim scenario] answer 3: \(flatYAML(third))")
            let loaded = await ledger.review(third)
            printYAMLFindings(loaded)

            let retry = followUp + "\n" + third + "\n" + (loaded.feedback ?? "")
            let fourth = try await yamlTurn(retry, router: router, meter: meter)
            print("[yaml claim scenario] answer 4 (after the feedback): \(flatYAML(fourth))")
            let again = await ledger.review(fourth)
            printYAMLFindings(again)
            if again.repeatedCount > 0 {
                print("[yaml claim scenario] repeated after a correction: no third request; the app shows "
                    + "answer 4 with the note")
            }
            let statistics = await ledger.statistics
            print("[yaml claim scenario] ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, "
                + "\(statistics.flagged) flagged, \(statistics.repeated) repeated")
            print("[yaml claim scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[yaml claim scenario] FAILED: \(error)")
        }
    }

    private static func flatYAML(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func printYAMLFindings(_ report: YAMLReport) {
        for finding in report.findings {
            let excerpt = flatYAML(finding.claim.excerpt)
            print("[yaml claim scenario]   \(finding.severity): \(excerpt) -> " + finding.explanation)
        }
        print("[yaml claim scenario] verdict \(report.verdict.rawValue) (\(report.summary)); "
            + "note: \(report.note ?? "-")")
    }

    private static let yamlClaimScript = [
        """
        ```yaml
        on: push
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/setup-python@v5
                with:
                  python-version: 3.10
        ```
        In YAML, `python-version: 3.10` is read as the string "3.10". To read the trigger:
        ```python
        import yaml
        workflow = yaml.safe_load(open(".github/workflows/ci.yml"))
        print(workflow["on"])  # push
        ```
        """,
        """
        ```yaml
        on: push
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/setup-python@v5
                with:
                  python-version: "3.10"
        ```
        Quoted, `python-version: "3.10"` is read as the string "3.10". PyYAML loads the key `on` as True:
        ```python
        import yaml
        workflow = yaml.safe_load(open(".github/workflows/ci.yml"))
        print(workflow[True])  # push
        ```
        """,
        """
        ```yaml
        regions: [GB, NO, SE]
        ```
        ```python
        import yaml
        config = yaml.safe_load(open("deploy.yml"))
        print(config["regions"])  # ['GB', 'NO', 'SE']
        ```
        """,
        """
        Checked again, the codes stay strings:
        ```yaml
        regions: [GB, NO, SE]
        ```
        ```python
        import yaml
        config = yaml.safe_load(open("deploy.yml"))
        print(config["regions"])  # ['GB', 'NO', 'SE']
        ```
        """
    ]

    private static func yamlTurn(
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
