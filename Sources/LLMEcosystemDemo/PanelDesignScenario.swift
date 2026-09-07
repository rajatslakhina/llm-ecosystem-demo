import ChanceAgreementKit
import EffectiveVoteKit
import Foundation
import PanelDesignKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the fifty-sixth scenario bills its design work against.
extension ProviderIdentifier {
    static let panelDesignHost = ProviderIdentifier("panel-design-host")
}

extension EcosystemDemo {
    /// The fifty-sixth scenario: **scenario 55 found that this demo's panel is fully crossed and
    /// therefore carries exactly no association. This one measures that as a property of the
    /// design, refuses to certify the fixture, and builds the panel the last six scenarios have
    /// needed.**
    ///
    /// `PanelSpec.all` enumerates every combination of four axes over two phrasings. That makes
    /// the history reproducible on every machine, which is why it was built that way, and it also
    /// makes every joint count the product of its marginals — so the coefficients, intervals,
    /// corrections and thresholds scenarios 50 through 55 publish are all estimating a quantity
    /// whose true value is nil. Nothing above is wrong. The *fixture* cannot exercise what five
    /// scenarios exist to measure.
    static func runPanelDesignScenario(meter: TokenMeter) async {
        print("[panel design scenario] the fixture five scenarios have been computing over")

        let history = panelHistory()
        let judges = history.judges
        guard let panel = designPanel(history, judges: judges) else {
            print("     no panel to diagnose")
            return
        }

        let ledger = DesignLedger()
        await ledger.record("corpus", panel: panel)

        await designPartA(ledger, judges: judges)
        designPartB(panel, judges: judges)
        await designPartC(ledger, panel: panel, judges: judges)
        await designPartD(ledger, panel: panel)

        await meter.record(
            TokenUsage(promptTokens: 420, completionTokens: 130),
            for: ProviderIdentifier.panelDesignHost.rawValue
        )
    }

    /// The judges' verdicts as a binary affirm grid.
    ///
    /// Binary on purpose. `PanelDesignKit` constructs two-category fixtures and prices any number,
    /// and affirm / not-affirm is the grading that makes "did this gate let the turn through"
    /// answerable at all.
    private static func designPanel(
        _ history: ObservationHistory, judges: [JudgeIdentity]
    ) -> PanelMatrix? {
        let labels = judges.map { judge in
            history.observations.map { $0.verdicts[judge] == .affirm ? 0 : 1 }
        }
        return try? PanelMatrix(labels: labels, categoryCount: 2)
    }

    // MARK: - A: the diagnosis, and where the refusal actually lands

    /// The whole-panel reading passes, and it should not be trusted for that.
    ///
    /// Two things came out of this that were not the expected answer. **The affirm grid of a
    /// fully crossed design is not itself fully crossed**: `PanelSpec.all` crosses four *axes*,
    /// and these four judges are functions of those axes rather than the axes themselves, so the
    /// sixteen judge combinations do not occur equally often. And the panel is not structurally
    /// null overall — because `answerability` and `morphology` agree on every item, which is one
    /// judge counted twice. **Every pair of genuinely distinct judges reads exactly zero**, and a
    /// whole-panel test is rescued by the duplicate. The pairs are the question.
    private static func designPartA(_ ledger: DesignLedger, judges: [JudgeIdentity]) async {
        print("  A. what the corpus can carry, before any coefficient is taken off it")
        guard let diagnosis = try? await ledger.diagnosis(for: "corpus") else {
            print("     no diagnosis")
            return
        }
        print("     \(diagnosis.judgeCount) judges, \(diagnosis.itemCount) items, "
            + "\(diagnosis.deviations.count) distinct pairs")
        print("     fully crossed        \(diagnosis.isFullyCrossed)   "
            + "(the affirm grid is a function of the axes, not the axes)")
        print("     largest |obs - exp|  \(designDp(diagnosis.maximumPairDeviation, 6))")
        print("     structurally null    \(diagnosis.isStructurallyNull)")
        var exactlyNull = 0
        for deviation in diagnosis.deviations {
            let identical = panelLabelsMatch(diagnosis, deviation)
            if deviation.deviation == 0 { exactlyNull += 1 }
            let names = "\(judges[deviation.first]) / \(judges[deviation.second])"
            print("     \(designWide(names, 34))"
                + "agree \(designDp(deviation.agreementRate))  "
                + "kappa \(designDp(deviation.cohenKappa ?? .nan))  "
                + "dev \(designDp(deviation.deviation, 6))"
                + (identical ? "   (one judge twice)" : ""))
        }
        print("     \(exactlyNull) of \(diagnosis.deviations.count) pairs sit at exactly zero; the "
            + "one that does not is a duplicate")
        await designCertifyPairs(ledger, diagnosis: diagnosis, judges: judges)
    }

