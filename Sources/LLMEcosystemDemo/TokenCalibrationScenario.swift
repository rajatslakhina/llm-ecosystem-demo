import Foundation
import ProviderGatewayKit
import QuotaGovernorKit
import TokenCalibrationKit
import TokenMeterKit

/// The identifier the ninety-first scenario's turn bills against.
extension ProviderIdentifier {
    static let calibrationHost = ProviderIdentifier("calibration-host")
}

/// `calibration-host`'s tokenizer, simulated, because the demo has no real one: an English word costs one
/// token up to three letters and one more per four after that, a Han character one or two, every other
/// non-space scalar one, each message four and the request three. The calibrator never sees this type;
/// it only sees request text and the billed number.
private enum CalibrationHostTokenizer {
    static func bill(_ messages: [String]) -> Int {
        messages.reduce(3) { $0 + 4 + tokens(in: $1) }
    }

    static func tokens(in text: String) -> Int {
        var total = 0
        var letters = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII && scalar.properties.isAlphabetic {
                letters += 1
                continue
            }
            total += letters > 0 ? 1 + max(0, letters - 3) / 4 : 0
            letters = 0
            switch scalar.value {
            case 0x20:
                break
            case 0x4E00...0x9FFF:
                total += scalar.value % 3 == 0 ? 2 : 1
            default:
                total += 1
            }
        }
        return total + (letters > 0 ? 1 + max(0, letters - 3) / 4 : 0)
    }
}

extension EcosystemDemo {
    /// The ninety-first scenario: a request the character count says fits, and the bill says does not.
    ///
    /// `TokenCalibrator` learns `calibration-host`'s rates from thirty earlier bills. A Japanese customer
    /// then pastes a long upload log into a 4,096-token window with 512 kept for the answer. Characters
    /// divided by four say it fits several times over; the calibrated estimate says it overflows, so
    /// the oldest log lines are trimmed until the upper bound fits. `QuotaGovernor` holds that upper
    /// bound, the turn goes through `ProviderRouter`, `TokenMeter` meters the bill, and the bill is fed
    /// back to the calibrator.
    static func runTokenCalibrationScenario(meter: TokenMeter) async {
        let costBefore = await meter.totalCost()
        do {
            let calibrator = TokenCalibrator()
            let model = ProviderIdentifier.calibrationHost.rawValue
            for index in 0..<30 {
                let messages = calibrationHistory(index)
                let billed = CalibrationHostTokenizer.bill(messages)
                _ = try await calibrator.record(.prompt(messages: messages), billedTokens: billed, model: model)
            }
            let learned = try await calibrator.report(for: model)
            print("[token calibration scenario] calibration-host: learned from \(learned.bills) earlier bills,"
                + " \(learned.inside)/\(learned.checked) inside their 90% interval")
            let messages = try await fitCalibratedRequest(calibrator, model: model)
            try await sendCalibratedTurn(messages, calibrator: calibrator, model: model, meter: meter)
            print("[token calibration scenario] metered: $\(await meter.totalCost() - costBefore)")
        } catch {
            print("[token calibration scenario] FAILED: \(error)")
        }
    }

    /// Trims the oldest pasted log lines until the calibrated upper bound fits the window.
    private static func fitCalibratedRequest(_ calibrator: TokenCalibrator, model: String) async throws -> [String] {
        var log = calibrationLog
        var messages = [calibrationSystem, log.joined(separator: "\n"), calibrationQuestion]
        let flat = messages.reduce(0) { $0 + $1.count } / 4
        var estimate = try await calibrator.estimatePrompt(messages: messages, model: model)
        var fit = try ContextFit(estimate: estimate, contextWindow: 4_096, reservedOutput: 512)
        print("[token calibration scenario] \(log.count)-line Japanese log: chars/4 says \(flat) tokens, fits in"
            + " 3584; calibrator says \(estimate.lower)-\(estimate.upper), \(fit.label); the host would bill"
            + " \(CalibrationHostTokenizer.bill(messages))")
        while fit.tokensToTrim > 0 {
            log.removeFirst()
            messages = [calibrationSystem, log.joined(separator: "\n"), calibrationQuestion]
            estimate = try await calibrator.estimatePrompt(messages: messages, model: model)
            fit = try ContextFit(estimate: estimate, contextWindow: 4_096, reservedOutput: 512)
        }
        print("[token calibration scenario] kept the newest \(log.count) of \(calibrationLog.count) lines:"
            + " \(estimate.lower)-\(estimate.upper), \(fit.label); \(estimate.unfamiliarTokens) of the estimate"
            + " is digits, a class no earlier bill contained, so it is bounded by the prior band")
        return messages
    }

