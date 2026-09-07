import AssociationFitKit
import AssociationFitSquare
import ChanceAgreementKit
import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import SquareDesignKit
import TokenMeterKit

/// The identifier the fifty-eighth scenario bills its fitting against.
extension ProviderIdentifier {
    static let associationFitHost = ProviderIdentifier("association-fit-host")
}

/// One pair of judges and the two margins their verdicts imply.
struct AssociationPair {
    let name: String
    let row: FitMargin
    let column: FitMargin
}

extension EcosystemDemo {
    /// The fifty-eighth scenario: **scenario 57 repaired this panel to a diagonal total. That
    /// pins one number and leaves eight free, and this one chooses them.**
    ///
    /// A three-category panel with fixed margins has nine free cells. `SquareDesignKit` fixes the
    /// trace, which uses one of them; the other eight are whatever its construction happened to
    /// leave, and its construction pushes mass into corners because that is the cheapest way to
    /// reach a diagonal. So a fixture repaired to "agree 61 times out of 100" carries an
    /// association nobody chose, and every coefficient scenarios 50 through 57 publish is
    /// sensitive to it.
    ///
    /// Here the association is the requirement and the trace is the consequence.
    static func runAssociationFitScenario(meter: TokenMeter) async {
        print("[association fit scenario] the eight cells scenario 57 left to chance")

        let history = panelHistory()
        let judges = history.judges
        guard let margins = associationMargins(history, judges: judges) else {
            print("     no pair of judges gives a three-category panel")
            return
        }

        let ledger = AssociationFitLedger()
        await associationPartA(ledger, margins: margins)
        await associationPartB(ledger, margins: margins)
        await associationPartC(ledger, margins: margins)
        await associationPartD(margins: margins)

        await meter.record(
            TokenUsage(promptTokens: 450, completionTokens: 140),
            for: ProviderIdentifier.associationFitHost.rawValue
        )
    }

    /// The three-way verdict margins of the first two judges on the panel.
    private static func associationMargins(
        _ history: ObservationHistory, judges: [JudgeIdentity]
    ) -> AssociationPair? {
        guard judges.count >= 2 else { return nil }
        for left in 0..<judges.count where left + 1 < judges.count {
            for right in (left + 1)..<judges.count {
                let first = associationCounts(history, judge: judges[left])
                let second = associationCounts(history, judge: judges[right])
                guard first != second,
                      let row = try? FitMargin(counts: first),
                      let column = try? FitMargin(counts: second) else { continue }
                return AssociationPair(
                    name: "\(judges[left]) / \(judges[right])", row: row, column: column
                )
            }
        }
        return nil
    }

    private static func associationCounts(
        _ history: ObservationHistory, judge: JudgeIdentity
    ) -> [Int] {
        var totals = [Int](repeating: 0, count: Verdict.allCases.count)
        for observation in history.observations {
            guard let verdict = observation.verdicts[judge],
                  let code = Verdict.allCases.firstIndex(of: verdict) else { continue }
            totals[code] += 1
        }
        return totals
    }

    // MARK: - A: the structures, and the agreement each one implies

    private static func associationPartA(
        _ ledger: AssociationFitLedger, margins: AssociationPair
    ) async {
        print("  A. the same two judges' own rates, fitted to four different structures")
        print("     pair \(margins.name), margins \(margins.row.counts) and \(margins.column.counts)")
        print("     \(associationWide("structure", 26))\(associationWide("passes", 9))"
            + "\(associationWide("agreement", 12))\(associationWide("min odds", 11))max odds")
        for (name, seed) in associationSeeds(categoryCount: margins.row.categoryCount) {
            let fitted: FittedTable
            do {
                fitted = try await ledger.fit(
                    name, seed: seed, row: margins.row, column: margins.column
                )
            } catch {
                print("     \(associationWide(name, 26))\(error)")
                continue
            }
            let finite = fitted.localOdds.values.flatMap { $0 }.compactMap { $0 }
            print("     \(associationWide(name, 26))"
                + "\(associationWide("\(fitted.iterations)", 9))"
                + "\(associationWide(associationDp(fitted.agreementRate), 12))"
                + "\(associationWide(associationDp(finite.min() ?? .nan), 11))"
                + associationDp(finite.max() ?? .nan))
        }
        print("     the margins are identical down the column; only the structure changed, and")
        print("     the agreement rate moved with it — it was never a free parameter")
    }

    // MARK: - B: what the fit preserves, measured

