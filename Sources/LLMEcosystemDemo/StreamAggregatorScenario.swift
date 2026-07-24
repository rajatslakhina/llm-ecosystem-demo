import Foundation
import ProviderGatewayKit
import StreamAggregatorKit
import TokenMeterKit
import ToolRegistryKit

/// A tenth provider identity, used only by the stream-aggregator scenario's
/// streamed hop — registered with its own explicit rate in
/// `EcosystemDemo.buildMeter()` so the streamed round trip's cost is visible
/// rather than silently defaulting to $0.
extension ProviderIdentifier {
    static let streamHost = ProviderIdentifier("stream-host")
}

extension EcosystemDemo {
    /// The sixteenth scenario: `StreamAggregatorKit` reassembles what a
    /// streaming provider emits over SSE — a content preamble plus a tool call
    /// whose arguments arrive as interleaved fragments — back into one
    /// `AssembledMessage`, and the rest of the stack acts on it. The
    /// reassembled tool call is dispatched through `ToolRegistryKit`, and the
    /// streamed `usage` the aggregator carried through is billed by
    /// `TokenMeter` at its exact counts rather than re-estimated from text.
    ///
    /// This is the front of the pipeline. `ProviderGatewayKit`'s scripted
    /// providers collapse a reply to a single `.completed` event
    /// (`supportsStreaming: false`); `StreamAggregatorKit` is the assembly
    /// layer a real streamed send would feed, with no compile-time dependency
    /// on the gateway — the `DeltaSource` is the only seam.
    static func runStreamAggregatorScenario(meter: TokenMeter) async {
        let recorder = InMemoryAggregationEventRecorder()
        let aggregator = StreamAggregator(recorder: recorder)
        do {
            let message = try await aggregator.aggregate(from: streamHostDeltaSource())
            guard let call = message.toolCalls.first else {
                print("[stream-aggregator scenario] FAILED: no tool call was reassembled")
                return
            }
            let folded = await aggregator.stats.deltasFolded
            print(
                "[stream-aggregator scenario] reassembled \(message.toolCalls.count) tool call from "
                    + "\(folded) streamed deltas: \(call.name)(\(call.arguments)), "
                    + "preamble \"\(message.content)\""
            )
            await dispatchReassembledCall(call)
            await billStreamedUsage(message.usage, meter: meter)
            let events = await recorder.events.count
            let finish = message.finishReason.map { "\($0)" } ?? "none"
            print("[stream-aggregator scenario] \(events) aggregation events recorded (finish \(finish))")
        } catch {
            print("[stream-aggregator scenario] FAILED: \(error)")
        }
    }

    /// What the stream-host provider would push over SSE for "What's the
    /// weather in Denver?": a short preamble, then a get_weather tool call
    /// whose JSON arguments dribble out across two fragments, then the terminal
    /// finish reason and the streamed usage.
    private static func streamHostDeltaSource() -> ScriptedDeltaSource {
        ScriptedDeltaSource([
            .role("assistant"),
            .content("Looking that up "),
            .content("for you."),
            .toolCall(index: 0, id: "call_stream_1", name: "get_weather", argumentsFragment: "{\"city\":"),
            .toolCall(index: 0, id: nil, name: nil, argumentsFragment: " \"Denver\"}"),
            .usage(promptTokens: 30, completionTokens: 14),
            .finish(.toolCalls)
        ])
    }

    /// Dispatches the reassembled tool call through `ToolRegistryKit`, exactly
    /// as the tool-calling scenario dispatches a decided call — the only
    /// difference is that this call arrived as a stream.
    private static func dispatchReassembledCall(_ call: AssembledToolCall) async {
        let toolRegistry = await buildToolRegistry()
        let dispatch = await toolRegistry.dispatch(
            ToolRegistryKit.ToolCallRequest(
                id: call.id ?? "call-stream",
                toolName: call.name,
                argumentsJSON: Data(call.arguments.utf8)
            )
        )
        guard case .success(let toolOutput) = dispatch.outcome else {
            print("[stream-aggregator scenario] FAILED: tool dispatch did not succeed: \(dispatch.outcome)")
            return
        }
        let encoded = (try? JSONEncoder().encode(toolOutput)) ?? Data()
        let toolOutputJSON = String(data: encoded, encoding: .utf8) ?? "{}"
        print("[stream-aggregator scenario] dispatched \(call.name) -> \(toolOutputJSON)")
    }

    /// Bills the streamed usage at its exact counts. Because the aggregator
    /// carried the stream's own token accounting through, `TokenMeter` records
    /// the real 30 + 14 rather than an estimate from the assembled text.
    private static func billStreamedUsage(_ usage: StreamAggregatorKit.TokenUsage?, meter: TokenMeter) async {
        guard let usage else { return }
        await meter.record(
            TokenMeterKit.TokenUsage(promptTokens: usage.promptTokens, completionTokens: usage.completionTokens),
            for: ProviderIdentifier.streamHost.rawValue
        )
        let cost = await meter.cost(for: ProviderIdentifier.streamHost.rawValue)
        print(
            "[stream-aggregator scenario] streamed usage "
                + "\(usage.promptTokens)+\(usage.completionTokens) tokens "
                + "billed under stream-host: $\(cost)"
        )
    }
}
