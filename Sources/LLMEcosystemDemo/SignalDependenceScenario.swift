import AbstentionPolicyAnswerability
import AbstentionPolicyKit
import AnswerabilityKit
import Foundation
import MorphologyMatchAnswerability
import MorphologyMatchKit
import SignalDependenceAbstention
import SignalDependenceKit
import SourceIndependenceKit
import TokenMeterKit

extension EcosystemDemo {
    /// The thirty-seventh scenario: **the panel that stopped scenario 36 was not four judges.**
    ///
    /// Scenario 36 established that several judges each holding a survivable weakness add up to a
    /// turn worth declining. It counted origins to get there. This one asks the question that
    /// counting cannot: were those origins separate?
    ///
    /// Two of them are not, and the demo does not assert it — it derives it. The morphology judge
    /// *is* the answerability engine with its matcher swapped, so their agreement is one technique
    /// agreeing with itself. The independence and temporal judges were handed passages carrying
    /// the same document ids, which is a shared input by measurement rather than by declaration.
    static func runSignalDependenceScenario(meter: TokenMeter) async {
        print("[signal dependence scenario] four judges, and how many of them are one judge")

        let corpus = Self.weakCorpus
        let signals = await Self.dependenceSignals(for: corpus)
        print("  A. what each judge said about the same turn")
        for signal in signals { print("    \(signal.summary)") }

        let graph = Self.dependenceGraph(for: corpus)
        print("  B. what they share, derived rather than declared")
        for edge in graph.edges { print("    \(edge.summary)") }

        let panel = await AbstentionSignalReducer().reduce(signals, using: graph)
        print("  C. the panel, deflated")
        print("    \(panel.report.explanation)")
        let effective = String(format: "%.2f", panel.report.effectiveVoices)
        print("    effective votes \(effective) of \(panel.report.nominalCount)")

        let arbiter = AbstentionArbiter(policy: .standard)
        print("  D. the same arbiter, ruling on origins and then on voices")
        print("    counting judges  \(arbiter.rule(on: signals).decision.summary)")
        print("    counting voices  \(arbiter.rule(on: panel.signals).decision.summary)")

        await Self.auditDependence(corpus: corpus)
        await Self.runDeflatedCorpus(Self.strongCorpus, arbiter: arbiter, meter: meter)
        print("  Corroboration is only worth anything between judges that could have disagreed.")
    }

    /// Four readings, every one of them from an analyser that actually ran.
    ///
    /// The morphology judge is deliberately built from the same `AnswerabilityEngine` type as the
    /// answerability judge, differing only in its matcher. That is not a contrivance for the
    /// scenario — it is how `MorphologyMatchKit` is wired into this demo in scenario 31, and it is
    /// exactly why the two cannot corroborate each other.
    private static func dependenceSignals(for corpus: AbstentionCorpus) async -> [AbstentionSignal] {
        var signals = await Self.abstentionSignals(for: corpus)

        let lenient = AnswerabilityEngine(policy: .lenient, matcher: MorphologyEvidenceMatcher())
        let morphologyReport = lenient.assess(Question(corpus.question), against: corpus.evidence)
        let morphologySignal = AnswerabilitySignalMapper(
            origin: SignalOrigin("morphology"),
            blockingExpression: .concern(.moderate)
        ).signal(for: morphologyReport)

        // The gate reading clean is the case worth carrying: a judge that found nothing still
        // occupies a seat, and whether that seat is its own is the whole question here.
        signals.append(morphologySignal.reading.isClear
            ? AbstentionSignal(
                origin: SignalOrigin("morphology"),
                reading: .concern(.low, "matched only after morphological conflation")
            )
            : morphologySignal)
        return signals
    }

    /// The shared-input edge is measured off the corpus, not written down by hand.
    ///
    /// Independence reads passages and the temporal pass reads observations. If the ids overlap
    /// they are reading the same documents, and no amount of separate analysis makes their
    /// agreement independent. Declaring this by hand would be a guess that ages; intersecting the
    /// ids is a fact about the corpus in front of them.
    private static func dependenceGraph(for corpus: AbstentionCorpus) -> DependenceGraph {
        var edges = [
            DependenceEdge("answerability", "morphology", mechanism: .sharedHeuristic)
        ]
        let passageIDs = Set(corpus.passages.map(\.id))
        let observationIDs = Set(corpus.observations.map(\.id))
        let shared = passageIDs.intersection(observationIDs)
        if !shared.isEmpty {
            let overlap = Double(shared.count) / Double(passageIDs.union(observationIDs).count)
            edges.append(
                DependenceEdge("independence", "temporal", mechanism: .sharedInput, strength: overlap)
            )
        }
        return DependenceGraph(edges: edges)
    }

    /// The half a declared graph cannot cover.
    ///
    /// Both corpora are run through the same judges and every concurring set is recorded. A pair
    /// that has never once fired apart is behaving as one judge whatever the graph says, and the
    /// registry is the only thing here that can notice.
    private static func auditDependence(corpus: AbstentionCorpus) async {
        let registry = DependenceRegistry(graph: Self.dependenceGraph(for: corpus))
        for sample in [corpus, Self.strongCorpus] {
            for _ in 0..<3 {
                let raised = await Self.dependenceSignals(for: sample)
                    .filter { $0.reading.concernSeverity != nil || $0.reading.isRefusal }
                    .map { DependenceOrigin($0.origin.rawValue) }
                await registry.record(concurring: raised)
            }
        }
        let warnings = await registry.undeclaredEntanglement()
        print("  E. pairs behaving as one judge that nobody declared (\(await registry.observedRounds) rounds)")
        if warnings.isEmpty {
            print("    none — every co-firing pair is already accounted for in the graph")
        } else {
            for warning in warnings { print("    \(warning.summary)") }
        }
    }

    /// A corpus with nothing to hold against it, through the same deflation.
    ///
    /// The reduction has to be able to let a turn through, or it is a way of never answering
    /// rather than a way of counting. Merging two clean judges into one clean voice lowers the
    /// coverage available to the floor, so this is also the case that would catch a deflation
    /// tuned so tightly that nothing survives it.
    private static func runDeflatedCorpus(
        _ corpus: AbstentionCorpus,
        arbiter: AbstentionArbiter,
        meter: TokenMeter
    ) async {
        let signals = await Self.dependenceSignals(for: corpus)
        let panel = await AbstentionSignalReducer().reduce(signals, using: Self.dependenceGraph(for: corpus))
        let ruling = arbiter.rule(on: panel.signals)
        print("  F. a corpus that holds up, through the same deflation")
        print("    \(panel.report.explanation)")
        print("    ruling          \(ruling.decision.summary)")
        await Self.spendIfAnswerable(ruling, meter: meter, label: "rollback timing")
    }
}
