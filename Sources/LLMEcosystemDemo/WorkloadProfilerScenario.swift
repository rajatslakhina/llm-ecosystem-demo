import CostEstimatorKit
import Foundation
import ProviderGatewayKit
import TokenMeterKit
import WorkloadProfilerKit

/// The identifier the twenty-fifth scenario's routed hops bill against.
///
/// Registered at the same $2.80 / $11.20 per million as `.estimatorHost`, in
/// `EcosystemDemo.buildMeter()`, and again in this scenario's own `PriceBook` — so when
/// the derived plan is forecast at the end, forecast and actual are priced off the same
/// rates and any gap is a gap in predicting *work*.
extension ProviderIdentifier {
    static let profilerHost = ProviderIdentifier("profiler-host")
}

extension EcosystemDemo {
    /// The twenty-fifth scenario: where the *plan* in scenario 24 should have come from.
    ///
    /// Scenario 24 forecasts a loop from a `WorkloadPlan` and reconciles the result. That
    /// plan is a literal — `expectedOutputTokensPerStep: 15`, written by hand before the
    /// loop had ever been run. Scenario 24 then shows the model writing closer to 56 and
    /// the first pass overrunning at 81% tokens.
    ///
    /// This scenario runs three real loops through `ProviderGatewayKit`, records what each
    /// hop actually sent and received, and derives the plan from those runs instead. Then
    /// it puts the hand-written plan and the derived one side by side, which is the check
    /// nobody in this series had until now: not "was the forecast right?" but "is the
    /// thing we forecast from still describing the workload?"
    ///
    /// Nothing here duplicates the packages either side of it. `TokenMeterKit` measures
    /// one hop, `WorkloadProfilerKit` recovers the shape of many, and `CostEstimatorKit`
    /// prices the shape. The derived plan is fed straight back into a real
    /// `CostEstimatorKit.WorkloadPlan` at the end, so the loop closes.
    static func runWorkloadProfilerScenario(meter: TokenMeter) async {
        do {
            let profiler = WorkloadProfiler(
                config: try ProfilerConfig(minimumRuns: 3, maxResidualPermille: 60)
            )

            var firstInversion: TranscriptInversion?
            for (index, steps) in [3, 4, 5].enumerated() {
                let run = try await driveObservedLoop(
                    runID: "profiled-\(index + 1)",
                    steps: steps,
                    meter: meter
                )
                let inversion = try await profiler.ingest(run)
                if firstInversion == nil { firstInversion = inversion }
            }

            if let inversion = firstInversion {
                print(
                    "[workload profiler] run 1 sent \(inversion.observedInputTokens) input tokens "
                        + "across \(inversion.stepCount) steps — \(inversion.accumulationPercent)% "
                        + "of the \(inversion.flatInputTokens) a flat estimate would predict, "
                        + "\(inversion.residualPermille) permille unexplained"
                )
            }

            let key = ProfileKey(
                model: WorkloadProfilerKit.ModelID("profiler-host"),
                taskKind: "release-triage"
            )
            let derived = try await profiler.derivePlan(for: key)
            print(
                "[workload profiler] derived from 3 runs: \(derived.steps) steps, "
                    + "\(derived.toolCallsPerStep) tool call/step at \(derived.toolResultTokens) "
                    + "tokens, \(derived.expectedOutputTokensPerStep) output tokens/step "
                    + "— confidence \(derived.evidence.confidence), dispersion "
                    + "\(derived.evidence.dispersionPermille) permille"
            )

            try reportDrift(against: derived)
            try await reportForecast(from: derived, meter: meter)
        } catch {
            print("[workload profiler] FAILED: \(error)")
        }
    }

    /// The hand-written plan from scenario 24, checked against what the runs actually did.
    private static func reportDrift(against derived: DerivedPlan) throws {
        let handWritten = try estimatorPlan()
        let declared = try DeclaredPlan(
            openingContextTokens: handWritten.openingContextTokens,
            steps: handWritten.steps,
            toolCallsPerStep: handWritten.toolCallsPerStep,
            toolResultTokens: handWritten.toolResultTokens,
            expectedOutputTokensPerStep: handWritten.expectedOutputTokensPerStep,
            retryOverheadPercent: handWritten.retryOverheadPercent,
            cacheHitPercent: handWritten.cacheHitPercent
        )
        let comparison = try PlanComparison.compare(declared: declared, observed: derived)
        print(
            "[workload profiler] scenario 24's declared plan vs these runs: "
                + (comparison.hasDrifted ? "DRIFTED" : "still accurate")
                + " on \(comparison.drifted.count) of \(comparison.deltas.count) fields"
        )
        for delta in comparison.drifted {
            print(
                "[workload profiler]   \(delta.field): declared \(delta.declared), "
                    + "observed \(delta.observed) "
                    + "(\(delta.differencePermille) permille, "
                    + (delta.understated ? "understated" : "overstated") + ")"
            )
        }
    }

