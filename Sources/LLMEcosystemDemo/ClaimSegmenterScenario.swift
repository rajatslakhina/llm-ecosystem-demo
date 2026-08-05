import ClaimSegmenterKit
import Foundation
import GroundingKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the twenty-eighth scenario's single routed hop bills against.
extension ProviderIdentifier {
    static let segmenterHost = ProviderIdentifier("segmenter-host")
}

/// Feeds `ClaimSegmenterKit`'s claims into `GroundingKit`'s verifier through the seam that package
/// already has, so nothing downstream of the segmenter changes.
///
/// The two are complementary rather than competing: `ClaimSegmenterKit` decides where a claim
/// begins and ends, and `SentenceClaimSegmenter` is still the thing that pulls `[kb-cache]` markers
/// out of the text. Replacing the citation extraction as well would have been a rewrite of a part
/// that works.
struct ClaimSegmenterBridge: GroundingKit.ClaimSegmenting {
    let policy: SegmentationPolicy

    func claims(in answer: String) -> [GroundingKit.Claim] {
        guard let segmented = try? SynchronousClaimSegmenter(policy: policy).segment(answer) else {
            return []
        }
        let citations = SentenceClaimSegmenter()
        return segmented.claims.enumerated().compactMap { index, claim in
            guard let parsed = citations.claims(in: claim.verifiableText).first else { return nil }
            return GroundingKit.Claim(
                id: "c\(index + 1)",
                text: parsed.text,
                rawText: claim.text,
                citations: parsed.citations,
                span: GroundingKit.TextSpan(offset: claim.span.start,
                                            length: claim.span.length,
                                            text: claim.text)
            )
        }
    }
}

extension EcosystemDemo {
    /// The twenty-eighth scenario: **the sentence is the wrong unit of verification.**
    ///
    /// Every truthfulness check in this toolkit — grounding, propositional consistency, source
    /// conflict — starts by cutting text into claims, and all three take that cut as given. This
    /// scenario runs `GroundingKit`'s verifier twice over one answer, changing nothing but the
    /// segmenter behind its `ClaimSegmenting` seam.
    ///
    /// The answer is built so each sentence carries two assertions with two different citations:
    /// one that its source supports and one its source contradicts. At sentence granularity a
    /// verifier has one verdict to give for both, and the half that is wrong is averaged against
    /// the half that is right.
    static func runClaimSegmenterScenario(meter: TokenMeter) async {
        do {
            let evidence = try EvidenceSet(segmenterSources)
            let answer = try await routeSegmenterTurn(meter: meter)
            let coarse = try await GroundingVerifier().verify(
                answer: answer, against: evidence, policy: .strict, at: 1
            )
            let bridge = ClaimSegmenterBridge(policy: .default)
            let fine = try await GroundingVerifier(segmenter: bridge).verify(
                answer: answer, against: evidence, policy: .strict, at: 1
            )
            report(coarse: coarse, fine: fine, answer: answer)
        } catch {
            print("[claim segmenter scenario] FAILED: \(error)")
        }
    }

    private static var segmenterSources: [SourceDocument] {
        [
            SourceDocument(id: SourceID("kb-cache"),
                           text: "The response cache is enabled by default."),
            SourceDocument(id: SourceID("kb-share"),
                           text: "The response cache is shared across sessions."),
            SourceDocument(id: SourceID("kb-retry"),
                           text: "The client is capped at two retries."),
            SourceDocument(id: SourceID("kb-stream"),
                           text: "Streaming is disabled by default."),
            SourceDocument(id: SourceID("kb-queue"),
                           text: "Requests queue behind the limiter and the queue is bounded.")
        ]
    }

    /// One real routed turn. Each sentence pairs a true clause with a false one, and each clause
    /// cites the document that is actually about it — so citation checking passes and the defect
    /// survives all the way to the verifier.
    private static func routeSegmenterTurn(meter: TokenMeter) async throws -> String {
        let prompt = "Question: summarise the caching, retry, streaming and queueing behaviour."
        let reply = "The response cache is enabled by default [kb-cache], "
            + "but it is not shared across sessions [kb-share]. "
            + "The client is capped at two retries [kb-retry], "
            + "and streaming is enabled by default [kb-stream]. "
            + "Requests queue behind the limiter, and the queue is bounded [kb-queue]."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .segmenterHost, script: [reply])
        ])
        let response = try await LLMSession(router: router).send(prompt)
        await meter.record(
            TokenMeterKit.TokenUsage(
                promptTokens: prompt.count / 4,
                completionTokens: response.text.count / 4
            ),
            for: ProviderIdentifier.segmenterHost.rawValue
        )
        print("[claim segmenter scenario] routed via \(response.providerID); "
            + "3 sentences, 5 assertions, 5 citations")
        return response.text
    }

    private static func report(coarse: GroundingReport, fine: GroundingReport, answer: String) {
        print("  sentence granularity (GroundingKit's own segmenter)")
        describe(coarse)
        print("  clause granularity (ClaimSegmenterKit behind the same seam)")
        describe(fine)
        attribution(fine)
        segmentationNotes(for: answer)
    }

    /// A finer claim is checked against whichever document scores highest for it, which is not
    /// necessarily the one it cited. Splitting makes that visible instead of fixing it: the smaller
    /// the claim, the more of its wording it shares with a near neighbour, and a lexical scorer
    /// will happily hand `Streaming is enabled by default` to a document about the cache being
    /// enabled by default. Reported here rather than smoothed over — it is a real limit of matching
    /// by overlap, and it belongs to the layer below this one.
    private static func attribution(_ report: GroundingReport) {
        let strays = report.verdicts.filter { !$0.claim.citations.contains($0.support.sourceID) }
        guard !strays.isEmpty else {
            print("    every claim was scored against a source it actually cited")
            return
        }
        for verdict in strays {
            let cited = verdict.claim.citations.map(\.rawValue).joined(separator: ", ")
            print("    \(verdict.claim.id) cited [\(cited)] but was scored against "
                + "\(verdict.support.sourceID) - the overlap scorer picked a neighbour")
        }
    }

    private static func describe(_ report: GroundingReport) {
        for verdict in report.verdicts {
            let overlap = Int((verdict.support.score * 100).rounded())
            let level = "\(verdict.level.rawValue) (\(overlap)% vs \(verdict.support.sourceID))"
            print("    \(verdict.claim.id) \(level.padding(toLength: 44, withPad: " ", startingAt: 0))"
                + verdict.claim.text.prefix(52))
        }
        print("    -> \(report.decision.kind().rawValue), "
            + "\(report.violations.count) violation(s), \(report.verdicts.count) claim(s)")
    }

    /// What the segmenter itself did, printed beside the verdicts so a reader can see that the
    /// extra claims came from real cuts and that the refused one is reported rather than lost.
    private static func segmentationNotes(for answer: String) {
        guard let segmented = try? SynchronousClaimSegmenter().segment(answer) else { return }
        let repaired = segmented.repairedClaims.count
        print("  segmenter: \(segmented.claims.count) claims, \(repaired) repaired, "
            + "\(segmented.refusedSplits.count) split(s) refused")
        for claim in segmented.repairedClaims {
            print("    repaired \(claim.id): \"\(claim.text)\" -> \"\(claim.verifiableText)\"")
        }
        for refusal in segmented.refusedSplits {
            print("    refused at \",\u{00A0}\(refusal.coordinator)\" - \(refusal.reason.rawValue)")
        }
        print("  extra gateway hops spent on the second pass: 0 - segmentation is local computation")
    }
}
