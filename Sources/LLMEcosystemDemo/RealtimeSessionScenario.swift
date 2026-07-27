import Foundation
import ProviderGatewayKit
import RealtimeSessionKit
import StructuredOutputKit
import TokenMeterKit

/// A twelfth provider identity, used only by the realtime-session scenario's
/// routed turns — registered with its own explicit rate in
/// `EcosystemDemo.buildMeter()` so every hop the session made, replays included,
/// bills at a real rate rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let realtimeHost = ProviderIdentifier("realtime-host")
}

/// One routed turn's token accounting, kept so the scenario can bill the whole
/// session — including the hop a replay caused — in one go.
struct RoutedHop: Sendable {
    let id: String
    let promptTokens: Int
    let completionTokens: Int
}

/// `RealtimeSessionKit`'s `RealtimeTransport` seam wired to a real routed
/// `ProviderRouter`/`LLMSession` pair, so the session's turns genuinely go
/// through `ProviderGatewayKit` instead of into a stub.
///
/// The `open` behaviour is what a durable-session server actually does: a client
/// arriving with no cursor gets a new session, and a client arriving *with* one
/// gets that session continued. The session layer, not the transport, decides
/// whether asking is worth it — past the resume window it opens with no cursor.
actor GatewayRealtimeTransport: RealtimeTransport {
    private let replies: [String: String]
    private let decoder: StructuredOutputDecoder
    private let providerID: ProviderIdentifier
    private var hops: [RoutedHop] = []
    private var openCount = 0

    init(replies: [String: String], decoder: StructuredOutputDecoder, providerID: ProviderIdentifier) {
        self.replies = replies
        self.decoder = decoder
        self.providerID = providerID
    }

    func open(resume cursor: SessionCursor?) async throws -> HandshakeResult {
        openCount += 1
        guard let cursor else {
            return .fresh(token: "sess-live-\(openCount)")
        }
        return .resumed(cursor: cursor)
    }

    /// Routes the turn and validates the reply. A reply that does not decode
    /// throws, which leaves the event pending in the outbox rather than failing
    /// the session — the same seam `RetryPolicyKit` would slot into.
    func transmit(_ event: OutboundEvent) async throws {
        let router = ProviderRouter(providers: [
            ScriptedProvider(identifier: providerID, script: [replies[event.id] ?? "{}"])
        ])
        let response = try await LLMSession(router: router).send(event.payload)
        _ = try await decoder.decode(WeatherReport.self, from: response.text)
        hops.append(
            RoutedHop(
                id: event.id,
                promptTokens: event.payload.count / 4,
                completionTokens: response.text.count / 4
            )
        )
    }

    func close() async {}

    /// Every routed hop, in write order — the replay after the resume included,
    /// because at-least-once delivery genuinely costs that second hop.
    func routedHops() -> [RoutedHop] {
        hops
    }

    func replyText(forHopAt index: Int) -> String {
        guard index < hops.count else { return "{}" }
        return replies[hops[index].id] ?? "{}"
    }
}

extension EcosystemDemo {
    /// The eighteenth scenario: `RealtimeSessionKit` holds a live LLM session
    /// together across a socket drop, with every turn going out through a real
    /// `ProviderRouter`/`LLMSession` via `GatewayRealtimeTransport`.
    ///
    /// Four guarantees show up in the output. A turn that was never acknowledged
    /// is **replayed** on resume — visibly costing a second gateway hop, which is
    /// what at-least-once actually means. The resume asks the server to continue
    /// from the client's own cursor rather than starting over. A buffered server
    /// event is accepted once and its immediate redelivery is **caught by the id
    /// window**. And the outbox drains to zero only once the server has
    /// acknowledged both turns.
    ///
    /// This sits underneath `StreamAggregatorKit`: that package reassembles the
    /// deltas of one response, this one owns the session those responses arrive
    /// on. Neither has a compile-time dependency on the other.
    static func runRealtimeSessionScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let transport = GatewayRealtimeTransport(
            replies: [
                "c1": #"{"city": "Denver", "temperatureCelsius": 21.5, "conditions": "clear"}"#,
                "c2": #"{"city": "Boulder", "temperatureCelsius": 19.0, "conditions": "cloudy"}"#
            ],
            decoder: decoder,
            providerID: .realtimeHost
        )
        let recorder = InMemorySessionEventRecorder()
        let session = RealtimeSession(
            transport: transport,
            backoff: BackoffPolicy(
                baseTicks: 250,
                capTicks: 8000,
                jitter: DeterministicJitter(numerator: 1, denominator: 2)
            ),
            budget: RetryBudget(maxAttempts: 3),
            resumePolicy: ResumePolicy(windowTicks: 30),
            recorder: recorder
        )

