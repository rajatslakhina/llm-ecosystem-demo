import AnswerContinuationKit
import Foundation
import LinkEgressKit
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the eighty-ninth scenario's turns bill against.
extension ProviderIdentifier {
    static let continuationHost = ProviderIdentifier("continuation-host")
}

/// A provider that replies from a script and reports the finish reason each reply really had,
/// which `ScriptedProvider` (always `.stop`) cannot.
private struct LengthLimitedProvider: LLMProvider {
    let identifier: ProviderIdentifier
    let capabilities = ProviderCapabilities(
        supportsToolCalling: false,
        supportsStreaming: false,
        maxContextTokens: 32_000,
        costTier: .medium,
        locality: .network
    )
    let script: [(text: String, finish: LLMResponse.FinishReason)]
    let calls = ContinuationCalls()

    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let reply = script[min(await calls.next(), script.count - 1)]
                let response = LLMResponse(text: reply.text, finishReason: reply.finish, providerID: identifier)
                continuation.yield(.completed(response))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Counts the calls `LengthLimitedProvider` has answered.
private actor ContinuationCalls {
    private var count = 0

    func next() -> Int {
        defer { count += 1 }
        return count
    }
}

extension EcosystemDemo {
    /// The eighty-ninth scenario: the answer the output limit cut.
    ///
    /// The route answers with `finish_reason: length` twice: first inside the code block, then
    /// inside the docs link. `ContinuationRunner` rewinds each cut to the last place nothing is
    /// half-written, asks for the rest through `ProviderRouter.send`, and stitches each reply on:
    /// the reopened fence, the repeated line and the preamble are removed. `LinkSanitizer.scan`
    /// shows what the cut answer would have linked to, and every call is metered, including
    /// the prompt each round sends again.
    static func runAnswerContinuationScenario(meter: TokenMeter) async {
        let costBefore = await meter.totalCost()
        let ledger = TruncationLedger()
        let provider = LengthLimitedProvider(identifier: .continuationHost, script: continuationScript)
        let router = ProviderRouter(providers: [provider])
        let base = [LLMMessage(role: .user, content: continuationPrompt)]
        do {
            let first = try await router.send(LLMRequest(messages: base, maxOutputTokens: 64))
            await meterContinuationCall(prompt: continuationPrompt, reply: first.text, meter: meter)
            let stop = StopReason(first.finishReason)
            let check = TruncationCheck(answer: first.text, stop: stop)
            let resume = ResumePoint(rewinding: first.text)
            print("[continuation scenario] continuation-host stops at \(first.text.unicodeScalars.count) scalars:"
                + " \(stop), cut \(check.isTruncated), inside \(continuationPlace(resume.context));"
                + " set aside \"\(resume.dropped)\" (\(resume.reasons.map { "\($0)" }.joined(separator: ", ")))")
            let runner = ContinuationRunner(policy: .standard, ledger: ledger)
            let outcome = await runner.finish(answer: first.text, stop: stop, model: "continuation-host") { plan in
                let messages = base + plan.messages.map {
                    LLMMessage(role: $0.role == .assistant ? .assistant : .user, content: $0.content)
                }
                let reply = try await router.send(LLMRequest(messages: messages, maxOutputTokens: 64))
                let sent = messages.map(\.content).joined(separator: "\n")
                await meterContinuationCall(prompt: sent, reply: reply.text, meter: meter)
                return ModelReply(text: reply.text, stop: StopReason(reply.finishReason))
            }
            printContinuationRounds(outcome)
            await printContinuationLinks(first: first.text, outcome: outcome)
            await printContinuationCost(outcome: outcome, ledger: ledger)
            print("[continuation scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[continuation scenario] FAILED: \(error)")
        }
    }

    private static let continuationPrompt = "System: You are a senior iOS engineer.\n\n"
        + "User: How do I retry a failed URLSession upload with exponential backoff? Show the code and link the docs."

    /// The answer the model meant to write.
    static let continuationAnswer = "Retry with a capped exponential backoff and give up after a few attempts:\n\n"
        + "```swift\nfunc upload(_ request: URLRequest, data: Data) async throws -> Data {\n"
        + "    for attempt in 0..<4 {\n        do {\n"
        + "            let (body, _) = try await URLSession.shared.upload(for: request, from: data)\n"
        + "            return body\n        } catch {\n"
        + "            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))\n"
        + "        }\n    }\n    throw URLError(.cannotConnectToHost)\n}\n```\n\n"
        + "The error codes worth retrying are listed in "
        + "[URLError.Code](https://developer.apple.com/documentation/foundation/urlerror/code). "
        + "Do not retry a 4xx response."

