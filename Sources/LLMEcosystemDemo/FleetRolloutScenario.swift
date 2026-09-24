import FleetRollout
import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The identifier the seventy-second scenario bills its measurement against.
extension ProviderIdentifier {
    static let fleetRolloutHost = ProviderIdentifier("fleet-rollout-host")
}

extension EcosystemDemo {
    /// The seventy-second scenario: every earlier scenario in this demo assumes every session gets
    /// the same providers and the same capabilities. A real fleet does not ship that way — a new
    /// capability (here, a structured-output beta on `ProviderIdentifier.cloud`) goes out to a
    /// canary slice first, and if it misbehaves, the kill has to actually hold. `FleetRolloutKit`
    /// is the client half of that: real set-membership targeting instead of a version comparison
    /// that over-exposes a forked OS fleet, and a version floor that a stale replay cannot undo.
    static func runFleetRolloutScenario(meter: TokenMeter) async {
        print("[fleet rollout scenario] which sessions get the structured-output beta on "
            + "\(ProviderIdentifier.cloud.rawValue), and does the kill survive a stale replay?")

        await fleetRolloutExposure()
        await fleetRolloutKillSurvivesReplay(meter: meter)
    }

    /// A. the headline finding, at ecosystem-demo scale: onTrain(set) vs. a naive version-ordering
    /// rule over the same forked fleet `FleetRolloutKit`'s own tests use.
    private static func fleetRolloutExposure() async {
        let fleet = FleetSimulator.makeFleet(size: 2_000)
        let onTrain = FlagDefinition(
            key: "provider.structured_output_beta", salt: "ecosystem-demo-salt",
            variants: [Variant(key: "on", value: .bool(true)), Variant(key: "off", value: .bool(false))],
            defaultVariantKey: "off",
            rules: [RolloutRule(id: "duo-canary", predicate: .onTrain(["ios-27.1-duo"]), variantKey: "on")])
        let versionOrdered = onTrain.replacingRules([
            RolloutRule(id: "gte-27.1", predicate: .onTrain(["ios-27.1-duo", "ios-27.2"]), variantKey: "on")
        ])

        let onTrainEvaluator = Evaluator(
            document: ConfigDocument(documentVersion: 1, issuedAt: .now, flags: [onTrain]), fallback: .empty)
        let versionEvaluator = Evaluator(
            document: ConfigDocument(documentVersion: 1, issuedAt: .now, flags: [versionOrdered]), fallback: .empty)

        let onTrainTreated = FleetSimulator.exposure(
            of: onTrain.key, evaluator: onTrainEvaluator, fleet: fleet, treatedVariantKeys: ["on"]
        ).byVariant["on"] ?? 0
        let versionTreated = FleetSimulator.exposure(
            of: onTrain.key, evaluator: versionEvaluator, fleet: fleet, treatedVariantKeys: ["on"]
        ).byVariant["on"] ?? 0

        print("  A. onTrain(duo-only): \(onTrainTreated) / \(fleet.count) sessions get the beta")
        print("     osVersion >= 27.1 equivalent: \(versionTreated) / \(fleet.count) sessions get it")
        if onTrainTreated > 0 {
            let factor = Double(versionTreated) / Double(onTrainTreated)
            print(String(format: "     over-exposure factor: %.1fx", factor))
        }
    }

    /// B. the kill path, exercised for real against `ConfigStore`: publish the beta live, kill it,
    /// then replay the pre-kill document — the same stale-edge failure mode the README argues from.
    private static func fleetRolloutKillSurvivesReplay(meter: TokenMeter) async {
        let flag = FlagDefinition(
            key: "provider.structured_output_beta", salt: "ecosystem-demo-salt",
            variants: [Variant(key: "on", value: .bool(true)), Variant(key: "off", value: .bool(false))],
            defaultVariantKey: "off",
            rules: [RolloutRule(id: "everyone", predicate: .always, variantKey: "on")])
        let live = ConfigDocument(documentVersion: 5, issuedAt: .now.addingTimeInterval(-600), flags: [flag])
        let killed = ConfigDocument(documentVersion: 6, issuedAt: .now, flags: [flag.settingKilled(true)])
        let bundled = ConfigDocument(
            documentVersion: 0, issuedAt: .now.addingTimeInterval(-3_600), flags: [flag.settingKilled(true)])

        let store = ConfigStore(
            bundledFallback: bundled,
            transport: EcosystemFleetTransport(documents: [live, killed, live])
        )
        _ = await store.refresh()
        _ = await store.refresh()
        let replay = await store.refresh()

        let evaluator = await store.evaluator(fallback: .empty)
        let session = DeviceContext(
            stableIdentifier: "demo-session-1", buildTrain: .ios27_2, deviceClass: .phoneStandard,
            posture: .fixed, appBuild: 1_201)
        let assignment = evaluator.evaluate(flag.key, for: session)
        print("  B. replay of the pre-kill document: \(replay)")
        print("     this session's beta assignment=\(assignment.variantKey) reason=\(assignment.reason)"
            + " (kill held: \(assignment.reason == .killed ? "yes" : "NO -- REGRESSION"))")

        await meter.record(
            TokenUsage(promptTokens: 260, completionTokens: 90),
            for: ProviderIdentifier.fleetRolloutHost.rawValue
        )
    }
}

/// Serves three documents in order, ignoring `knownVersion` — the same shape as
/// `FleetRolloutKit`'s own demo's `SequencedTransport`, reused here as its own real collaborator
/// rather than reimplemented, since `ConfigTransport` is a one-method protocol built to be swapped.
private struct EcosystemFleetTransport: ConfigTransport {
    let documents: [ConfigDocument]
    let index = Counter()

    final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            let current = value
            value += 1
            return current
        }
    }

    func fetch(knownVersion: Int) async throws -> TransportResponse {
        .document(documents[min(index.next(), documents.count - 1)])
    }
}
