import BatchInferenceKit
import Foundation
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit

/// An eleventh provider identity, used only by the batch-inference scenario's
/// fanned-out routed calls — registered with its own explicit rate in
/// `EcosystemDemo.buildMeter()` so the batch's summed usage bills at a real rate
/// rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let batchHost = ProviderIdentifier("batch-host")
}

/// `BatchInferenceKit`'s `BatchExecuting` seam wired to a real routed
/// `ProviderRouter`/`LLMSession` pair, so the batch genuinely fans out through
/// `ProviderGatewayKit` instead of answering from canned strings.
///
/// One session per item rather than one shared across the batch: `LLMSession`
/// serializes the turns of a *conversation*, and a batch's items are independent
/// requests, not turns. Keying each reply off the request id rather than a shared
/// call counter is also what keeps this scenario reproducible — a reply belongs to
/// its prompt, not to whichever slot in the window happened to finish first.
///
/// Each routed reply is validated with `StructuredOutputKit`, and the adapter
/// throws when one doesn't decode. That throw is the per-item failure
/// `BatchProcessor` isolates: the realistic failure mode for an offline batch is
/// one reply out of many coming back off-contract, not the whole job dying.
struct GatewayBatchExecutor: BatchExecuting {
    let replies: [String: String]
    let decoder: StructuredOutputDecoder
    let providerID: ProviderIdentifier

    func execute(_ request: BatchRequest) async throws -> BatchResponse {
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [replies[request.id] ?? "{}"])
        ])
        let response = try await LLMSession(router: router).send(request.prompt)
        _ = try await decoder.decode(WeatherReport.self, from: response.text)
        return BatchResponse(
            id: request.id,
            text: response.text,
            usage: BatchTokenUsage(
                promptTokens: request.prompt.count / 4,
                completionTokens: response.text.count / 4
            )
        )
    }
}

extension EcosystemDemo {
    /// The seventeenth scenario: `BatchInferenceKit` runs five prompts through one
    /// `BatchProcessor` with at most two in flight, and every item is a real
    /// `ProviderRouter`/`LLMSession` round trip via `GatewayBatchExecutor`. Three
    /// guarantees show up in the output: `stats.peakActive` proves the
    /// `ConcurrencyLimit(2)` bound actually held, `report.outcomes` comes back in
    /// input order no matter which item finished first, and the one reply that
    /// arrives missing a required field is isolated as a single `BatchItemError`
    /// under `.continueOnFailure` while the other four still complete.
    ///
    /// The billing seam is the interesting part. `BatchProcessor` sums
    /// `BatchTokenUsage` over *successful* items only, so the whole batch settles
    /// with one `TokenMeter.record` against `stats.usage` — the failed item costs
    /// nothing, matching how the retry scenario declines to bill failed attempts.
    /// `BatchInferenceKit` carries no cost or retry logic of its own by design; the
    /// executor and the summed usage are the only seams.
    static func runBatchInferenceScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let requests = batchInferenceRequests()
        let recorder = InMemoryBatchEventRecorder()
        let processor = BatchProcessor(
            executor: GatewayBatchExecutor(
                replies: batchInferenceReplies,
                decoder: decoder,
                providerID: .batchHost
            ),
            limit: ConcurrencyLimit(2),
            policy: .continueOnFailure,
            recorder: recorder
        )

        do {
            let report = try await processor.process(requests)
            printBatchSummary(report, requestCount: requests.count)
            await billBatchUsage(report.stats, meter: meter)
            let events = await recorder.events
            let last = events.last.map { "\($0)" } ?? "none"
            print("[batch inference scenario] \(events.count) batch events recorded, last: \(last)")
        } catch {
            print("[batch inference scenario] FAILED: \(error)")
        }
    }

    /// Prints the three guarantees the batch is here to demonstrate: the bound that
    /// held, the input order that survived, and the one item whose failure stayed
    /// its own rather than taking the batch down with it.
    private static func printBatchSummary(_ report: BatchReport, requestCount: Int) {
        let stats = report.stats
        print(
            "[batch inference scenario] \(requestCount) prompts, limit 2 \u{2192} peakActive "
                + "\(stats.peakActive) (bound held), \(stats.succeeded) succeeded, \(stats.failed) failed, "
                + "\(stats.cancelled) cancelled"
        )
        let order = report.outcomes.map { outcome in
            guard let response = outcome.response else {
                return "\(outcome.error?.requestID ?? "?")=failed"
            }
            return "\(response.id)=ok"
        }
        print("[batch inference scenario] outcomes in input order: \(order.joined(separator: ", "))")
        for failure in report.failures {
            print("[batch inference scenario] \(failure.requestID) isolated (\(failure.kind)): \(failure.message)")
        }
    }

    /// Bills the batch in one shot against the usage `BatchProcessor` summed over
    /// its successful items — the reason `batch-host` is registered with its own
    /// explicit rate in `buildMeter()` rather than left to a default catalog that
    /// would report a silent $0 for an identity it has never heard of.
    private static func billBatchUsage(_ stats: BatchStats, meter: TokenMeter) async {
        await meter.record(
            TokenUsage(
                promptTokens: stats.usage.promptTokens,
                completionTokens: stats.usage.completionTokens
            ),
            for: ProviderIdentifier.batchHost.rawValue
        )
        let cost = await meter.cost(for: ProviderIdentifier.batchHost.rawValue)
        print(
            "[batch inference scenario] \(stats.succeeded) successful items summed to "
                + "\(stats.usage.promptTokens)+\(stats.usage.completionTokens) tokens "
                + "(\(stats.usage.totalTokens) total), billed under batch-host: $\(cost)"
        )
    }

    /// The five prompts this batch fans out, in submission order.
    private static func batchInferenceRequests() -> [BatchRequest] {
        let instructions = PromptBuilder.instructions(for: WeatherReport.jsonSchema, typeName: "a WeatherReport")
        return ["kochi", "jaipur", "shimla", "nagpur", "bhopal"].map { id in
            BatchRequest(id: id, prompt: "\(instructions)\nReport the current weather for \(id.capitalized).")
        }
    }

    /// What the batch-host provider answers for each request id. `shimla`'s reply
    /// omits the required `conditions` field on purpose, so exactly one of the five
    /// items fails validation inside the executor and the rest still run.
    private static var batchInferenceReplies: [String: String] {
        [
            "kochi": #"{"city": "Kochi", "temperatureCelsius": 30.5, "conditions": "cloudy"}"#,
            "jaipur": #"{"city": "Jaipur", "temperatureCelsius": 38.0, "conditions": "clear"}"#,
            "shimla": #"{"city": "Shimla", "temperatureCelsius": 12.0}"#,
            "nagpur": #"{"city": "Nagpur", "temperatureCelsius": 35.5, "conditions": "clear"}"#,
            "bhopal": #"{"city": "Bhopal", "temperatureCelsius": 31.0, "conditions": "rain"}"#
        ]
    }
}
