import Foundation
import GuardrailKit
import ProviderGatewayKit
import StreamAggregatorKit
import StreamReleaseKit
import TokenMeterKit

/// The identifier the seventy-ninth scenario's streamed reply bills against.
extension ProviderIdentifier {
    static let streamReleaseHost = ProviderIdentifier("stream-release-host")
}

extension EcosystemDemo {
    /// The seventy-ninth scenario: `GuardrailKit` (scenario 7) screens a whole reply, and
    /// `StreamAggregatorKit` (scenario 16) reassembles a streamed one, but a chat UI shows the
    /// reply delta by delta. Screening each delta alone misses a value split across two deltas,
    /// and screening the assembled reply happens after every delta is already on screen.
    /// `StreamReleaseKit`'s `ReleaseGate` sits between the deltas and the screen and releases only
    /// text no scanner can still change its verdict on.
    ///
    /// The reply comes from a routed `LLMSession` and is billed through `TokenMeterKit`. The
    /// gateway's scripted provider answers in one piece (`supportsStreaming: false`), so the
    /// scenario cuts that reply into 12-scalar deltas, the same way scenario 16 scripts its SSE.
    static func runStreamReleaseScenario(meter: TokenMeter) async {
        let prompt = "Where is the staging deploy key, and who do I ask if the deploy fails?"
        let router = ProviderRouter(providers: [
            ScriptedProvider(
                identifier: .streamReleaseHost,
                script: ["Use AKIAIOSFODNN7EXAMPLE for staging; mail ops@acme.io if it fails."]
            )
        ])
        do {
            let response = try await LLMSession(router: router).send(prompt)
            await meter.record(
                TokenMeterKit.TokenUsage(promptTokens: prompt.count / 4, completionTokens: response.text.count / 4),
                for: response.providerID.rawValue
            )
            let deltas = scalarChunks(response.text, size: 12)
            let host = response.providerID.rawValue
            print("[stream release scenario] reply from \(host) cut into \(deltas.count) deltas")

            let perDelta = await screenEachDelta(deltas)
            print("   per-delta GuardrailKit screen shows: \"\(perDelta)\"")

            let assembled = try await StreamAggregator().aggregate(
                from: ScriptedDeltaSource([.role("assistant")] + deltas.map { .content($0) } + [.finish(.stop)])
            )
            let whole = await GuardrailPipeline(policy: GuardrailPolicy()).screenResponse(assembled.content)
            print("   whole-reply GuardrailKit screen: \(whole.verdict), \(whole.findings.count) finding(s), " +
                "but only after all \(deltas.count) deltas were shown")

            try await gateDeltas(deltas)
        } catch {
            print("[stream release scenario] FAILED: \(error)")
        }
    }

    /// What a UI would show if it ran `GuardrailKit` on each delta as it arrived.
    private static func screenEachDelta(_ deltas: [String]) async -> String {
        let pipeline = GuardrailPipeline(policy: GuardrailPolicy())
        var shown = ""
        for delta in deltas {
            shown += await pipeline.screenResponse(delta).sanitizedText
        }
        return shown
    }

    /// Pipes the deltas through a `ReleaseGate` and checks the result against the whole-text reference.
    private static func gateDeltas(_ deltas: [String]) async throws {
        let scanners: [any StreamScanner] = [try PatternScanner.awsAccessKeyID(), try PatternScanner.emailAddress()]
        let gate = ReleaseGate(scanners: scanners)
        let stream = AsyncStream<String> { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
        var shown = ""
        var calls = 0
        for try await release in gate.releases(of: stream) {
            shown += release.text
            calls += 1
        }
        let reference = await ReleaseGate.reference(for: deltas.joined(), scanners: scanners)
        let stats = await gate.stats
        print("   ReleaseGate shows: \"\(shown)\"")
        print("   \(stats.redactions) redactions across \(calls) releases; matches whole-text reference: " +
            "\(shown == reference); peak withheld \(stats.peakWithheld) of \(stats.scalarsReceived) scalars")
        // The email pattern's 96-scalar holdback is longer than this whole reply, so nothing shows
        // until the stream ends. The key scanner alone shows how much of that lag is the email's.
        let keyOnly = ReleaseGate(scanners: [try PatternScanner.awsAccessKeyID()])
        for delta in deltas { _ = await keyOnly.ingest(delta) }
        _ = await keyOnly.finish()
        let keyPeak = await keyOnly.stats.peakWithheld
        print("   holdback is the price: key scanner alone peaks at \(keyPeak) withheld scalars, " +
            "the email pattern holds the whole \(stats.scalarsReceived)-scalar reply until it ends")
    }

    private static func scalarChunks(_ text: String, size: Int) -> [String] {
        let scalars = Array(text.unicodeScalars)
        return stride(from: 0, to: scalars.count, by: size).map { start in
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[start..<min(start + size, scalars.count)])
            return String(view)
        }
    }
}