        do {
            try await runLiveTurnThenDrop(session: session, transport: transport)
            await billSessionHops(transport: transport, meter: meter)
            let events = await recorder.events().count
            print("[realtime-session scenario] \(events) session events recorded, trail is timestamp-free")
        } catch {
            print("[realtime-session scenario] FAILED: \(error)")
        }
    }

    /// One acknowledged turn, one turn whose ack never arrives, a drop, a resume,
    /// and the replay plus dedup that follow.
    private static func runLiveTurnThenDrop(
        session: RealtimeSession,
        transport: GatewayRealtimeTransport
    ) async throws {
        let opened = try await session.connect()
        let token = await session.resumeCursor()?.token ?? "none"
        print("[realtime-session scenario] connect -> \(describe(opened)), token \(token)")

        let first = try await session.enqueue("What's the weather in Denver?")
        let firstReply = await transport.replyText(forHopAt: 0)
        let inbound = await session.receive(ServerEvent(id: "srv-1", sequence: 1, body: firstReply))
        let acked = await session.acknowledge(first.id)
        print("[realtime-session scenario] turn \(first.id) routed through the gateway; "
            + "srv-1 \(inbound), ack \(acked)")

        let second = try await session.enqueue("And in Boulder?")
        let plan = try await session.handleDisconnect()
        print("[realtime-session scenario] socket dropped with \(second.id) unacked -> \(plan)")

        let resumed = try await session.reconnect(elapsedTicks: 4)
        let hops = await transport.routedHops().count
        print("[realtime-session scenario] reconnect(4 ticks) -> \(describe(resumed)); "
            + "\(second.id) replayed, so 2 turns cost \(hops) gateway hops")

        let secondReply = await transport.replyText(forHopAt: 1)
        let buffered = await session.receive(ServerEvent(id: "srv-2", sequence: 2, body: secondReply))
        let redelivered = await session.receive(ServerEvent(id: "srv-2", sequence: 2, body: secondReply))
        print("[realtime-session scenario] buffered srv-2 \(buffered), redelivery \(redelivered)")

        _ = await session.acknowledge(second.id)
        let stats = await session.statistics()
        print("[realtime-session scenario] outbox drained: pending \(await session.pendingEvents().count), "
            + "acked \(stats.acknowledged), retransmitted \(stats.retransmitted), resumes \(stats.resumes)")
    }

    /// Bills every hop the session made under `realtime-host`, replay included.
    private static func billSessionHops(transport: GatewayRealtimeTransport, meter: TokenMeter) async {
        let hops = await transport.routedHops()
        let prompt = hops.reduce(0) { $0 + $1.promptTokens }
        let completion = hops.reduce(0) { $0 + $1.completionTokens }
        await meter.record(
            TokenMeterKit.TokenUsage(promptTokens: prompt, completionTokens: completion),
            for: ProviderIdentifier.realtimeHost.rawValue
        )
        let cost = await meter.cost(for: ProviderIdentifier.realtimeHost.rawValue)
        print("[realtime-session scenario] \(hops.count) hops billed under realtime-host: "
            + "\(prompt)+\(completion) tokens, $\(cost)")
    }

    /// Trims the module qualifier `String(describing:)` puts on a nested enum, so
    /// the demo output reads as the API does.
    private static func describe(_ decision: ResumeDecision) -> String {
        String(describing: decision).replacingOccurrences(of: "RealtimeSessionKit.", with: "")
    }
}