    /// `certify` on the whole panel, then on each pair on its own.
    ///
    /// The whole panel passes. Every pair of distinct judges refuses. That difference is the
    /// finding: `isStructurallyNull` over a multi-judge panel asks whether *any* pair carries
    /// something, and one duplicated judge is enough to answer yes.
    private static func designCertifyPairs(
        _ ledger: DesignLedger, diagnosis: DesignDiagnosis, judges: [JudgeIdentity]
    ) async {
        await designAttempt("certify the whole panel") { _ = try await ledger.certify("corpus") }
        guard let panel = try? await ledger.panel(for: "corpus") else { return }
        for deviation in diagnosis.deviations {
            let names = "certify \(judges[deviation.first]) / \(judges[deviation.second])"
            await designAttempt(names) {
                let pair = try PanelMatrix(
                    labels: [panel.labels[deviation.first], panel.labels[deviation.second]],
                    categoryCount: 2
                )
                _ = try DesignDiagnosis(panel: pair).certify()
            }
        }
    }

    private static func panelLabelsMatch(
        _ diagnosis: DesignDiagnosis, _ deviation: PairDeviation
    ) -> Bool {
        deviation.agreementRate == 1
    }

    // MARK: - B: the range and the lattice these judges' own rates impose

    private static func designPartB(_ panel: PanelMatrix, judges: [JudgeIdentity]) {
        print("  B. the agreement rates these marginals allow, and the ones that do not exist")
        print("     \(designWide("pair", 34))\(designWide("a+", 6))\(designWide("b+", 6))"
            + "\(designWide("floor", 9))\(designWide("ceiling", 9))\(designWide("step", 6))exist / in range")
        for left in 0..<panel.judgeCount where left + 1 < panel.judgeCount {
            for right in (left + 1)..<panel.judgeCount {
                guard let first = try? panel.margin(left),
                      let second = try? panel.margin(right),
                      let range = try? AttainableAgreement(first: first, second: second) else { continue }
                let exist = (range.attainableCounts ?? []).count
                let span = range.upperCount - range.lowerCount + 1
                print("     \(designWide("\(judges[left]) / \(judges[right])", 34))"
                    + "\(designWide("\(first.counts[0])", 6))\(designWide("\(second.counts[0])", 6))"
                    + "\(designWide(designDp(range.lower), 9))\(designWide(designDp(range.upper), 9))"
                    + "\(designWide(range.step.map(String.init) ?? "-", 6))\(exist) / \(span)")
            }
        }
        print("     a fixture asked for a rate off that lattice is asked for a panel that does not")
        print("     exist; asked for one below the floor, for a panel these two judges forbid")
    }

    // MARK: - C: the panel the last six scenarios have needed

    /// Same two marginals, real association put in on purpose, and the coefficient re-taken.
    ///
    /// This is the point of the whole scenario. `ChanceAgreementKit` is handed the same pair of
    /// judges twice: once as the corpus built them, once as a fixture designed to carry an odds
    /// ratio of six. The judges' own rates are identical in both. Only the pairing changes.
    private static func designPartC(
        _ ledger: DesignLedger, panel: PanelMatrix, judges: [JudgeIdentity]
    ) async {
        print("  C. the same two judges, on a fixture that can carry an association")
        guard let pair = designStrongestBinaryPair(panel) else {
            print("     no pair with two live categories on both sides")
            return
        }
        let names = "\(judges[pair.0]) / \(judges[pair.1])"
        guard let built = try? await ledger.replacement(
            for: "corpus", pair: pair, target: .oddsRatio(6), seed: 20_260_907
        ) else {
            print("     \(names): no replacement could be built")
            return
        }
        _ = try? await ledger.adopt("designed", construction: built, seed: 20_260_907)
        print("     pair \(names), marginals held at "
            + "\(built.table.rowMargin.counts[0]) and \(built.table.columnMargin.counts[0]) of "
            + "\(built.table.itemCount)")
        print("     built table \(built.table.cells)   "
            + "snapped \(designDp(built.snapDistance, 6)) off the requested rate")
        await designCompare(original: panel, built: built, pair: pair, names: names)
    }

