import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import SignalDependenceKit
import TokenMeterKit

/// The identifier the forty-ninth scenario bills its audit against.
extension ProviderIdentifier {
    static let effectiveVoteHost = ProviderIdentifier("effective-vote-host")
}

extension EcosystemDemo {
    /// The forty-ninth scenario: **scenario 37 wrote down how dependent these judges are. Nobody
    /// ever checked.**
    ///
    /// Scenario 37 deflates a four-judge panel using a `DependenceGraph` whose strengths are
    /// declared: `answerability` and `morphology` share a heuristic, `independence` and `temporal`
    /// share an input. Those declarations are correct in kind and have never been correct in
    /// degree, because nothing in this demo could measure a degree.
    ///
    /// This runs the same four analysers over ninety-six constructed corpora, labels each one by
    /// how it was built rather than by what any judge said, and measures what the judges actually
    /// did. Two of the declarations turn out to be wrong in opposite directions, and the pair
    /// scenario 37 never declared at all is the most entangled pair on the panel.
    static func runEffectiveVoteScenario(meter: TokenMeter) async {
        print("[effective vote scenario] the declared dependence graph, finally measured")

        let history = panelHistory()
        votePartA(history)
        let estimate = EffectiveVoteEstimator(basis: .errorAgreement).estimate(history, stratum: .all)
        votePartB(estimate)
        votePartC(estimate)
        votePartD(estimate)
        votePartE(history)

        await meter.record(
            TokenUsage(promptTokens: 610, completionTokens: 180),
            for: ProviderIdentifier.effectiveVoteHost.rawValue
        )
    }

    // MARK: - A: what the panel did

    private static func votePartA(_ history: ObservationHistory) {
        print("  A. four real analysers over \(history.count) constructed corpora")
        for judge in panelJudges {
            let votes = history.observations.compactMap { $0.verdict(of: judge) }
            let affirm = votes.filter { $0 == .affirm }.count
            let deny = votes.filter { $0 == .deny }.count
            let abstain = votes.filter { $0 == .abstain }.count
            print("     \(judge.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0))"
                + "affirm \(affirm)  deny \(deny)  abstain \(abstain)")
        }
        print("     labels come from how each corpus was built, not from any judge: "
            + "\(history.observations.filter { $0.truth == .affirm }.count) of "
            + "\(history.count) are genuinely safe to answer")
    }

    // MARK: - B: what they actually shared

    private static func votePartB(_ estimate: EffectiveVoteEstimate) {
        print("  B. measured agreement between mistakes, every pair")
        for association in estimate.associations.sorted(by: { ($0.coefficient ?? -2) > ($1.coefficient ?? -2) }) {
            print("     \(association.summary)")
        }
    }

    // MARK: - C: declared against measured

    private static func votePartC(_ estimate: EffectiveVoteEstimate) {
        print("  C. scenario 37's declarations, held against that")
        let gaps = estimate.discrepancies(against: declaredPanelStrengths())
        for gap in gaps.sorted(by: { $0.excess > $1.excess }) {
            print("     \(gap.summary)")
        }
        let undeclared = estimate.measuredDependencies()
            .filter { declaredPanelStrengths()[$0.pair] == nil }
            .sorted { $0.strength > $1.strength }
        if let worst = undeclared.first, abs(worst.strength) > 0.01 {
            print("     strongest pair nobody declared -> \(worst.summary)")
        } else {
            print("     every pair nobody declared measured flat, so the graph is missing no edge here")
        }
        print("     Both declarations are wrong, and in opposite directions. The shared heuristic")
        print("     is worse than written down: these two are not correlated, they are the same")
        print("     judge on this corpus, and swapping the matcher changed nothing. The shared")
        print("     input is better: reading the same document ids produced no shared mistake.")
    }

    // MARK: - D: two ways to count the same four judges

    private static func votePartD(_ estimate: EffectiveVoteEstimate) {
        let graph = DependenceGraph(edges: [
            DependenceEdge("answerability", "morphology", mechanism: .sharedHeuristic),
            DependenceEdge("independence", "temporal", mechanism: .sharedInput)
        ])
        let declared = graph.assess(panelJudges.map { DependenceOrigin($0.rawValue) })
        print("  D. effective votes, declared and measured")
        print(String(format: "     scenario 37, from the declared graph   %.2f of %d",
                     declared.effectiveVoices, declared.nominalCount))
        if let measured = estimate.effectiveVotes {
            print(String(format: "     scenario 49, from what they did        %.2f of %d",
                         measured, estimate.nominalJudges))
        }
        print("     The two numbers answer the same question from opposite ends. One is what the")
        print("     architecture says the panel should be worth; the other is what it was worth.")
    }

    // MARK: - E: the audit, and the stratum that cannot be read naively

    private static func votePartE(_ history: ObservationHistory) {
        let audit = EffectiveVoteEstimator(
            basis: .errorAgreement,
            policy: IntervalWidthPolicy(minimumObservations: 20)
        ).audit(history)
        print("  E. the audit: every decision, and the ones one vote could flip")
        for line in audit.lines {
            print("     \(line)")
        }
        voteSelectionNote(history)
    }

    /// The pivotal reading looks like good news and is an artefact. Showing it is the point.
    private static func voteSelectionNote(_ history: ObservationHistory) {
        let loosened = EffectiveVoteEstimator(
            basis: .errorAgreement,
            policy: IntervalWidthPolicy(
                minimumObservations: 20,
                maximumIntervalWidth: 12,
                rationale: "deliberately loosened so the comparison can be shown at all"
            )
        ).audit(history)
        print("     the strict policy refused the overall side, so the same audit again, loosened")
        print("     purely to make the comparison printable:")
        print("       \(loosened.comparison.summary)")
        print("     Read the pivotal figure literally and this panel is perfectly independent")
        print("     exactly where one vote decides, which is not credible. Selecting a one-vote")
        print("     margin conditions on the sum of the votes being correlated, so it drags the")
        print("     measurement down on its own. Only the opposite sign would have been a finding.")
    }
}
