import ClaimConsistencyKit
import Foundation
import ProviderGatewayKit
import SourceConflictKit
import TokenMeterKit

/// The identifier the twenty-seventh scenario's single surviving hop bills against.
extension ProviderIdentifier {
    static let conflictHost = ProviderIdentifier("conflict-host")
}

/// Serves pairwise verdicts that were computed ahead of time.
///
/// `ContradictionOracle.judge` is synchronous by design — that is what makes an audit replayable —
/// and `ConsistencyChecker` is an actor. Rather than pretend the mismatch away, the pairs are
/// judged once, up front, and the results handed to the auditor as a table. Judging happens in one
/// canonical id order and is served for both, which is how the oracle's symmetry contract survives
/// an underlying checker that never promised it.
struct TableOracle: ContradictionOracle {
    let name: String
    let verdicts: [String: OracleVerdict]

    static func key(_ lhs: String, _ rhs: String) -> String {
        [lhs, rhs].sorted().joined(separator: "|")
    }

    func judge(_ lhs: Passage, _ rhs: Passage) -> OracleVerdict {
        verdicts[TableOracle.key(lhs.id, rhs.id)] ?? .unrelated
    }
}

extension EcosystemDemo {
    /// The twenty-seventh scenario: **the sources disagree with each other, and nobody asked.**
    ///
    /// Every truthfulness check in the twenty-six scenarios above runs after generation. Grounding
    /// verifies an answer against its sources; claim consistency checks whether that answer states
    /// the opposite of what a source says. Both judge a paragraph that has already been paid for.
    ///
    /// This one runs before the request. It takes the retrieved set and asks whether the passages
    /// agree with *each other* — a question nothing else in this pipeline covers, and the one the
    /// research literature keeps naming as the gap that degrades RAG accuracy most sharply.
    ///
    /// The integration worth reading is the oracle: today's package delegates its pairwise
    /// judgement to yesterday's. `ClaimConsistencyKit` already answers exactly the question
    /// `ContradictionOracle` asks — *do these two sentences agree* — so it plugs straight in, and
    /// the demo runs the same audit twice to show what that buys over the built-in lexical oracle.
    static func runSourceConflictScenario(meter: TokenMeter) async {
        do {
            let passages = try conflictPassages()
            let lexical = try await ConflictAuditor().audit(passages, at: 1)
            let backed = try await ConflictAuditor(
                oracle: try await consistencyOracle(over: passages)
            ).audit(passages, at: 1)

            report(lexical: lexical, backed: backed)
            try await sendSurvivingTopic(passages: passages, report: backed, meter: meter)
        } catch {
            print("[source conflict scenario] FAILED: \(error)")
        }
    }

    /// Seven passages over three topics. One topic is clean, one carries a contradiction the
    /// lexical oracle can see, and one carries a contradiction only a propositional checker reaches.
    private static func conflictPassages() throws -> [Passage] {
        let retries = try TopicKey("retry budget")
        let endpoint = try TopicKey("token counting endpoint")
        let cache = try TopicKey("response cache default")
        return [
            passage("s-spec", "The client retries at least 3 times before failing.",
                    retries, from("spec", .official, 12)),
            // 5 satisfies "at least 3". Not a conflict — and a naive numeric comparison says it is.
            passage("s-blog", "The client retries 5 times before failing.",
                    retries, from("blog", .community, 30)),
            passage("s-forum", "The client does not retry before failing.",
                    retries, from("forum", .community, 28)),
            passage("s-doc-a", "Some providers expose a token counting endpoint.",
                    endpoint, from("doc-a", .vendor, 5)),
            passage("s-doc-b", "All providers expose a token counting endpoint.",
                    endpoint, from("doc-b", .vendor, 9)),
            passage("s-cache-1", "The response cache is enabled by default.",
                    cache, from("spec", .official, 12)),
            passage("s-cache-2", "Caching is enabled by default for every request.",
                    cache, from("guide", .vendor, 11))
        ]
    }

    private static func from(_ source: String, _ authority: AuthorityTier, _ revision: Int) -> Provenance {
        Provenance(sourceID: source, authority: authority, revision: revision)
    }

    private static func passage(
        _ id: String,
        _ text: String,
        _ topic: TopicKey,
        _ provenance: Provenance
    ) -> Passage {
        Passage(id: id, text: text, topic: topic, provenance: provenance)
    }

