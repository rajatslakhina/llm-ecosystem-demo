import Foundation
import ProviderGatewayKit
import QuotaGovernorKit
import TokenMeterKit
import UsageRecoveryKit

/// The identifier the ninetieth scenario's turn bills against.
extension ProviderIdentifier {
    static let recoveryHost = ProviderIdentifier("recovery-host")
}

/// A billing API that answers not-found on the first lookup and has the record on the second, as a
/// record written after the stream ends would.
private actor RecoveryBillingAPI: GenerationLookup {
    private let record: BilledUsage
    private(set) var lookups = 0

    init(record: BilledUsage) {
        self.record = record
    }

    func lookUp(_ id: GenerationID) async throws -> LookupAnswer {
        lookups += 1
        return lookups < 2 ? .notYetAvailable : .billed(record)
    }
}

/// Returns at once, so the lookup schedule runs without waiting.
private struct InstantSleeper: Sleeping {
    func sleep(for duration: Duration) async throws {}
}

extension EcosystemDemo {
    /// The ninetieth scenario: the turn whose usage never arrived.
    ///
    /// `recovery-host` writes a whole answer through `ProviderRouter`; the client reads 40 chunks
    /// and the user taps Stop, so the usage frame never comes. A budget that settles the turn at
    /// zero gets the whole hold back. `UsageRecovery` bounds the call from what was read, the
    /// governor settles at the upper bound, and the billing lookup's record is what `TokenMeter`
    /// records.
    static func runUsageRecoveryScenario(meter: TokenMeter) async {
        let costBefore = await meter.totalCost()
        do {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .recoveryHost, script: [recoveryAnswer])
            ])
            let reply = try await LLMSession(router: router).send(recoveryPrompt).text
            let read = readUntilStop(reply, chunks: 40)
            let headers = ["content-type": "text/event-stream", "x-generation-id": "gen-1760871090-rcv"]
            let generationID = GenerationIDExtractor.openRouter.generationID(fromHeaders: headers)
            print("[usage recovery scenario] recovery-host: user Stop after \(read.chunks) chunks,"
                + " \(read.text.unicodeScalars.count) of \(reply.unicodeScalars.count) scalars read;"
                + " no usage frame; id \(generationID?.rawValue ?? "none") from the header")
            let atZero = try await settleCutTurn(microcents: 0, tokens: 0)
            print("[usage recovery scenario] settled at zero: \(atZero) microcents of 5000000 left;"
                + " TokenMeter recorded nothing for the turn")
            try await recoverCutTurn(reply: reply, read: read, generationID: generationID, meter: meter)
            print("[usage recovery scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[usage recovery scenario] FAILED: \(error)")
        }
    }

    private static func recoverCutTurn(
        reply: String,
        read: (text: String, chunks: Int),
        generationID: GenerationID?,
        meter: TokenMeter
    ) async throws {
        let promptTokens = recoveryPrompt.count / 4
        let price = try UsageRecoveryKit.TokenPrice(inputDollarsPerMillion: 3, outputDollarsPerMillion: 15)
        let recovery = UsageRecovery(
            prices: PriceBook([ProviderIdentifier.recoveryHost.rawValue: price]),
            catalog: .openRouterDocumented(),
            sleeper: InstantSleeper()
        )
        let call = try ObservedCall(
            generationID: generationID,
            model: ProviderIdentifier.recoveryHost.rawValue,
            upstreamProvider: nil,
            input: try TokenRange(lower: promptTokens * 9 / 10, upper: promptTokens * 11 / 10),
            outputText: read.text,
            contentChunks: read.chunks,
            maxOutputTokens: 512,
            ending: .cancelled(reason: "user Stop")
        )
        let charge = try await recovery.open(call)
        let bounds = charge.bounds
        let streamedOnly = price.microcents(input: promptTokens, output: read.text.count / 4, roundingUp: false)
        print("[usage recovery scenario] bounds: output \(bounds.output) tokens, \(bounds.lowerMicrocents)"
            + "-\(bounds.upperMicrocents) microcents (\(bounds.basis.label)); streamed text alone prices it at"
            + " \(streamedOnly)")
        let held = try await settleCutTurn(
            microcents: charge.estimateMicrocents,
            tokens: bounds.input.upper + bounds.output.upper
        )
        print("[usage recovery scenario] settled at the upper bound: \(held) microcents of 5000000 left")
        // The upstream the router chose bills the whole generation after a disconnect.
        let billed = try BilledUsage(
            inputTokens: promptTokens,
            outputTokens: reply.count / 4,
            cancelled: true,
            upstreamProvider: "Google"
        )
        let api = RecoveryBillingAPI(record: billed)
        let resolution = try await recovery.resolve(charge.id, using: api)
        guard case let .billed(usage, microcents, attempts, inside) = resolution else {
            print("[usage recovery scenario] no record: \(resolution)")
            return
        }
        await meter.record(
            TokenUsage(promptTokens: usage.inputTokens, completionTokens: usage.outputTokens),
            for: ProviderIdentifier.recoveryHost.rawValue
        )
        print("[usage recovery scenario] billing record after \(attempts) lookups: \(usage.inputTokens) in /"
            + " \(usage.outputTokens) out on \(usage.upstreamProvider ?? "?"), \(microcents) microcents,"
            + " inside bounds \(inside); \(usage.outputTokens - read.text.count / 4) output tokens"
            + " billed after the Stop")
    }

    /// A fresh account with a $0.05 ceiling: hold for the turn, settle at `microcents`, return what
    /// is left.
    private static func settleCutTurn(microcents: Int, tokens: Int) async throws -> Int {
        let governor = QuotaGovernor()
        let account = ScopeID("recovery-account")
        try await governor.register(
            account,
            limits: try ScopeLimits(quota: try Quota(tokens: 100_000, microcents: 5_000_000))
        )
        let hold = try await governor.reserve(
            try Cost(tokens: 1_000, microcents: 1_000_000),
            for: try ScopePath([account]),
            at: 1
        )
        _ = try await governor.settle(hold.id, actual: try Cost(tokens: tokens, microcents: microcents), at: 2)
        return try await governor.snapshot(of: account).remaining(on: .microcents) ?? 0
    }

    /// Reads `chunks` chunks of 16 scalars, the way a live bubble receives them, then stops.
    private static func readUntilStop(_ reply: String, chunks: Int) -> (text: String, chunks: Int) {
        let scalars = Array(reply.unicodeScalars)
        var text = String.UnicodeScalarView()
        var count = 0
        for start in stride(from: 0, to: scalars.count, by: 16) where count < chunks {
            text.append(contentsOf: scalars[start..<min(start + 16, scalars.count)])
            count += 1
        }
        return (String(text), count)
    }

    private static let recoveryPrompt = "System: You are a senior iOS engineer.\n\n"
        + "User: How should an iOS app upload large files so the upload survives the app being suspended?"

    private static let recoveryAnswer = "Use a background URLSession. Create the configuration with "
        + "URLSessionConfiguration.background(withIdentifier:) and give it an identifier that stays the same "
        + "across launches, because the system uses it to reconnect your app to transfers it is still running. "
        + "Upload from a file, not from memory: background sessions only accept upload tasks created with "
        + "uploadTask(with:fromFile:), so write the body to a file in your container first. Set "
        + "isDiscretionary to false for uploads the user is waiting on, and leave sessionSendsLaunchEvents "
        + "on so the system can relaunch the app when the transfer finishes. Implement "
        + "application(_:handleEventsForBackgroundURLSession:completionHandler:) in the app delegate, keep "
        + "the completion handler, recreate the session with the same identifier, and call the handler from "
        + "urlSessionDidFinishEvents(forBackgroundURLSession:) on the main queue once your delegate has "
        + "processed every event. Do not rely on the delegate methods running while the app is suspended; "
        + "they run when the system wakes the app. For retries, inspect the task's error and its "
        + "NSURLErrorBackgroundTaskCancelledReasonKey, and resume from the server's last acknowledged byte "
        + "if your backend supports resumable uploads. Finally, test it for real: start an upload, send the "
        + "app to the background, and kill it from Xcode, then watch the upload finish and the app relaunch."
}
