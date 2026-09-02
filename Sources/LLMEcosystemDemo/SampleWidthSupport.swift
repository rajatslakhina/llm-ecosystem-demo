import EffectiveVoteKit
import Foundation
import ProxyLabelKit
import SampleWidthKit

extension EcosystemDemo {
    /// Audits every pair the panel measured, keeping only the ones that produced a real bound.
    static func auditedPairs(from panel: ProxyLabelledPanel, pairs: [JudgePair]) -> [AuditedPair] {
        let audit = ProxyLabelAuditor()
        let sample = panel.auditSample(limit: 60)
        return pairs.compactMap { pair in
            let result = audit.audit(
                proposals: panel.proposals,
                left: JudgeID(pair.first.rawValue),
                right: JudgeID(pair.second.rawValue),
                against: sample
            )
            guard case .bounded(let association, let cost, let table) = result.outcome,
                  let regime = result.regime else { return nil }
            return AuditedPair(
                pair: pair,
                table: table,
                association: association,
                flipRate: cost.symmetric,
                regime: regime
            )
        }
    }

    /// The same counts, in the shape `SampleWidthKit` measures widths on.
    static func contingency(from table: ErrorAgreementTable) -> SampleWidthKit.ContingencyTable? {
        try? SampleWidthKit.ContingencyTable(
            bothTrue: table.bothErred,
            firstTrueOnly: table.leftOnly,
            secondTrueOnly: table.rightOnly,
            bothFalse: table.neitherErred
        )
    }

    /// The integer table with `like`'s margins whose phi is nearest `phi`.
    static func agreementTable(atPhi phi: Double, like table: ErrorAgreementTable) -> ErrorAgreementTable? {
        let total = table.total
        let rowOne = table.leftErrorCount
        let colOne = table.rightErrorCount
        let rowZero = total - rowOne
        let colZero = total - colOne
        let denominator = (Double(rowOne) * Double(rowZero) * Double(colOne) * Double(colZero)).squareRoot()
        guard denominator > 0 else { return nil }

        let exact = (phi * denominator + Double(rowOne) * Double(colOne)) / Double(total)
        let cell = min(min(rowOne, colOne), max(max(0, rowOne + colOne - total), Int(exact.rounded())))
        return ErrorAgreementTable(
            bothErred: cell,
            leftOnly: rowOne - cell,
            rightOnly: colOne - cell,
            neitherErred: total - rowOne - colOne + cell
        )
    }

    static func widthDp(_ value: Double?) -> String {
        guard let value else { return "unmeasurable" }
        return String(format: "%.4f", value)
    }

    static func show(_ range: ClosedRange<Double>) -> String {
        "[\(widthDp(range.lowerBound)), \(widthDp(range.upperBound))]"
    }

    static func pad(_ text: String) -> String {
        text.padding(toLength: 28, withPad: " ", startingAt: 0)
    }
}
