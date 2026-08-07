import CitationBindingKit
import ClaimSegmenterKit
import Foundation
import GroundingKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the twenty-ninth scenario's single routed hop bills against.
extension ProviderIdentifier {
    static let citationHost = ProviderIdentifier("citation-host")
}

extension EcosystemDemo {
    /// The twenty-ninth scenario: **being supported and being attributed are different questions.**
    ///
    /// Scenario 28 ended by reporting a defect it could see but not fix. `GroundingKit` scores each
    /// claim against every document and keeps the best one, so a finely-cut claim gets handed to
    /// whichever passage shares the most wording — which is not necessarily the passage it cited.
    /// That scenario printed the strays and said the fix belonged to the layer below.
    ///
    /// This is that layer. `CitationBindingKit` asks the question the verifier never asks: not
    /// *which document supports this claim best*, but *does the document the answer actually named
    /// support it*. Both run over the same claims from the same segmenter, so the difference in the
    /// output is the difference between the two questions and nothing else.
    static func runCitationBindingScenario(meter: TokenMeter) async {
        do {
            let answer = try await routeCitationTurn(meter: meter)
            let bridge = ClaimSegmenterBridge(policy: .default)
            let claims = bridge.claims(in: answer)
            let grounding = try await GroundingVerifier(segmenter: bridge).verify(
                answer: answer,
                against: try EvidenceSet(citationSources),
                policy: .strict,
                at: 1
            )

            let binder = CitationBindingKit.SynchronousCitationBinder(
                evidence: try citationEvidence(),
                policy: .strict
            )
            let report = try binder.bind(claims.map(Self.toCitedClaim))

            compare(grounding: grounding, binding: report)
            describeBindings(report)
        } catch {
            print("[citation binding scenario] FAILED: \(error)")
        }
    }

    /// The same five documents scenario 28 uses, in the shape this package takes. Two of them —
    /// `kb-cache` and `kb-stream` — both talk about something being enabled or disabled by default,
    /// which is exactly the near-duplicate pair that makes a finely-cut claim land on the wrong one.
    private static var citationSources: [GroundingKit.SourceDocument] {
        [
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-cache"),
                                        text: "The response cache is enabled by default."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-share"),
                                        text: "The response cache is shared across sessions."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-retry"),
                                        text: "The client is capped at two retries."),
            GroundingKit.SourceDocument(id: GroundingKit.SourceID("kb-stream"),
                                        text: "Streaming is disabled by default."),
            GroundingKit.SourceDocument(
                id: GroundingKit.SourceID("kb-queue"),
                text: "Requests queue behind the limiter and the queue is bounded."
            )
        ]
    }

    private static func citationEvidence() throws -> CitationBindingKit.EvidenceSet {
        try CitationBindingKit.EvidenceSet(citationSources.map { document in
            CitationBindingKit.SourceDocument(
                id: CitationBindingKit.SourceID(document.id.rawValue),
                title: document.id.rawValue,
                text: document.text
            )
        })
    }

    /// `GroundingKit.Claim` already carries the citations parsed out of the answer, so both packages
    /// look at exactly the same claims — no re-parsing, and no chance of the two drifting.
    private static func toCitedClaim(_ claim: GroundingKit.Claim) -> CitedClaim {
        CitedClaim(
            id: claim.id,
            text: claim.text,
            citations: claim.citations.map { CitationBindingKit.SourceID($0.rawValue) }
        )
    }

    private static func routeCitationTurn(meter: TokenMeter) async throws -> String {
        let prompt = "Question: summarise the caching, retry, streaming and queueing behaviour."
        let reply = "The response cache is enabled by default [kb-cache], "
            + "but it is not shared across sessions [kb-share]. "
            + "The client is capped at two retries [kb-retry], "
            + "and streaming is enabled by default [kb-stream]. "
            + "Requests queue behind the limiter, and the queue is bounded [kb-queue]."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .citationHost, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            ),
            for: ProviderIdentifier.citationHost.rawValue
        )
        print("[citation binding scenario] routed via \(response.providerID)")
        return response.text
    }

    /// The comparison worth the scenario: for every claim, which document each layer looked at.
    private static func compare(grounding: GroundingReport, binding: BindingReport) {
        print("  claim  grounding scored against   binding attributed to   agree?")
        var divergent: [String] = []
        for verdict in grounding.verdicts {
            guard let bound = binding.binding(verdict.claim.id) else { continue }
            let scored = verdict.support.sourceID.rawValue
            let attributed = bound.source()?.description ?? "(unbound)"
            let agree = scored == attributed
            if !agree { divergent.append(verdict.claim.id) }
            print("  \(pad(verdict.claim.id, 7))\(pad(scored, 27))\(pad(attributed, 24))"
                + (agree ? "yes" : "NO"))
        }
        guard !divergent.isEmpty else {
            print("  the two layers agree on every claim")
            return
        }
        print("  \(divergent.count) claim(s) where the two layers looked at different documents: "
            + divergent.joined(separator: ", ")
            + " - grounding took the best overlap, binding took the citation")
    }

    private static func describeBindings(_ report: BindingReport) {
        let statistics = report.statistics()
        print("  findings:")
        let flagged = report.flaggedFindings()
        if flagged.isEmpty {
            print("    none - every claim was bound to a source it actually cited, and no uncited")
            print("    source beat a cited one by the decisive margin")
        }
        for entry in flagged {
            print("    \(entry.claimID): \(entry.finding.summary())")
        }
        let rate = statistics.attributionRate().map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("  \(statistics.claimCount) claims, \(statistics.citedBoundCount) bound to a cited "
            + "source, \(statistics.misattributedCount) mis-attributed. Attribution rate \(rate).")
        print("  extra gateway hops: 0 - binding is local computation over what was already fetched")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
