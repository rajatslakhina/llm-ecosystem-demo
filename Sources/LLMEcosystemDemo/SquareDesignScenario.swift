import ChanceAgreementKit
import EffectiveVoteKit
import Foundation
import PanelDesignKit
import ProviderGatewayKit
import SquareDesignKit
import TokenMeterKit

/// The identifier the fifty-seventh scenario bills its construction against.
extension ProviderIdentifier {
    static let squareDesignHost = ProviderIdentifier("square-design-host")
}

extension EcosystemDemo {
    /// The fifty-seventh scenario: **scenario 56 diagnosed this corpus as structurally null and
    /// then could only repair it two categories at a time. These judges cast three-way verdicts.
    /// This one repairs the panel they actually produced.**
    ///
    /// `PanelDesignKit` prices the attainable agreement range exactly at every category count and
    /// then stops: `admits(count:)` returns `nil` above two categories and `BinaryPanelBuilder`
    /// throws `constructionRequiresBinary`, on the grounds that the general case is a
    /// transportation problem with a forbidden diagonal and a prescribed trace. It is, and it has
    /// a closed form. `SquareDesignKit` is that closed form, so every question scenario 56 left
    /// open on this panel is answerable here — including which counts inside the range do not
    /// exist, which is a question nothing in this demo could previously ask.
    static func runSquareDesignScenario(meter: TokenMeter) async {
        print("[square design scenario] the three-way panel scenario 56 could only repair in binary")

        let history = panelHistory()
        let judges = history.judges
        let pairs = squarePairs(history, judges: judges)
        guard let sample = pairs.first else {
            print("     no pair of judges on this panel admits a square design")
            return
        }

        squarePartA(pairs)
        squarePartB(sample)
        await squarePartC(sample)
        squarePartD(pairs)

        await meter.record(
            TokenUsage(promptTokens: 440, completionTokens: 150),
            for: ProviderIdentifier.squareDesignHost.rawValue
        )
    }

    // MARK: - the corpus, as the three-way verdicts these judges cast

    private struct SquarePair {
        let key: String
        let first: [Int]
        let second: [Int]
        let row: LabelMargin
        let column: LabelMargin
        let priced: AttainableTrace
    }

    private static func squarePairs(
        _ history: ObservationHistory, judges: [JudgeIdentity]
    ) -> [SquarePair] {
        var built: [SquarePair] = []
        for left in 0..<judges.count where left + 1 < judges.count {
            for right in (left + 1)..<judges.count {
                let first = squareCodes(history, judge: judges[left])
                let second = squareCodes(history, judge: judges[right])
                guard let row = try? LabelMargin(labels: first, categoryCount: 3),
                      let column = try? LabelMargin(labels: second, categoryCount: 3),
                      let priced = try? AttainableTrace(row: row, column: column) else { continue }
                built.append(SquarePair(
                    key: "\(judges[left]) / \(judges[right])",
                    first: first, second: second,
                    row: row, column: column, priced: priced
                ))
            }
        }
        return built
    }

    private static func squareCodes(
        _ history: ObservationHistory, judge: JudgeIdentity
    ) -> [Int] {
        history.observations.map { observation in
            guard let verdict = observation.verdicts[judge],
                  let code = Verdict.allCases.firstIndex(of: verdict) else { return 2 }
            return code
        }
    }

    // MARK: - A: which agreement counts this corpus can reach, and which it cannot

    private static func squarePartA(_ pairs: [SquarePair]) {
        print("  A. every pair, and the counts inside its range that no table reaches")
        print("     \(squareWide("pair", 28))\(squareWide("margins", 22))"
            + "\(squareWide("range", 10))\(squareWide("observed", 9))"
            + "\(squareWide("reachable", 10))holes")
        for pair in pairs {
            let range = "\(pair.priced.lowerTrace)...\(pair.priced.upperTrace)"
            let observed = zip(pair.first, pair.second).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
            let holes = pair.priced.holes
            print("     \(squareWide(pair.key, 30))"
                + "\(squareWide(squareCounts(pair.row.counts) + squareCounts(pair.column.counts), 22))"
                + "\(squareWide(range, 10))"
                + "\(squareWide("\(observed)", 9))"
                + "\(squareWide("\(pair.priced.attainableTraces.count)", 10))"
                + (holes.isEmpty ? "none" : squareCounts(holes)))
        }
        print("     the range is Fréchet; the holes are the part no book prints, because the")
        print("     attainable set above two categories is not an arithmetic progression")
    }

    // MARK: - B: the refusal, and the same question answered

