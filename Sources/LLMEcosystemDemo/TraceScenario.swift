import Foundation
import ProviderGatewayKit
import StructuredOutputKit
import TokenMeterKit
import ToolRegistryKit
import TraceKit

private func describeStatus(_ status: SpanStatus) -> String {
    switch status {
    case .unset:
        return "UNSET"
    case .ok:
        return "OK"
    case .error(let message):
        return "ERROR (\(message))"
    }
}

extension EcosystemDemo {
    /// The eighth scenario: `TraceKit` wraps the same tool-calling round
    /// trip pattern the earlier scenario hand-rolled — a routed decision
    /// turn, a schema-validated `ToolRegistryKit` dispatch, and a routed
    /// final turn — each captured as a nested `Span` under one manually
    /// managed root `agentStep` span. Reconstructing that trace and running
    /// it through `EvalGate` turns "did every hop succeed, and quickly
    /// enough" into an enforced pass/fail check instead of eyeballed print
    /// output, exactly the trace-to-eval workflow `TraceKit` exists for.
    static func runTraceScenario(decoder: StructuredOutputDecoder, meter: TokenMeter) async {
        let tracer = Tracer()
        let toolRegistry = await buildToolRegistry()
        let rootID = await tracer.startSpan(name: "agent.weatherLookup", kind: .agentStep)
        let context = TracedContext(tracer: tracer, rootID: rootID, providerID: .selfHosted)

        do {
            let finalValue = try await runTracedRoundTrip(
                context: context,
                toolRegistry: toolRegistry,
                decoder: decoder,
                meter: meter
            )
            await tracer.endSpan(rootID, status: .ok)
            print("[trace scenario] traced round trip \u{2192} final answer: \(finalValue)")
        } catch {
            await tracer.endSpan(rootID, status: .error(String(describing: error)))
            print("[trace scenario] FAILED: \(error)")
        }

        let trace = await tracer.trace(rootID: rootID)
        for span in trace {
            let duration = span.durationMs.map { String(format: "%.0fms", $0) } ?? "n/a"
            print("  span: [\(span.kind.rawValue)] \(span.name) \u{2014} \(describeStatus(span.status)) (\(duration))")
        }

        let gate = EvalGate()
        let scorers: [any EvalScorer] = [NoErrorSpansScorer(), MaxDurationScorer(maxDurationMs: 5000)]
        let report = await gate.run(trace, scorers: scorers)
        print("[trace scenario] EvalGate passed: \(report.passed) (\(trace.count) spans scored)")
    }

    /// Bundles the tracer, the trace's root span id, and the provider
    /// identity every step of the traced round trip shares — keeps each
    /// helper function below under SwiftLint's parameter-count limit.
    private struct TracedContext {
        let tracer: Tracer
        let rootID: UUID
        let providerID: ProviderIdentifier
    }

    /// Runs the routed decide \u{2192} dispatch \u{2192} answer round trip, delegating
    /// each step to its own traced helper, and returns the decoded final
    /// answer.
    private static func runTracedRoundTrip(
        context: TracedContext,
        toolRegistry: ToolRegistryKit.ToolRegistry,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws -> ToolBackedAnswer {
        let call = try await decideToolCall(context: context, meter: meter)
        let toolOutputJSON = try await dispatchTool(context: context, call: call, toolRegistry: toolRegistry)
        return try await answerWithToolResult(
            context: context,
            call: call,
            toolOutputJSON: toolOutputJSON,
            decoder: decoder,
            meter: meter
        )
    }

    /// Routes a decision turn (traced as `llm.decide`) and decodes it into
    /// a `ScriptedToolCall`.
    private static func decideToolCall(context: TracedContext, meter: TokenMeter) async throws -> ScriptedToolCall {
        let decisionScript = #"{"tool": "get_weather", "arguments": {"city": "Seattle"}}"#
        let decisionRouter = ProviderRouter(providers: [
            ScriptedProvider(identifier: context.providerID, script: [decisionScript])
        ])
        let decisionSession = LLMSession(router: decisionRouter)
        let decisionPrompt = "What's the weather in Seattle? Call get_weather if needed."

        let decisionResponse = try await context.tracer.withSpan(
            name: "llm.decide",
            kind: .llmCall,
            parentID: context.rootID,
            attributes: ["provider": context.providerID.rawValue]
        ) { _ in
            try await decisionSession.send(decisionPrompt)
        }
        await meter.record(
            TokenUsage(promptTokens: decisionPrompt.count / 4, completionTokens: decisionResponse.text.count / 4),
            for: context.providerID.rawValue
        )

        return try JSONDecoder().decode(ScriptedToolCall.self, from: Data(decisionResponse.text.utf8))
    }

    /// Dispatches `call` through `toolRegistry` (traced as `tool.<name>`)
    /// and returns its JSON-encoded output.
    private static func dispatchTool(
        context: TracedContext,
        call: ScriptedToolCall,
        toolRegistry: ToolRegistryKit.ToolRegistry
    ) async throws -> String {
        let argumentsData = try JSONEncoder().encode(call.arguments)
        let dispatchResult = await context.tracer.withSpan(
            name: "tool.\(call.tool)",
            kind: .toolCall,
            parentID: context.rootID
        ) { _ in
            await toolRegistry.dispatch(
                ToolRegistryKit.ToolCallRequest(id: "trace-call-1", toolName: call.tool, argumentsJSON: argumentsData)
            )
        }

        guard case .success(let toolOutput) = dispatchResult.outcome else {
            throw TraceScenarioError.toolDispatchFailed
        }
        return String(data: try JSONEncoder().encode(toolOutput), encoding: .utf8) ?? "{}"
    }

    /// Routes a final turn (traced as `llm.finalAnswer`) with the tool's
    /// output folded in, and decodes it into a `ToolBackedAnswer`.
    private static func answerWithToolResult(
        context: TracedContext,
        call: ScriptedToolCall,
        toolOutputJSON: String,
        decoder: StructuredOutputDecoder,
        meter: TokenMeter
    ) async throws -> ToolBackedAnswer {
        let finalInstructions = PromptBuilder.instructions(
            for: ToolBackedAnswer.jsonSchema,
            typeName: "a ToolBackedAnswer"
        )
        let finalPrompt = "Tool '\(call.tool)' returned: \(toolOutputJSON). \(finalInstructions)"
        let finalRouter = ProviderRouter(providers: [
            ScriptedProvider(identifier: context.providerID, script: [toolOutputJSON])
        ])
        let finalSession = LLMSession(router: finalRouter)

        let finalResponse = try await context.tracer.withSpan(
            name: "llm.finalAnswer",
            kind: .llmCall,
            parentID: context.rootID,
            attributes: ["provider": context.providerID.rawValue]
        ) { _ in
            try await finalSession.send(finalPrompt)
        }
        await meter.record(
            TokenUsage(promptTokens: finalPrompt.count / 4, completionTokens: finalResponse.text.count / 4),
            for: context.providerID.rawValue
        )

        return try await decoder.decode(ToolBackedAnswer.self, from: finalResponse.text)
    }

    private enum TraceScenarioError: Error, CustomStringConvertible {
        case toolDispatchFailed

        var description: String { "tool dispatch did not succeed" }
    }
}