    private static var continuationScript: [(text: String, finish: LLMResponse.FinishReason)] {
        let firstCut = continuationAnswer.components(separatedBy: "Double(attempt)")[0] + "Dou"
        return [
            (firstCut, .maxTokens),
            ("```swift\n            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))\n        }\n    }\n"
                + "    throw URLError(.cannotConnectToHost)\n}\n```\n\nThe error codes worth retrying are listed in "
                + "[URLError.Code](https://developer.apple.com/documen", .maxTokens),
            ("Continuing from where I left off: [URLError.Code]"
                + "(https://developer.apple.com/documentation/foundation/urlerror/code). Do not retry a 4xx response.",
             .stop)
        ]
    }

    private static func continuationPlace(_ context: ContinuationContext) -> String {
        switch context {
        case let .codeBlock(language): return "a \(language ?? "plain") code block"
        case .table: return "a table"
        case .list: return "a list"
        case .prose: return "prose"
        }
    }

    private static func printContinuationRounds(_ outcome: ContinuationOutcome) {
        for round in outcome.rounds {
            let removed = round.removed.map { removal -> String in
                switch removal {
                case let .preamble(text): return "preamble \(text.debugDescription)"
                case let .reopenedFence(text): return "reopened fence \(text.debugDescription)"
                case let .repeatedText(text): return "repeat \(text.debugDescription)"
                }
            }
            print("[continuation scenario] round \(round.round): \(round.stop), \(round.received) scalars received,"
                + " \(round.added) added; removed \(removed.joined(separator: ", "))")
        }
        print("[continuation scenario] status \(outcome.status);"
            + " matches the answer the model meant: \(outcome.text == continuationAnswer)")
    }

    /// What a reader could tap: in the second cut shown as it is, and in the finished answer.
    private static func printContinuationLinks(first: String, outcome: ContinuationOutcome) async {
        let sanitizer = LinkSanitizer()
        let secondCut = outcome.rounds.count > 1
            ? continuationAnswer.components(separatedBy: "/documentation/")[0] + "/documen"
            : first
        let cutLinks = sanitizer.scan(secondCut).map(\.destination)
        let finalLinks = sanitizer.scan(outcome.text).map(\.destination)
        print("[continuation scenario] LinkEgressKit, links in the second cut shown as it is: \(cutLinks)")
        print("[continuation scenario] LinkEgressKit, links in the finished answer: \(finalLinks)")
        let naive = continuationScript.map(\.text).joined()
        let fences = naive.components(separatedBy: "```swift").count - 1
        print("[continuation scenario] naive concatenation instead: \(fences)"
            + " opening fences, \(naive.components(separatedBy: "Continuing from").count - 1) preamble,"
            + " equals the answer: \(naive == continuationAnswer)")
    }

    /// Three calls, each sending the prompt again, against one call with a limit that fits.
    private static func printContinuationCost(outcome: ContinuationOutcome, ledger: TruncationLedger) async {
        let raised = await buildMeter()
        await raised.record(
            TokenUsage(
                promptTokens: continuationPrompt.count / 4,
                completionTokens: continuationAnswer.count / 4
            ),
            for: ProviderIdentifier.continuationHost.rawValue
        )
        let stats = await ledger.stats(for: "continuation-host")
        let raisedCost = await raised.totalCost()
        print("[continuation scenario] ledger: \(stats.answers) answer, \(stats.cut) cut, \(stats.finished) finished"
            + " in \(stats.rounds) rounds; one call with a limit that fits would have cost $\(raisedCost)")
    }

    private static func meterContinuationCall(prompt: String, reply: String, meter: TokenMeter) async {
        await meter.record(
            TokenUsage(promptTokens: prompt.count / 4, completionTokens: reply.count / 4),
            for: ProviderIdentifier.continuationHost.rawValue
        )
    }
}

extension StopReason {
    /// The gateway's three finish reasons in this package's terms.
    init(_ reason: LLMResponse.FinishReason) {
        switch reason {
        case .stop: self = .finished
        case .maxTokens: self = .lengthLimit
        case .toolCallLimitExceeded: self = .toolCall
        }
    }
}