    /// Holds the upper bound, sends through the router, meters the bill and teaches the calibrator.
    private static func sendCalibratedTurn(
        _ messages: [String],
        calibrator: TokenCalibrator,
        model: String,
        meter: TokenMeter
    ) async throws {
        let estimate = try await calibrator.estimatePrompt(messages: messages, model: model)
        let governor = QuotaGovernor()
        let account = ScopeID("calibration-account")
        try await governor.register(
            account,
            limits: try ScopeLimits(quota: try Quota(tokens: 100_000, microcents: 5_000_000))
        )
        let held = try Cost(tokens: estimate.upper + 512, microcents: estimate.upper * 300 + 512 * 1_500)
        let hold = try await governor.reserve(held, for: try ScopePath([account]), at: 1)
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .calibrationHost, script: [calibrationAnswer])
        ])
        let reply = try await LLMSession(router: router).send(messages.joined(separator: "\n\n")).text
        let billedIn = CalibrationHostTokenizer.bill(messages)
        let billedOut = CalibrationHostTokenizer.tokens(in: reply)
        await meter.record(TokenUsage(promptTokens: billedIn, completionTokens: billedOut), for: model)
        let actual = try Cost(tokens: billedIn + billedOut, microcents: billedIn * 300 + billedOut * 1_500)
        _ = try await governor.settle(hold.id, actual: actual, at: 2)
        let update = try await calibrator.record(.prompt(messages: messages), billedTokens: billedIn, model: model)
        let error = String(format: "%+.1f%%", update.relativeError * 100)
        print("[token calibration scenario] held \(held.tokens) tokens; billed \(billedIn) in / \(billedOut) out,"
            + " \(update.check) the interval (point \(update.estimate.point), \(error)); settled with"
            + " \(try await governor.snapshot(of: account).remaining(on: .microcents) ?? 0) of 5000000 microcents left")
    }

    private static func calibrationHistory(_ index: Int) -> [String] {
        let english = [
            "My upload stops when I switch apps. How do I keep it running?",
            "Which background session configuration should a large video upload use on iOS?",
            "The transfer finishes but my completion handler never runs after relaunch."
        ]
        let japanese = ["アップロードが止まりました。", "バックグラウンドで続けるには？", "東京から送信しています。"]
        let question = index.isMultiple(of: 2)
            ? english[index % 3]
            : String(repeating: japanese[index % 3], count: 2 + index % 5)
        return [calibrationSystem, question]
    }

    private static let calibrationSystem = "You are a support assistant for an iOS file transfer app."
    private static let calibrationQuestion = "上のログでアップロードが止まる理由を教えてください。"
    private static let calibrationLog = (0..<120).map { line in
        "2026-10-21 09:\(String(format: "%02d", line % 60)):\(String(format: "%02d", (line * 7) % 60))"
            + " 転送 #\(1_000 + line): バックグラウンド転送を再開しました。残り\(120 - line)件。"
    }
    private static let calibrationAnswer = "ログでは、アプリが一時停止されるたびに転送が再開されています。"
        + "バックグラウンドセッションの識別子を起動のたびに同じにし、完了ハンドラを保持してください。"
}