    private static func designCompare(
        original: PanelMatrix, built: BinaryConstruction, pair: (Int, Int), names: String
    ) async {
        guard let asBuilt = try? original.table(pair.0, pair.1) else { return }
        let corpusPair = try? LabelPair(
            first: original.labels[pair.0], second: original.labels[pair.1], categoryCount: 2
        )
        let designed = PanelRealization(table: built.table, seed: 20_260_907)
        let designedPair = try? LabelPair(
            first: designed.first, second: designed.second, categoryCount: 2
        )
        print("     \(designWide("fixture", 22))\(designWide("agree", 9))\(designWide("kappa", 9))"
            + "\(designWide("null sd", 10))\(designWide("deviate", 10))p")
        await designRow("as the corpus built it", corpusPair)
        await designRow("designed, odds ratio 6", designedPair)
        print("     odds ratio as built \(designDp((try? asBuilt.oddsRatio()) ?? .nan))"
            + "   designed \(designDp((try? built.table.oddsRatio()) ?? .nan))")
        print("     both rows are the same two judges at the same rates. The first cannot show a")
        print("     coefficient because there is none to show; the second is a fixture, not a finding.")
    }

    private static func designRow(_ label: String, _ pair: LabelPair?) async {
        guard let pair else {
            print("     \(designWide(label, 22))unavailable")
            return
        }
        let ledger = ChanceLedger()
        await ledger.record("row", pair: pair)
        guard let reading = try? await ledger.baseline(for: "row") else {
            print("     \(designWide(label, 22))refused")
            return
        }
        print("     \(designWide(label, 22))"
            + "\(designWide(designDp(pair.observedAgreement), 9))"
            + "\(designWide(designDp(reading.coefficient), 9))"
            + "\(designWide(designDp(reading.nullStandardDeviation), 10))"
            + "\(designWide(designDp(reading.standardizedDeviate, 3), 10))"
            + designSci(reading.oneSidedProbability))
    }

    /// The first pair whose two judges both used both categories.
    private static func designStrongestBinaryPair(_ panel: PanelMatrix) -> (Int, Int)? {
        for left in 0..<panel.judgeCount where left + 1 < panel.judgeCount {
            for right in (left + 1)..<panel.judgeCount {
                guard let first = try? panel.margin(left), let second = try? panel.margin(right),
                      !first.isDegenerate, !second.isDegenerate,
                      first.counts != second.counts else { continue }
                return (left, right)
            }
        }
        return nil
    }

    // MARK: - D: what this package refuses on this panel

    private static func designPartD(_ ledger: DesignLedger, panel: PanelMatrix) async {
        print("  D. refusals this corpus actually produces")
        await designAttempt("replace using one judge twice") {
            _ = try await ledger.replacement(
                for: "corpus", pair: (0, 0), target: .independence, seed: 1
            )
        }
        await designAttempt("n - 1 agreements, identical marginals") {
            guard let first = try? panel.margin(0) else { return }
            let range = try AttainableAgreement(first: first, second: first)
            _ = try range.snap(rate: Double(panel.itemCount - 1) / Double(panel.itemCount))
            let builder = try BinaryPanelBuilder(first: first, second: first)
            _ = try builder.table(diagonalTotal: panel.itemCount - 1)
        }
        await designAttempt("an agreement rate below the floor") {
            guard let first = try? panel.margin(0), let second = try? panel.margin(1) else { return }
            let builder = try BinaryPanelBuilder(first: first, second: second)
            _ = try builder.table(for: .agreementRate(0.0))
        }
        print("     the second one is the general form of the two-category step: identical marginals")
        print("     forbid a single disagreement, so n - 1 agreements is a panel that cannot exist")
    }

    private static func designAttempt(_ label: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            print("     \(designWide(label, 40))no refusal")
        } catch {
            print("     \(designWide(label, 40))\(error)")
        }
    }

    private static func designWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func designDp(_ value: Double, _ places: Int = 4) -> String {
        value.isNaN ? "n/a" : String(format: "%.\(places)f", value)
    }

    private static func designSci(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.2e", value)
    }
}