    private static func squarePartB(_ pair: SquarePair) {
        print("  B. the call scenario 56 declines, next to the call that answers it")
        let target = pair.priced.upperTrace - 1
        do {
            let first = try MarginalProfile(counts: pair.row.counts)
            let second = try MarginalProfile(counts: pair.column.counts)
            let legacy = try AttainableAgreement(first: first, second: second)
            let verdict = legacy.admits(count: target)
            print("     PanelDesignKit.admits(count: \(target)) -> "
                + (verdict.map { "\($0)" } ?? "nil (declines to decide)"))
            _ = try BinaryPanelBuilder(first: first, second: second)
                .table(diagonalTotal: target)
            print("     PanelDesignKit built it")
        } catch {
            print("     PanelDesignKit.table(diagonalTotal: \(target)) -> \(error)")
        }
        print("     SquareDesignKit.admits(trace: \(target)) -> \(pair.priced.admits(trace: target))")
        do {
            let table = try SquarePanelBuilder(attainable: pair.priced).table(trace: target)
            print("     SquareDesignKit built it: trace \(table.trace), "
                + "margins preserved \(table.rowMargin == pair.row && table.columnMargin == pair.column)")
        } catch {
            let sides = pair.priced.neighbourText(of: target)
            print("     SquareDesignKit refused: no table reaches \(target); nearest \(sides)")
        }
    }

    // MARK: - C: same judges, same rates, only the pairing changed

    private static func squarePartC(_ pair: SquarePair) async {
        print("  C. repairing the pairing, and what the coefficient does when you do")
        let builder = SquarePanelBuilder(attainable: pair.priced)
        let observed = zip(pair.first, pair.second).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        await squareReading("as the corpus paired them", first: pair.first, second: pair.second)
        for trace in [pair.priced.lowerTrace, observed, pair.priced.upperTrace] {
            guard pair.priced.admits(trace: trace) else {
                print("     designed to agree on \(trace): no such table")
                continue
            }
            guard let table = try? builder.table(trace: trace) else { continue }
            let realised = PanelRealization(table: table, seed: 20_260_907)
            await squareReading(
                "designed to agree on \(trace)",
                first: realised.first, second: realised.second
            )
        }
        print("     every row above holds both judges' verdict rates exactly; the only thing that")
        print("     moved is which item each verdict landed on, which is the whole of association")
    }

    private static func squareReading(_ label: String, first: [Int], second: [Int]) async {
        guard let pair = try? LabelPair(first: first, second: second, categoryCount: 3) else {
            print("     \(squareWide(label, 32))no pair")
            return
        }
        let ledger = ChanceLedger()
        await ledger.record("reading", pair: pair)
        guard let reading = try? await ledger.baseline(for: "reading") else {
            print("     \(squareWide(label, 32))agreed \(pair.agreementCount), no chance term")
            return
        }
        print("     \(squareWide(label, 32))"
            + "\(squareWide("agreed \(pair.agreementCount)", 12))"
            + "\(squareWide("kappa " + squareDp(reading.coefficient), 14))"
            + "deviate \(squareDp(reading.standardizedDeviate, 3))")
    }

    // MARK: - D: the theorem this corpus happens to demonstrate

    private static func squarePartD(_ pairs: [SquarePair]) {
        print("  D. what identical marginals forbid, on the pairs of this panel that have them")
        let identical = pairs.filter(\.priced.marginsAreIdentical)
        guard identical.isEmpty == false else {
            print("     no pair on this panel shares a marginal, so the theorem does not bind here")
            return
        }
        for pair in identical {
            let items = pair.priced.itemCount
            let observed = zip(pair.first, pair.second).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
            print("     \(squareWide(pair.key, 30))"
                + "\(squareWide(squareCounts(pair.row.counts) + " both", 18))"
                + "\(squareWide("observed \(observed)/\(items)", 16))"
                + "n-1 = \(items - 1) reachable \(pair.priced.admits(trace: items - 1))")
        }
        print("     at n-1 every per-category floor reads a_k, so their sum is n, which is never")
        print("     at most n-1: two judges with the same rates cannot differ on exactly one item.")
        print("     a pair here that agrees on every item is one judge counted twice, and the")
        print("     theorem is why it cannot instead have agreed on all but one")
    }

    // MARK: - formatting

    private static func squareWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func squareCounts(_ values: [Int]) -> String {
        "[" + values.map(String.init).joined(separator: ",") + "]"
    }

    private static func squareDp(_ value: Double, _ places: Int = 4) -> String {
        value.isNaN ? "n/a" : String(format: "%.\(places)f", value)
    }
}

extension AttainableTrace {
    /// The attainable counts either side of an unattainable one, as printed text.
    func neighbourText(of trace: Int) -> String {
        let reachable = attainableTraces
        let below = reachable.last { $0 < trace }.map(String.init) ?? "none"
        let above = reachable.first { $0 > trace }.map(String.init) ?? "none"
        return "\(below) / \(above)"
    }
}