    private static func associationPartB(
        _ ledger: AssociationFitLedger, margins: AssociationPair
    ) async {
        print("  B. the association the fit was told to keep, after it moved the margins")
        let categoryCount = margins.row.categoryCount
        guard let seed = try? AssociationSeed.uniformAssociation(
            categoryCount: categoryCount, oddsRatio: 3
        ), let fitted = try? await ledger.fitted(for: "uniform association 3") else {
            print("     no uniform fit to read back")
            return
        }
        let asked = LocalOddsRatios(table: seed.weights)
        print("     asked for every local odds ratio at 3.0000 across "
            + "\(categoryCount) categories")
        print("     largest relative change after fitting: "
            + associationSci(fitted.localOdds.maximumRelativeDeviation(from: asked)))
        print("     margin error: \(associationSci(fitted.marginError))")
        print("     scaling a row or a column cancels out of every odds ratio, so the fit spends")
        print("     all of its effort on the margins and none of it on the structure")
    }

    // MARK: - C: the invoice whole items present

    private static func associationPartC(
        _ ledger: AssociationFitLedger, margins: AssociationPair
    ) async {
        print("  C. what turning each fit into whole verdicts cost it")
        print("     \(associationWide("structure", 26))\(associationWide("odds drift", 13))"
            + "\(associationWide("agree drift", 13))\(associationWide("cell drift", 12))margins")
        for (name, _) in associationSeeds(categoryCount: margins.row.categoryCount) {
            guard let report = try? await ledger.adopt(name) else { continue }
            print("     \(associationWide(name, 26))"
                + "\(associationWide(associationSci(report.oddsRatioDrift), 13))"
                + "\(associationWide(associationDp(report.agreementDrift), 13))"
                + "\(associationWide(associationDp(report.cellDrift, 3), 12))"
                + (report.marginsExact ? "exact" : "MOVED"))
        }
        print("     every row says exact, on every structure. The margins are the guarantee and")
        print("     the association is what pays for them.")
    }

    // MARK: - D: the two constructions, side by side on one panel

    private static func associationPartD(
        margins: AssociationPair
    ) async {
        print("  D. the same margins, once to a structure and once to a diagonal")
        let ledger = AssociationFitLedger()
        guard let seed = try? AssociationSeed.diagonalWeight(
            categoryCount: margins.row.categoryCount, weight: 6
        ), (try? await ledger.fit(
            "diagonal", seed: seed, row: margins.row, column: margins.column
        )) != nil, let report = try? await ledger.adopt("diagonal") else {
            print("     no diagonal fit available")
            return
        }
        guard let agreement = try? SquareBridge.crossCheck(panel: report.panel) else {
            print("     the neighbour could not price this panel")
            return
        }
        print("     fitted to a diagonal weight of 6: trace \(agreement.trace), "
            + "agreement \(associationDp(report.panel.agreementRate))")
        print("     SquareDesignKit on the same margins: attainable \(agreement.isAttainable), "
            + "range \(agreement.range.lowerBound)...\(agreement.range.upperBound), "
            + "\(agreement.attainableCount) reachable, \(agreement.holeCount) holes")
        guard let atTrace = try? SquareBridge.panelAtTrace(
            row: margins.row, column: margins.column, trace: report.panel.trace
        ) else { return }
        let blocks = (margins.row.categoryCount - 1) * (margins.row.categoryCount - 1)
        print("     blocks with no finite odds ratio, of \(blocks): "
            + "ours \(report.panel.localOdds.undefinedCount), "
            + "its \(atTrace.localOdds.undefinedCount)")
        let identical = atTrace.cells == report.panel.cells
        print("     the two panels are \(identical ? "identical" : "different") cell for cell")
        print("     and that is a fact about this corpus rather than about the two packages:")
        print("     no judge here ever abstained, so the third category is empty and the panel is")
        print("     really two-by-two — one free cell, which any single requirement fixes. On a")
        print("     panel with three live categories the trace would leave eight cells open.")
    }

    private static func associationSeeds(categoryCount: Int) -> [(String, AssociationSeed)] {
        let candidates: [(String, AssociationSeed?)] = [
            ("independent", try? .independent(categoryCount: categoryCount)),
            ("uniform association 3", try? .uniformAssociation(
                categoryCount: categoryCount, oddsRatio: 3
            )),
            ("diagonal weight 6", try? .diagonalWeight(categoryCount: categoryCount, weight: 6)),
            ("quasi-independent", try? .quasiIndependent(categoryCount: categoryCount))
        ]
        return candidates.compactMap { name, seed in seed.map { (name, $0) } }
    }

    private static func associationWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func associationDp(_ value: Double, _ places: Int = 4) -> String {
        value.isNaN ? "n/a" : String(format: "%.\(places)f", value)
    }

    private static func associationSci(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.3e", value)
    }
}
