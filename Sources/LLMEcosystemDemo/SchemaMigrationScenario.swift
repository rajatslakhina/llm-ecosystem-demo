import Foundation
import ProviderGatewayKit
import SchemaMigrationKit
import StructuredOutputKit
import TokenMeterKit

/// A fourteenth provider identity, used only by the schema-migration scenario's
/// one live routed turn — registered with its own explicit rate in
/// `EcosystemDemo.buildMeter()` so the single hop bills at a real rate rather
/// than silently $0.
extension ProviderIdentifier {
    static let schemaHost = ProviderIdentifier("schema-host")
}

/// The one adapter `SchemaMigrationKit`'s README promises: `FieldValue` in, JSON
/// text out, and back. The package owns its own value vocabulary so it has no
/// compile-time dependency on `StructuredOutputKit`; this is what that costs.
enum FieldValueJSON {

    /// Emits JSON with keys in sorted order, so the demo's output is byte-stable.
    static func text(_ payload: [String: FieldValue]) -> String {
        let body = payload
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \(literal($0.value))" }
            .joined(separator: ", ")
        return "{\(body)}"
    }

    static func payload(from json: String) -> [String: FieldValue] {
        let data = Data(json.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.reduce(into: [String: FieldValue]()) { result, entry in
            result[entry.key] = value(from: entry.value)
        }
    }

    private static func value(from raw: Any) -> FieldValue {
        if let text = raw as? String {
            return .string(text)
        }
        guard let number = raw as? NSNumber else {
            return .null
        }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .boolean(number.boolValue)
        }
        return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .integer(number.intValue)
    }

    private static func literal(_ value: FieldValue) -> String {
        switch value {
        case .string(let text): return "\"\(text)\""
        case .integer(let number): return "\(number)"
        case .double(let number): return "\(number)"
        case .boolean(let flag): return flag ? "true" : "false"
        case .array, .object, .null: return "null"
        }
    }
}

extension EcosystemDemo {

    /// The twentieth scenario: `SchemaMigrationKit` makes a payload written under
    /// an older contract readable by today's decoder — without asking a provider
    /// to re-generate it.
    ///
    /// This is the third distinct answer this toolkit gives to "the same work
    /// twice". `ResponseCacheKit` avoids a second hop for an identical question.
    /// `IdempotencyKit` avoids a second hop for a retried side effect. Here the
    /// cached answer is not identical and not retried — it is *stale in shape* —
    /// and the fix is still zero hops, because a schema migration is local
    /// computation. The one hop this scenario does spend is the live turn, and it
    /// exists to show the other half: when producer and consumer already agree,
    /// negotiation returns `.exact` and no migration runs at all.
    static func runSchemaMigrationScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let registry = SchemaRegistry(recorder: InMemoryMigrationEventRecorder())
        guard await setUpWeatherContract(registry) else {
            print("[schema-migration scenario] FAILED: contract registration")
            return
        }
        await classifyTheVersionChange(registry)
        await readAStalePayload(registry, decoder: decoder)
        await routeALiveTurnAndNegotiate(registry, decoder: decoder, meter: meter)
        await serveAClientStillOnV1(registry)