    /// The derived plan handed to `CostEstimatorKit` as a real `WorkloadPlan`.
    private static func reportForecast(from derived: DerivedPlan, meter: TokenMeter) async throws {
        let split = try derived.split(systemTokens: profilerSystemBlock.count / 4)
        let plan = try WorkloadPlan(
            model: CostEstimatorKit.ModelID("profiler-host"),
            taskKind: derived.taskKind,
            systemTokens: split.systemTokens,
            promptTokens: split.promptTokens,
            steps: derived.steps,
            toolCallsPerStep: derived.toolCallsPerStep,
            toolResultTokens: derived.toolResultTokens,
            expectedOutputTokensPerStep: derived.expectedOutputTokensPerStep,
            retryOverheadPercent: derived.retryOverheadPercent,
            cacheHitPercent: derived.cacheHitPercent
        )
        let estimator = CostEstimator(
            priceBook: try PriceBook([
                (
                    CostEstimatorKit.ModelID("profiler-host"),
                    try ModelPrice(
                        model: CostEstimatorKit.ModelID("profiler-host"),
                        inputPerMillion: 280_000_000,
                        outputPerMillion: 1_120_000_000
                    )
                )
            ]),
            predictor: FixedOutputPredictor()
        )
        let forecast = try await estimator.forecast(plan)
        print(
            "[workload profiler] forecasting from the derived plan: \(forecast.tokens) "
                + "· flat estimate would say \(forecast.naiveTokens)"
        )
        let metered = await meter.cost(for: ProviderIdentifier.profilerHost.rawValue)
        print("[workload profiler] TokenMeterKit billed these three runs at $\(metered)")
    }

    private static var profilerSystemBlock: String {
        "You are a release-triage assistant. Answer from the incident log only, and stop "
            + "as soon as the owning team is identified."
    }

    /// One real routed loop, recorded step by step as it happens.
    ///
    /// The transcript genuinely grows: step 4 resends the system block, the question, three
    /// answers and three tool results. That is the growth the inversion recovers, and it is
    /// only recoverable because the input token count of every hop is captured rather than
    /// summed into one total at the end.
    private static func driveObservedLoop(
        runID: String,
        steps: Int,
        meter: TokenMeter
    ) async throws -> ObservedRun {
        let answer = "The regression belongs to the checkout-api team: the 22:14Z deploy raised "
            + "p99 latency from 410ms to 840ms on the payment-authorisation path, and no other "
            + "service in the log moved outside its normal band during the same window."
        let question = "Checkout latency doubled after last night's deploy. "
            + "Which team owns the regression?"

        var transcript = profilerSystemBlock + "\n" + question
        var observed: [ObservedStep] = []

        for step in 1...steps {
            let router = ProviderRouter(providers: [
                ScriptedProvider(identifier: .profilerHost, script: [answer])
            ])
            let response = try await LLMSession(router: router).send(transcript)

            let promptTokens = transcript.count / 4
            let completionTokens = response.text.count / 4
            await meter.record(
                TokenMeterKit.TokenUsage(
                    promptTokens: promptTokens,
                    completionTokens: completionTokens
                ),
                for: ProviderIdentifier.profilerHost.rawValue
            )

            let toolResult = step < steps ? profilerToolResult(step) : ""
            observed.append(
                try ObservedStep(
                    ordinal: step,
                    tokens: try TokenCounts(
                        inputTokens: promptTokens,
                        outputTokens: completionTokens
                    ),
                    toolResultCount: toolResult.isEmpty ? 0 : 1,
                    toolResultTokens: toolResult.count / 4
                )
            )

            guard step < steps else { continue }
            transcript += "\n" + response.text + "\n" + toolResult
        }

        return try ObservedRun(
            runID: runID,
            model: WorkloadProfilerKit.ModelID("profiler-host"),
            taskKind: "release-triage",
            steps: observed
        )
    }

    private static func profilerToolResult(_ step: Int) -> String {
        "{\"tool\":\"incident_log\",\"step\":\(step),\"records\":"
            + "[{\"service\":\"checkout-api\",\"p99_ms\":840,\"deploy\":\"2026-07-30T22:14Z\"}]}"
    }
}
