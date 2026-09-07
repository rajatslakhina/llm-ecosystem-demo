import ChanceAgreementKit
import EffectiveVoteKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the fifty-fifth scenario bills its chance terms against.
extension ProviderIdentifier {
    static let chanceAgreementHost = ProviderIdentifier("chance-agreement-host")
}

extension EcosystemDemo {
    /// The fifty-fifth scenario: **scenario 54 refused to price the chance question. This one
    /// prices it, and finds the assumption hiding in the coefficient every scenario above has
    /// been quoting.**
    ///
    /// `ObservedNullKit` resamples the *family tail* — the null of the largest reading across a
    /// correlated family — and its ledger throws on anything that is not a `.familyTail`,
    /// because a judge-label permutation destroys exactly the dependence a multiplicity
    /// denominator exists to price. That refusal left a question standing: for one pair, is
    /// this reading above chance at all, and what is "chance" here?
    ///
    /// The answer turns out to be that every chance term in the literature *is* a resampling
    /// scheme's mean, and picking one is picking an assumption. This panel can say which.
    static func runChanceAgreementScenario(meter: TokenMeter) async {
        print("[chance agreement scenario] the chance question scenario 54 declined to spend")

        let history = panelHistory()
        let judges = history.judges
        let pairs = chancePairs(from: history, judges: judges)
        guard pairs.isEmpty == false else {
            print("     no pair of judges on this panel admits a chance term")
            return
        }

        let ledger = ChanceLedger()
        for (key, pair) in pairs { await ledger.record(key, pair: pair) }

        await chancePartA(ledger, pairs: pairs)
        chanceOrthogonality(pairs)
        chancePartB(pairs)
        await chancePartC(ledger, pairs: pairs)
        await chancePartD(ledger, pairs: pairs, history: history, judges: judges)

        await meter.record(
            TokenUsage(promptTokens: 480, completionTokens: 140),
            for: ProviderIdentifier.chanceAgreementHost.rawValue
        )
    }

    /// Every pair of judges, as the three-way verdicts they actually cast.
    ///
    /// Not the correctness grades `EffectiveVoteKit` counts. Agreement between two judges is a
    /// claim about what they *said*, and these judges said one of three things.
    private static func chancePairs(
        from history: ObservationHistory, judges: [JudgeIdentity]
    ) -> [(String, LabelPair)] {
        var built: [(String, LabelPair)] = []
        for left in 0..<judges.count where left + 1 < judges.count {
            for right in (left + 1)..<judges.count {
                let first = chanceCodes(history, judge: judges[left])
                let second = chanceCodes(history, judge: judges[right])
                let key = "\(judges[left]) / \(judges[right])"
                guard let pair = try? LabelPair(first: first, second: second, categoryCount: 3) else {
                    print("     \(key): no pair to build")
                    continue
                }
                built.append((key, pair))
            }
        }
        return built
    }

    private static func chanceCodes(_ history: ObservationHistory, judge: JudgeIdentity) -> [Int] {
        history.observations.map { observation in
            guard let verdict = observation.verdicts[judge],
                  let code = Verdict.allCases.firstIndex(of: verdict) else { return 2 }
            return code
        }
    }

    // MARK: - A: the coefficient, and the half of it nobody publishes

    private static func chancePartA(_ ledger: ChanceLedger, pairs: [(String, LabelPair)]) async {
        print("  A. every pair, corrected against the one scheme that holds both judges' rates")
        if let (_, sample) = pairs.first {
            print("     panel: \(sample.itemCount) items, verdicts coded "
                + "\(Verdict.allCases.map(\.rawValue).joined(separator: "/"))")
        }
        print("     \(chanceWide("pair", 28))\(chanceWide("agreed", 9))\(chanceWide("expected", 10))"
            + "\(chanceWide("kappa", 9))\(chanceWide("null sd", 9))\(chanceWide("deviate", 9))p")
        for (key, pair) in pairs {
            do {
                let reading = try await ledger.baseline(for: key)
                let expected = reading.expectedAgreement * Double(pair.itemCount)
                print("     \(chanceWide(key, 28))"
                    + "\(chanceWide("\(pair.agreementCount)", 9))"
                    + "\(chanceWide(chanceDp(expected, 2), 10))"
                    + "\(chanceWide(chanceDp(reading.coefficient), 9))"
                    + "\(chanceWide(chanceDp(reading.nullStandardDeviation), 9))"
                    + "\(chanceWide(chanceDp(reading.standardizedDeviate, 3), 9))"
                    + chanceSci(reading.oneSidedProbability))
            } catch {
                print("     \(chanceWide(key, 28))refused: \(error)")
            }
        }
        print("     the deviate and the p come out of the same closed form as the chance term;")
        print("     no coefficient in this demo above has ever carried either of them")
    }

    // MARK: - A2: why five of those coefficients are exactly zero