        let stats = await registry.statistics()
        print("[schema-migration scenario] \(stats)")
    }

    /// v1 is what the first release stored: a numeric condition code and the
    /// weather station that reported it. v2 is exactly what today's
    /// `WeatherReport` decoder wants — and it stopped recording the station.
    private static func setUpWeatherContract(_ registry: SchemaRegistry) async -> Bool {
        let contract = ContractDefinition(
            id: "weather.report",
            versions: [
                ContractVersionDefinition(
                    version: 1,
                    schema: ContractSchema([
                        .required("city", .string),
                        .required("temperatureCelsius", .double),
                        .required("conditionCode", .integer),
                        .optional("stationId", .string)
                    ])
                ),
                ContractVersionDefinition(
                    version: 2,
                    schema: ContractSchema([
                        .required("city", .string),
                        .required("temperatureCelsius", .double),
                        .required("conditions", .string)
                    ])
                )
            ]
        )
        do {
            try await registry.register(contract)
            try await registerSteps(registry)
            return true
        } catch {
            print("[schema-migration scenario] setup error: \(error)")
            return false
        }
    }

    /// conditionCode is folded into conditions, so that part is lossless.
    /// stationId is not: v2 has nowhere to put it, and the step says so.
    /// Going back is lossless — the band maps cleanly onto a code, and v1 never
    /// required a station id.
    private static func registerSteps(_ registry: SchemaRegistry) async throws {
        try await registry.registerStep(
            PayloadMigration(from: 1, to: 2, loss: .lossy(drops: ["stationId"])) { payload in
                var next = payload
                if case .integer(let code) = payload["conditionCode"] {
                    next["conditions"] = .string(Self.band(for: code))
                }
                next["conditionCode"] = nil
                next["stationId"] = nil
                return next
            },
            for: "weather.report"
        )
        try await registry.registerStep(
            PayloadMigration(from: 2, to: 1) { payload in
                var next = payload
                if case .string(let band) = payload["conditions"] {
                    next["conditionCode"] = .integer(Self.code(for: band))
                }
                next["conditions"] = nil
                return next
            },
            for: "weather.report"
        )
    }

    private static let bands = ["clear", "cloudy", "rain", "storm"]

    private static func band(for code: Int) -> String {
        bands.indices.contains(code) ? bands[code] : "clear"
    }

    private static func code(for band: String) -> Int {
        bands.firstIndex(of: band) ?? 0
    }

    private static func classifyTheVersionChange(_ registry: SchemaRegistry) async {
        guard let verdict = try? await registry.compatibility(of: "weather.report", from: 1, to: 2) else {
            return
        }
        let reasons = verdict.changes.map(\.description).joined(separator: "; ")
        print("[schema-migration scenario] v1 -> v2 is "
            + "\(verdict.isBreaking ? "BREAKING" : "compatible") — \(reasons)")
    }

    /// A reply cached under last year's contract, read by today's decoder.
    ///
    /// Reading your own cache *forward* is still a decision: the step admits it
    /// cannot carry the station id across, so the migration is refused until the
    /// caller says that is acceptable.
    private static func readAStalePayload(_ registry: SchemaRegistry, decoder: StructuredOutputDecoder) async {
        let cached = #"{"city": "Shimla", "temperatureCelsius": 8.5, "conditionCode": 3, "stationId": "IN-SML-04"}"#
        print("[schema-migration scenario] cached v1 reply: \(cached)")
        do {
            _ = try await decoder.decode(WeatherReport.self, from: cached)
            print("[schema-migration scenario] decoded the v1 text directly — unexpected")
        } catch {
            print("[schema-migration scenario] today's decoder on the v1 text: rejected")
        }
        let stale = FieldValueJSON.payload(from: cached)
        do {
            _ = try await registry.migrate(stale, of: "weather.report", from: 1, to: 2)
            print("[schema-migration scenario] lossy upgrade unexpectedly allowed")
        } catch {
            print("[schema-migration scenario] upgrade refused — \(error)")
        }
        do {
            let result = try await registry.migrate(
                stale,
                of: "weather.report",
                from: 1,
                to: 2,
                allowingLoss: true
            )
            let text = FieldValueJSON.text(result.payload)
            let report = try await decoder.decode(WeatherReport.self, from: text)
            print("[schema-migration scenario] migrated \(result.path), 0 gateway hops, "
                + "dropped \(result.droppedFields.joined(separator: ", ")) — \(text)")
            print("[schema-migration scenario] decoded after migration: \(report)")
        } catch {
            print("[schema-migration scenario] migration FAILED: \(error)")
        }
    }

    /// One real routed turn. Its reply already satisfies v2, so negotiation
    /// returns `.exact` and nothing is migrated.
    private static func routeALiveTurnAndNegotiate(
        _ registry: SchemaRegistry,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async {
        let reply = #"{"city": "Shimla", "temperatureCelsius": 8.5, "conditions": "storm"}"#
        let prompt = "Report the current weather for Shimla."
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: .schemaHost, script: [reply])
        ])
        do {
            let response = try await LLMSession(router: router).send(prompt)
            let report = try await decoder.decode(WeatherReport.self, from: response.text)
            let outcome = try await registry.negotiate(
                "weather.report",
                producerVersion: 2,
                consumerVersion: 2
            )
            print("[schema-migration scenario] live turn via \(response.providerID) -> \(report.conditions); "
                + "negotiate(v2, v2) = \(outcome)")
            let promptTokens = prompt.count / 4
            let completionTokens = response.text.count / 4
            await meter.record(
                TokenMeterKit.TokenUsage(promptTokens: promptTokens, completionTokens: completionTokens),
                for: ProviderIdentifier.schemaHost.rawValue
            )
            let cost = await meter.cost(for: ProviderIdentifier.schemaHost.rawValue)
            print("[schema-migration scenario] 1 gateway hop billed under schema-host: "
                + "\(promptTokens)+\(completionTokens) tokens, $\(cost)")
        } catch {
            print("[schema-migration scenario] live turn FAILED: \(error)")
        }
    }

    /// A client that has not shipped v2 yet. This direction loses nothing — the
    /// band maps back onto a code — so it needs no opt-in, which is the contrast
    /// that makes the refusal above mean something.
    private static func serveAClientStillOnV1(_ registry: SchemaRegistry) async {
        let current: [String: FieldValue] = [
            "city": .string("Shimla"),
            "temperatureCelsius": .double(8.5),
            "conditions": .string("storm")
        ]
        do {
            let result = try await registry.migrate(current, of: "weather.report", from: 2, to: 1)
            print("[schema-migration scenario] serving a v1 client: \(FieldValueJSON.text(result.payload)) "
                + "(\(result.direction), dropped nothing)")
        } catch {
            print("[schema-migration scenario] downgrade FAILED: \(error)")
        }
    }
}