    /// Judges every same-topic pair through `ConsistencyChecker` once, then serves the results.
    private static func consistencyOracle(over passages: [Passage]) async throws -> TableOracle {
        var pairs: [(Passage, Passage)] = []
        for left in 0..<passages.count {
            for right in (left + 1)..<passages.count where passages[left].topic == passages[right].topic {
                pairs.append((passages[left], passages[right]))
            }
        }

        let checker = try ConsistencyChecker()
        let report = try await checker.check(
            pairs.map { lhs, rhs in
                ClaimPair(
                    claim: ClaimConsistencyKit.Claim(id: lhs.id, text: lhs.text),
                    passage: SourcePassage(id: rhs.id, text: rhs.text)
                )
            },
            policy: .standard,
            at: 1
        )

        var table: [String: OracleVerdict] = [:]
        for (pair, judgement) in zip(pairs, report.judgements) {
            let key = TableOracle.key(pair.0.id, pair.1.id)
            switch judgement.verdict {
            case .contradicts:
                let why = judgement.contradictions.first?.summary ?? "propositional contradiction"
                table[key] = .conflicts(reason: why)
            case .agrees:
                table[key] = .agrees(reason: "propositional agreement")
            case .indeterminate:
                // The rules had nothing to say. Silence is not corroboration.
                table[key] = .unrelated
            }
        }
        return TableOracle(name: "claim-consistency", verdicts: table)
    }

    /// Both oracles find the same topic in dispute. What separates them is how much of the
    /// evidence each one throws away, and the difference is a passage that was never wrong.
    private static func report(lexical: ConflictReport, backed: ConflictReport) {
        print("[source conflict scenario] 7 passages, 3 topics, audited before any turn is sent")
        for (label, report) in [("lexical", lexical), ("claim-consistency", backed)] {
            let positions = report.findings.map { $0.positions.count }
            print("  oracle=\(label.padding(toLength: 18, withPad: " ", startingAt: 0))"
                + "conflicts: \(report.findings.count)  positions: \(positions)  "
                + "withheld: \(report.withheld)  -> \(describe(report.decision))")
        }

        let rescued = Set(lexical.withheld).subtracting(backed.withheld).sorted()
        print("  the difference is a false positive the lexical oracle manufactures: \(rescued)")
        print("      \"retries 5 times\" against \"retries at least 3 times\" is a satisfied bound.")
        print("      Lexical compares 3 against 5 as written; the propositional oracle reads the")
        print("      bound and lets the two passages corroborate each other instead.")
        print("  what both correctly leave alone: s-doc-a vs s-doc-b, `some` against `all`.")
        print("      \"all X\" entails \"some X\", so two sources saying that are compatible — even")
        print("      though an ANSWER that widens some to all is not. Source-source and")
        print("      claim-source are different questions, and this stage only asks the first.")

        for finding in backed.findings {
            print("  \(finding.topic): corroboration \(finding.positions.map(\.corroboration)) "
                + "-> \(describeResolution(finding.resolution))")
            for reason in finding.reasons.prefix(2) {
                print("      \(reason)")
            }
        }
    }

    private static func describeResolution(_ resolution: Resolution) -> String {
        switch resolution {
        case .resolved(let winner, let rule):
            return "RESOLVED by \(rule.rawValue) -> \(winner)"
        case .unresolved(let tried):
            return "UNRESOLVED (\(tried.map(\.rawValue).joined(separator: ", ")))"
        }
    }

    private static func describe(_ decision: AuditDecision) -> String {
        switch decision {
        case .clear: return "CLEAR"
        case .flagged(let withheld): return "FLAGGED (\(withheld.count) withheld)"
        case .blocked(let topics): return "BLOCKED \(topics)"
        }
    }

    /// The admitted set is the audit's own answer, so it is what gets sent — not a whole topic
    /// dropped by hand. Under `.blocked` there would be no turn at all, and that is the argument
    /// for running this stage first: the cheapest turn is the one never sent.
    private static func sendSurvivingTopic(
        passages: [Passage],
        report: ConflictReport,
        meter: TokenMeter
    ) async throws {
        guard case .blocked = report.decision else {
            try await send(passages.filter { report.admitted.contains($0.id) }, of: passages, meter: meter)
            return
        }
        print("  BLOCKED — no turn sent, 0 tokens spent on evidence that contradicts itself")
    }

    private static func send(
        _ usable: [Passage],
        of passages: [Passage],
        meter: TokenMeter
    ) async throws {
        let context = usable.map { "[\($0.id)] \($0.text)" }.joined(separator: "\n")
        let prompt = "Context:\n\(context)\n\nQuestion: what is the response cache default?"

        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: .conflictHost,
                script: ["The response cache is enabled by default [s-cache-1]."]
            )
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            ),
            for: ProviderIdentifier.conflictHost.rawValue
        )
        print("  sent: \(usable.count) of \(passages.count) passages — the losing position never "
            + "reached the gateway")
        print("  routed via \(response.providerID); the contradiction cost 0 model calls to find")
    }
}
