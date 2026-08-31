import TokenMeterKit

/// The scenario groupings, lifted out of `EcosystemDemo` itself. Each addition to this series
/// adds a line to one of these, and the struct body has a 250-line limit that adding the
/// forty-seventh scenario crossed.
extension EcosystemDemo {
    /// The two scenarios about whether a call is permitted at all. Grouped so that adding the
    /// second one did not push `main()` past SwiftLint's 50-line body limit.
    static func runAuthorityScenarios(meter: TokenMeter) async {
        await runToolAuthorityScenario(meter: meter)
        await runSelectionTrustScenario(meter: meter)
    }

    /// The scenarios about what happens after an answer ships: whether it was gated, whether a
    /// label ever came back, and how long that took. Grouped out of `main()` for the same reason
    /// the banner was — that function has a 50-line body limit and this series keeps adding to it.
    static func runFeedbackScenarios(meter: TokenMeter) async {
        await runConformalGateScenario(meter: meter)
        await runCensoredFeedbackScenario(meter: meter)
        await runExplorationChannelScenario(meter: meter)
        await runLabelReturnScenario(meter: meter)
        await runDelaySignalScenario(meter: meter)
        await runDelayShapeScenario(meter: meter)
        await runDelayCurveScenario(meter: meter)
        await runCurveDivergenceScenario(meter: meter)
        await runLabelClockScenario(meter: meter)
    }
}
