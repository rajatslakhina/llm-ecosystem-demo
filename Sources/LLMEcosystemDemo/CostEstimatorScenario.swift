import CostEstimatorKit
import Foundation
import ProviderGatewayKit
import QuotaGovernorKit
import StructuredOutputKit
import TokenMeterKit

/// The identifier the twenty-fourth scenario's routed hops bill against.
///
/// Its rate is registered twice on purpose — once with `TokenMeter` in
/// `EcosystemDemo.buildMeter()` and once in this scenario's `PriceBook`, at the same
/// $2.80 / $11.20 per million. That is what makes the comparison at the end mean
/// anything: forecast and actual are priced off the same rates, so the error that
/// shows up is error in predicting *work*, not two catalogs disagreeing.
extension ProviderIdentifier {
    static let estimatorHost = ProviderIdentifier("estimator-host")
}

extension EcosystemDemo {
    /// The twenty-fourth scenario: where the estimate in scenario 23 came from.
    ///
    /// `QuotaGovernorKit` reserves against a `Cost` the caller hands it and never asks
    /// how that number was arrived at. In scenario 23 it was a literal. Here it is
    /// computed — from the loop shape the caller already decided on before dispatching.
    ///
    /// The loop below genuinely resends its transcript, because that is the thing being
    /// predicted. Step 1 sends the system block and the question. Step 4 sends those plus
    /// three answers plus three tool results. Input grows with the loop, which is exactly
    /// what a flat "one call times four" estimate misses.
    ///
    /// Two runs, and they fail differently:
    ///
    /// - Run 1 carries a prior of 15 output tokens per step against a model that writes
    ///   closer to 56. The transcript arithmetic is right and the output guess is wrong,
    ///   so the run overruns — and the `±50%` prior band is wide enough to have warned
    ///   about it before the first hop went out.
    /// - Runs 2 and 3 forecast after the EMA predictor has seen run 1. The point estimate
    ///   moves to where reality is and lands within tolerance. The band does *not* narrow
    ///   immediately: one 81% miss is now in the record, so the second forecast is wider
    ///   than the prior was, and it only comes back down as accurate runs accumulate.
    ///   A band that tightened straight after being wrong would be the wrong behaviour.
    ///
    /// Nothing here imports across the seam in the other direction: `CostEstimatorKit`
    /// predicts, `TokenMeterKit` measures, `QuotaGovernorKit` enforces, and the three
    /// agree because they agree on integer microcents.
    static func runCostEstimatorScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        do {
            let predictor = try EMAOutputLengthPredictor(alphaPercent: 60)
            let estimator = CostEstimator(
                priceBook: try estimatorPriceBook(),
                predictor: predictor,
                policy: try ForecastPolicy(
                    priorSpreadPercent: 50,
                    tolerancePercent: 20,
                    minimumSamplesForSpread: 1,
                    maximumSpreadPercent: 200
                )
            )

            var spreads: [Int] = []
            for pass in 1...3 {
                let result = try await runEstimatedLoop(
                    estimator: estimator,
                    meter: meter,
                    pass: pass
                )
                spreads.append(result.spread)
            }

            let shape = try estimatorPlan().shape
            let learned = await predictor.learnedOutputTokens(for: shape) ?? 0
            let record = await estimator.calibration(for: shape)
            print(
                "[cost estimator] learned \(learned) output tokens/step over 3 runs; band "
                    + spreads.map { "\($0)%" }.joined(separator: " → ")
                    + " — the prior, then one bad run widening it, then measurement pulling it back"
            )
            print(
                "[cost estimator] calibration: \(record.samples) samples, "
                    + "MAPE \(record.meanAbsoluteErrorPercent)%, bias \(record.meanSignedErrorPercent)%"
            )

            let metered = await meter.cost(for: ProviderIdentifier.estimatorHost.rawValue)
            print("[cost estimator] TokenMeterKit billed these hops at $\(metered)")
        } catch {
            print("[cost estimator] FAILED: \(error)")
        }
    }

    /// Same rates as `buildMeter()` registers for `.estimatorHost`, in microcents
    /// per million: $2.80 in, $11.20 out.
    private static func estimatorPriceBook() throws -> PriceBook {
        try PriceBook([
            (
                CostEstimatorKit.ModelID("estimator-host"),
                try ModelPrice(
                    model: CostEstimatorKit.ModelID("estimator-host"),
                    inputPerMillion: 280_000_000,
                    outputPerMillion: 1_120_000_000
                )
            )
        ])
    }

    private static var estimatorSystemBlock: String {
        "You are a release-triage assistant. Answer from the incident log only, and stop "
            + "as soon as the owning team is identified."
    }

    private static var estimatorQuestion: String {
        "Checkout latency doubled after last night's deploy. Which team owns the regression?"
    }

    private static func estimatorToolResult(_ step: Int) -> String {
        "{\"tool\":\"incident_log\",\"step\":\(step),\"records\":"
            + "[{\"service\":\"checkout-api\",\"p99_ms\":840,\"deploy\":\"2026-07-30T22:14Z\"}]}"
    }

    /// The plan, built from the real strings the loop will send rather than from
    /// round numbers, so the forecast is a prediction of *this* run.
    static func estimatorPlan() throws -> WorkloadPlan {
        try WorkloadPlan(
            model: CostEstimatorKit.ModelID("estimator-host"),
            taskKind: "release-triage",
            systemTokens: estimatorSystemBlock.count / 4,
            promptTokens: estimatorQuestion.count / 4,
            steps: 4,
            toolCallsPerStep: 1,
            toolResultTokens: estimatorToolResult(1).count / 4,
            expectedOutputTokensPerStep: 15
        )
    }

    private struct EstimatedPass {
        let spread: Int
    }

    private static func runEstimatedLoop(
        estimator: CostEstimator,
        meter: TokenMeter,
        pass: Int
    ) async throws -> EstimatedPass {
        let plan = try estimatorPlan()
        let forecast = try await estimator.forecast(plan)

        let hold = try QuotaGovernorKit.Cost(
            tokens: forecast.expected.tokens,
            microcents: forecast.expected.microcents
        )
        print(
            "[cost estimator] pass \(pass) forecast \(forecast.tokens) "
                + "· band ±\(forecast.spreadPercent)% "
                + "· flat estimate would say \(forecast.naiveTokens)"
        )
        print("[cost estimator] pass \(pass) reserve against QuotaGovernorKit: \(hold)")

        let actual = try await driveTranscript(meter: meter)
        let settled = try await estimator.reconcile(forecast.id, actual: actual, steps: plan.steps)
        print(
            "[cost estimator] pass \(pass) actual \(actual) "
                + "· \(settled.verdict) at \(settled.tokenErrorPercent)% tokens / "
                + "\(settled.costErrorPercent)% cost"
        )
        return EstimatedPass(spread: forecast.spreadPercent)
    }

    /// Four routed hops that really do resend everything said so far.
    private static func driveTranscript(meter: TokenMeter) async throws -> CostEstimatorKit.TokenUsage {
        let answer = "The regression belongs to the checkout-api team: the 22:14Z deploy raised p99 "
            + "latency from 410ms to 840ms on the payment-authorisation path, and no other service "
            + "in the log moved outside its normal band during the same window."

        var transcript = estimatorSystemBlock + "\n" + estimatorQuestion
        var inputTokens = 0
        var outputTokens = 0

        for step in 1...4 {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .estimatorHost, script: [answer])
            ])
            let response = try await LLMSession(router: router).send(transcript)

            let promptTokens = transcript.count / 4
            let completionTokens = response.text.count / 4
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: promptTokens,
                    completionTokens: completionTokens
                ),
                for: ProviderIdentifier.estimatorHost.rawValue
            )
            inputTokens += promptTokens
            outputTokens += completionTokens

            guard step < 4 else { continue }
            transcript += "\n" + response.text + "\n" + estimatorToolResult(step)
        }

        return try CostEstimatorKit.TokenUsage(input: inputTokens, output: outputTokens)
    }
}