    /// The panel's judges are not approximately unrelated. They are exactly unrelated, and the
    /// contingency tables prove it cell by cell.
    ///
    /// Four scenarios above publish coefficients, intervals, corrections and thresholds over
    /// this same page. This is the first one able to say what the page's true pairwise
    /// association is, and the answer is that there is none: `PanelSpec.all` is a fully crossed
    /// design, so every joint count equals the product of its marginals over `n`, exactly.
    private static func chanceOrthogonality(_ pairs: [(String, LabelPair)]) {
        print("  B. those zeroes are structural, not lucky")
        var worstOverall = 0.0
        for (key, pair) in pairs {
            let items = Double(pair.itemCount)
            let table = pair.contingency
            let rows = pair.firstCounts
            let columns = pair.secondCounts
            var worst = 0.0
            for row in 0..<pair.categoryCount {
                for column in 0..<pair.categoryCount {
                    let independent = Double(rows[row]) * Double(columns[column]) / items
                    worst = max(worst, abs(Double(table[row][column]) - independent))
                }
            }
            let duplicate = pair.first == pair.second
            if duplicate == false { worstOverall = max(worstOverall, worst) }
            print("     \(chanceWide(key, 28))largest cell minus a_j*b_k/n = \(chanceDp(worst, 6))"
                + (duplicate ? "   (same judge twice)" : ""))
        }
        print("     every distinct pair sits at \(chanceDp(worstOverall, 6)): the corpus is fully crossed, so the")
        print("     joint count IS the product of the marginals and the association is exactly nil.")
        let items = pairs.first?.1.itemCount ?? 0
        print("     the one pair that is not zero is answerability against morphology, which agree on")
        print("     all \(items) items — a coefficient of one between two judges that are one judge.")
    }

    // MARK: - B: two coefficients the literature offers as rivals

    private static func chancePartB(_ pairs: [(String, LabelPair)]) {
        guard let (key, pair) = pairs.first else { return }
        let scott = ClosedFormBaseline.scott.expectedAgreement(for: pair)
        let gwet = ClosedFormBaseline.gwet.expectedAgreement(for: pair)
        let exact = ExactChanceMoments(scheme: .pooledRedeal, pair: pair).mean
        let labels = 2 * Double(pair.itemCount)
        let categories = Double(pair.categoryCount)
        print("  C. the term Scott drops, on this panel (\(key), c = \(pair.categoryCount))")
        print("     scott Pe minus its scheme's exact mean   \(chanceDp(scott - exact, 12))")
        print("     (1 - scott Pe) / (2n - 1)                \(chanceDp((1 - scott) / (labels - 1), 12))")
        let rescaled = (categories - 1) * gwet / (labels - 1)
        print("     (c - 1) * gwet Pe / (2n - 1)             \(chanceDp(rescaled, 12))")
        print("     Scott and Gwet are offered as alternatives. The finite-population term one of")
        print("     them omits is exactly the other one's whole chance term, rescaled.")
    }

    // MARK: - C: the ceiling these judges' own rates impose

    private static func chancePartC(_ ledger: ChanceLedger, pairs: [(String, LabelPair)]) async {
        print("  D. what the marginals allowed before either judge spoke")
        for (key, _) in pairs {
            do {
                let verdict = try await ledger.verdict(for: key, at: 0.05)
                let capped = verdict.ceiling.isUnrestricted ? "unrestricted" : "capped"
                print("     \(chanceWide(key, 28))"
                    + "kappa \(chanceDp(verdict.ceiling.coefficient))  "
                    + "ceiling \(chanceDp(verdict.ceiling.maximum))  "
                    + "reached \(chanceDp(verdict.ratio ?? .nan))  \(capped)")
            } catch {
                print("     \(chanceWide(key, 28))no verdict: \(error)")
            }
        }
        print("     a pair whose ratio is one did everything its marginals left available; its")
        print("     shortfall against a kappa of one belongs to the design, not to the judges")
    }

    // MARK: - D: what this panel will not answer, and says so

    private static func chancePartD(
        _ ledger: ChanceLedger,
        pairs: [(String, LabelPair)],
        history: ObservationHistory,
        judges: [JudgeIdentity]
    ) async {
        print("  E. three refusals this panel actually produces")
        if let (key, pair) = pairs.first {
            do {
                _ = try ParadoxDiagnostics(pair: pair)
                print("     prevalence on verdicts   unexpectedly accepted")
            } catch {
                print("     prevalence on verdicts   \(error)")
            }
            let pooled = ChanceLedger(scheme: .pooledRedeal)
            await pooled.record(key, pair: pair)
            do {
                _ = try await pooled.verdict(for: key)
                print("     pooled scheme spent      unexpectedly accepted")
            } catch {
                print("     pooled scheme spent      \(error)")
            }
        }
        guard judges.count >= 2 else { return }
        let grades = judges.map { judge in
            history.observations.map { $0.verdicts[judge] == $0.truth ? 1 : 0 }
        }
        guard let binary = try? LabelPair(first: grades[0], second: grades[1], categoryCount: 2),
              let diagnostics = try? ParadoxDiagnostics(pair: binary) else {
            print("     prevalence on correctness  unavailable")
            return
        }
        print("     the same question on the binary correctness grades does have an answer:")
        print("     \(judges[0]) / \(judges[1])  p_o \(chanceDp(binary.observedAgreement))  "
            + "prevalence \(chanceDp(diagnostics.prevalenceIndex))  "
            + "bias \(chanceDp(diagnostics.biasIndex))  "
            + "adjusted \(chanceDp(diagnostics.adjustedCoefficient))")
        if let coefficient = try? ClosedFormBaseline.cohen.coefficient(for: binary) {
            print("     Cohen on the same pair \(chanceDp(coefficient)) — the gap between that and p_o is what")
            print("     the prevalence index above is there to explain")
        } else {
            print("     Cohen on the same pair: absent, its chance term is certain")
        }
    }

    private static func chanceWide(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func chanceDp(_ value: Double, _ places: Int = 4) -> String {
        value.isNaN ? "n/a" : String(format: "%.\(places)f", value)
    }

    private static func chanceSci(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.2e", value)
    }
}
