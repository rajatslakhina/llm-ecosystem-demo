# LLM Ecosystem Demo

A single runnable demo that wires together all sixty packages in this
ecosystem — [`ProviderGatewayKit`](https://github.com/rajatslakhina/foundation-model-provider-gateway),
[`TokenMeterKit`](https://github.com/rajatslakhina/token-meter-kit),
[`StructuredOutputKit`](https://github.com/rajatslakhina/structured-output-kit),
[`ResponseCacheKit`](https://github.com/rajatslakhina/response-cache-kit),
[`ToolRegistryKit`](https://github.com/rajatslakhina/tool-registry-kit),
[`AgentLoopKit`](https://github.com/rajatslakhina/agent-loop-kit),
[`GuardrailKit`](https://github.com/rajatslakhina/guardrail-kit),
[`TraceKit`](https://github.com/rajatslakhina/trace-kit),
[`RetrievalKit`](https://github.com/rajatslakhina/retrieval-kit),
[`PromptTemplateKit`](https://github.com/rajatslakhina/prompt-template-kit),
[`RetryPolicyKit`](https://github.com/rajatslakhina/retry-policy-kit),
[`ContextCompactionKit`](https://github.com/rajatslakhina/context-compaction-kit),
[`AgentMemoryKit`](https://github.com/rajatslakhina/agent-memory-kit),
[`SemanticRouterKit`](https://github.com/rajatslakhina/semantic-router-kit),
[`OutputRepairKit`](https://github.com/rajatslakhina/output-repair-kit),
[`StreamAggregatorKit`](https://github.com/rajatslakhina/stream-aggregator-kit), and
[`BatchInferenceKit`](https://github.com/rajatslakhina/batch-inference-kit), and
[`RealtimeSessionKit`](https://github.com/rajatslakhina/realtime-session-kit), and
[`IdempotencyKit`](https://github.com/rajatslakhina/idempotency-kit), and
[`SchemaMigrationKit`](https://github.com/rajatslakhina/schema-migration-kit), and
[`ToolAuthorityKit`](https://github.com/rajatslakhina/tool-authority-kit), and
[`GroundingKit`](https://github.com/rajatslakhina/grounding-kit), and
[`QuotaGovernorKit`](https://github.com/rajatslakhina/quota-governor-kit), and
[`CostEstimatorKit`](https://github.com/rajatslakhina/cost-estimator-kit), and
[`WorkloadProfilerKit`](https://github.com/rajatslakhina/workload-profiler-kit), and
[`ClaimConsistencyKit`](https://github.com/rajatslakhina/claim-consistency-kit), and
[`LabelClockKit`](https://github.com/rajatslakhina/label-clock-kit)
[`SelectionTrustKit`](https://github.com/rajatslakhina/selection-trust-kit)
[`ArgumentAttributionKit`](https://github.com/rajatslakhina/argument-attribution-kit)
[`EffectiveVoteKit`](https://github.com/rajatslakhina/effective-vote-kit)
— against each other's real, tagged `1.0.0` releases. Where each package's
own demo shows that package in isolation, this one shows the seams between
them: a routed call that gets decoded into a typed value, metered for cost,
answered from cache on a repeat request, dispatched to a registered tool
and routed again for a final answer, driven through a multi-step
tool-calling loop until the model converges, captured as a nested trace
and scored by an eval gate, grounded in context retrieved from a small
indexed knowledge base before the model ever answers, rendered from a
versioned, rollback-capable prompt template before that render's own
output becomes the routed call's prompt text, retried with exponential
backoff after the provider genuinely fails at the transport layer,
compacted down to a token budget before the compacted result — not the
raw, ever-growing transcript — becomes the next routed call's context, or
recalled from a long-term memory store, ranked by more than raw
similarity, before that recalled context grounds the final answer, or
classified into a support intent by embedding distance so the matched
route's own metadata — not a hard-coded branch — picks which model answers,
or driven through a bounded, self-healing repair loop that re-prompts the
routed model with structured feedback until the reply satisfies its output
contract, or fanned out as a whole batch of prompts through one executor
with a hard cap on how many are in flight, coming back in input order with
one bad reply isolated to its own item instead of taking the job down.

| Package | Role in this demo |
|---|---|
| [`ProviderGatewayKit`](https://github.com/rajatslakhina/foundation-model-provider-gateway) | Routes every call through a real `ProviderRouter`/`LLMSession` |
| [`StructuredOutputKit`](https://github.com/rajatslakhina/structured-output-kit) | Builds the schema instructions and extracts/validates each routed reply |
| [`TokenMeterKit`](https://github.com/rajatslakhina/token-meter-kit) | Meters every routed hop against registered per-provider rates |
| [`ResponseCacheKit`](https://github.com/rajatslakhina/response-cache-kit) | Sits in front of the router so a repeated request never re-pays for a call |
| [`ToolRegistryKit`](https://github.com/rajatslakhina/tool-registry-kit) | Validates and dispatches a tool call the model "decides" to make, mid round trip |
| [`AgentLoopKit`](https://github.com/rajatslakhina/agent-loop-kit) | Drives a bounded, multi-step decide/act/observe loop across several dependent tool calls |
| [`GuardrailKit`](https://github.com/rajatslakhina/guardrail-kit) | Redacts PII and enforces content policy before a prompt is routed and after a reply comes back |
| [`TraceKit`](https://github.com/rajatslakhina/trace-kit) | Captures a nested trace of the routed calls and tool dispatch, then scores it with an `EvalGate` |
| [`RetrievalKit`](https://github.com/rajatslakhina/retrieval-kit) | Indexes a small knowledge base and retrieves the context grounding the final routed answer |
| [`PromptTemplateKit`](https://github.com/rajatslakhina/prompt-template-kit) | Versions a prompt template, renders the active version, and feeds that rendered text into a routed call |
| [`RetryPolicyKit`](https://github.com/rajatslakhina/retry-policy-kit) | Retries a routed call with exponential backoff after a genuine transport-layer failure |
| [`ContextCompactionKit`](https://github.com/rajatslakhina/context-compaction-kit) | Compacts a growing transcript down to a token budget before the next routed call |
| [`AgentMemoryKit`](https://github.com/rajatslakhina/agent-memory-kit) | Recalls long-term memories, ranked by similarity/recency/importance/frequency, to ground a routed answer |
| [`SemanticRouterKit`](https://github.com/rajatslakhina/semantic-router-kit) | Classifies a query into a support intent by embedding distance; the matched route's metadata picks which model the routed call targets |
| [`OutputRepairKit`](https://github.com/rajatslakhina/output-repair-kit) | Wraps a routed call in a bounded repair loop: rejects an invalid reply with structured issues, folds them into a correction prompt, and re-prompts until it validates or the budget is spent |
| [`StreamAggregatorKit`](https://github.com/rajatslakhina/stream-aggregator-kit) | Reassembles a streamed reply — content fragments and index-keyed tool-call argument fragments — into one message, then dispatches the reassembled tool call and bills the exact streamed usage under `stream-host` |
| [`BatchInferenceKit`](https://github.com/rajatslakhina/batch-inference-kit) | Runs a batch of prompts through one bounded-concurrency executor that forwards each item to the gateway, returns outcomes in input order, isolates the one off-contract reply, and hands its summed successful usage to `TokenMeter` under `batch-host` |
| [`RealtimeSessionKit`](https://github.com/rajatslakhina/realtime-session-kit) | Holds a live session together across a socket drop: an at-least-once outbox replays the turn the server never acknowledged (a second real gateway hop), the resume continues from the client's own cursor, a redelivered server event is caught by the id window, and every hop bills under `realtime-host` |
| [`IdempotencyKit`](https://github.com/rajatslakhina/idempotency-kit) | Guards a side-effecting routed call so it runs at most once: three attempts under one derived key cost a single gateway hop, the same key with a changed payload is refused, an indeterminate timeout freezes the key until a reconciler settles it, and only the hops that really ran bill under `idem-host` |
| [`SchemaMigrationKit`](https://github.com/rajatslakhina/schema-migration-kit) | Migrates a payload written under an older contract into the shape today's decoder wants, with every hop validated against the schema it promised: a cached v1 reply is classified as a breaking change, refused while it would silently drop a field, then migrated with the loss opted into and decoded by the real `StructuredOutputDecoder` — all at zero gateway hops |
| [`ToolAuthorityKit`](https://github.com/rajatslakhina/tool-authority-kit) | Refuses a tool call the rest of the pipeline was happy to pass along: a retrieved passage carries an injected instruction, the routed turn proposes the outbound send it asked for, and the broker denies it on the one axis no other layer models — where the arguments came from. The same grant allows a read from that same untrusted source, and escalates a refund to a human whose signature covers that refund and no other |
| [`GroundingKit`](https://github.com/rajatslakhina/grounding-kit) | Checks the answer itself against the passages it was given: `StructuredOutputKit` accepts the reply because the shape is valid, and `GroundingVerifier` then gives each sentence its own verdict — one grounded and correctly cited, one inflating a number its source refutes (`contradicted`, not merely unsupported), and one citing a document that was never retrieved. Under `.strip` the grounded remainder is published and the rest is named, at zero extra gateway hops |
| [`QuotaGovernorKit`](https://github.com/rajatslakhina/quota-governor-kit) | Decides whether the *next* hop may run at all. `reserve` holds an estimate on every scope of a `tenant / run` path before the gateway is called; `TokenMeter` prices the response; `settle` closes the reservation against that real figure, so the metered cost becomes the input to the next admission decision rather than a report at the end. One settlement comes in under its hold on tokens and over it on money at once. A run budget cuts a loop off at step 4 while the tenant never notices, and a badly estimated answer leaves its scope in arrears — the spend already happened, so all the governor can do is refuse what comes next |
| [`CostEstimatorKit`](https://github.com/rajatslakhina/cost-estimator-kit) | Supplies the estimate `QuotaGovernorKit` reserves against, instead of it being a literal. A `WorkloadPlan` describes the loop shape — steps, tool calls per step, tool-result size, cache hit rate, retry overhead, compaction — and the forecast walks the transcript forward step by step, because an agent loop resends everything said so far. In this scenario the flat estimate says 200 input tokens and the run really uses 715. Output length is the one value a plan cannot supply, so it sits behind a predictor protocol and is learned per shape; reconciling against `TokenMeter`'s real figure feeds both the predictor and the width of the band |
| [`WorkloadProfilerKit`](https://github.com/rajatslakhina/workload-profiler-kit) | Answers the question `CostEstimatorKit` leaves open: where does the *plan* come from? Inverts the forecast — from the per-hop input counts of runs that already happened it recovers steps, tool shape, output length, retry overhead, cache hit rate and compaction thresholds, reporting the share of observed input it cannot account for rather than absorbing it. Then it gates the hand-written plan against what the runs did: scenario 24's literal drifts on exactly one of seven fields, `expectedOutputTokensPerStep` declared 15 against 56 observed — the same field scenario 24's own 81% overrun is caused by |
| [`ClaimConsistencyKit`](https://github.com/rajatslakhina/claim-consistency-kit) | Asks the question overlap cannot: given the passage a claim already matched, do the two *agree*? Five deterministic rules — polarity, numerics with units and bounds, quantifier and modal scope, version ordering, mutually exclusive values — decided by reading two sentences, with no model call. Scenario 26 runs it on `GroundingKit`'s own matches: it agrees on the polarity flip, **withdraws a grounding false positive** (`5 times` against `at least 3 times` is a satisfied bound, not a conflict), and catches the two claims that carry neither negation nor numbers, so nothing in an overlap score can reach them |
| [`SourceConflictKit`](https://github.com/rajatslakhina/source-conflict-kit) | Asks the question every check above asks too late: do the retrieved passages agree with *each other*? Topic-scoped conflict groups, corroboration counted in distinct documents rather than chunks, an explicit tie-breaker ladder that stands aside rather than guessing, and a block when sources cannot be reconciled. Scenario 27 runs the same audit twice — once with the built-in lexical oracle, once with `ClaimConsistencyKit` plugged in through the `ContradictionOracle` seam — and the propositional oracle **withholds one fewer passage**, because the lexical one manufactures a conflict out of a satisfied bound |
| [`ClaimSegmenterKit`](https://github.com/rajatslakhina/claim-segmenter-kit) | The unit every check above takes for granted. Grounding, claim consistency and source conflict all begin by cutting text into claims, and all three inherit whatever that cut gets wrong — silently, because a claim lost at a boundary is never checked rather than reported as a miss. Protected spans for code, URLs and quotes; Markdown structure; and clause-level splitting that carries the subject forward or refuses the cut. Scenario 28 runs `GroundingKit`'s verifier twice over one answer, changing nothing but the segmenter behind its `ClaimSegmenting` seam |
| [`CitationBindingKit`](https://github.com/rajatslakhina/citation-binding-kit) | The question every verifier above skips: not *which document supports this claim best*, but *does the document the answer actually named support it*. A verifier that keeps the best-scoring source has no opinion about what was cited, and the finer a claim gets the more of its wording it shares with a near neighbour. Honours the citation over the score, and reports the divergence rather than silently rebinding. Scenario 29 runs it over the exact claims scenario 28 produced |
| [`ClaimDecontextualizerKit`](https://github.com/rajatslakhina/claim-decontextualizer-kit) | The step before every verifier above, and the one that decides whether they had anything to work with. A claim lifted out of a paragraph often has no subject — `It is not shared across sessions` cannot be scored correctly, only scored. Rewrites what a decisive antecedent justifies, and refuses in two directions: when candidates are too close to choose between, and when a correct-but-long antecedent would narrow the claim beyond what the sentence asserted. `standaloneText(at:)` returns `nil` for every refusal, so an unresolved claim cannot be forwarded by accident. Scenario 30 |
| [`AnswerabilityKit`](https://github.com/rajatslakhina/answerability-kit) | The only gate in this table that runs *before* the provider call. Every verifier above it judges an answer already paid for; this one judges whether the question was answerable from the retrieved evidence at all. Splits the question into aspects and checks each against the corpus, separating a gap (`insufficient` — retrieve more) from a contradiction (`contested` — retrieving more makes it worse) from the gate having no opinion (`undetermined` — it could not read the question, or was handed nothing to read). `approvedQuestion` is `nil` for every verdict but approval, so a caller that forgets to switch cannot spend money. Scenario 31 |
| [`MorphologyMatchKit`](https://github.com/rajatslakhina/morphology-match-kit) | The recall floor underneath the gate above it. `AnswerabilityKit` refuses when nothing in the corpus speaks to an aspect — but that is an inference from a matcher finding no overlap, and it is worth exactly what the matcher's recall is worth. Keys inflectional families onto one bucket so a question about `requests` that were `retried` matches a corpus saying a client `retries` a `request`. Inflectional rules only: no `-er`, no `-ation`, length floors, and no key may land on a function word, because `note` keying to `not` would make every clause mentioning a note read as a denial. Every refused conflation is reported as a rule rather than a silence. Scenario 32 |
| [`EvidenceSensitivityKit`](https://github.com/rajatslakhina/evidence-sensitivity-kit) | Asks how close a verdict came to being a different verdict, before anyone acts on it. Re-runs any judge over subsets of its own evidence: leave-one-passage-out, leave-one-document-out, and distance to the threshold. The document pass is the load-bearing half — three chunks of one page defeat passage-level leave-one-out entirely, since removing any one leaves two more. Also names the two coincidences: two weak sides landing inside `conflictMargin` because two different recall failures cancelled, and apparent corroboration that is one source read several times. Only `robust` is `isTrustworthy`; `undetermined` deliberately is not, so "not measured" cannot pass for "measured fine". Scenario 33 |
| [`SourceIndependenceKit`](https://github.com/rajatslakhina/source-independence-kit) | Counts how many independent sources are actually behind an evidence set, which every judge here assumes and none can check. Four merge signals, each reported with its reason: a declared document id, a canonicalised locator (tracking parameters, `www.`, AMP, `index.html`, fragments), textual redundancy by 5-word shingle containment rather than Jaccard — a chunk is 100% inside its own page — and declared derivation, because a faithful summary shares no wording with its source and is still not a second voice. `establishedSourceCount` is a floor and safe to threshold against; `corroboratedSourceCount` is `nil` whenever a passage went unplaced, because a count taken with provenance missing was never a measurement. Scenario 34 |
| [`TemporalValidityKit`](https://github.com/rajatslakhina/temporal-validity-kit) | Decides which retrieved passages are entitled to speak, as of the instant the question was asked. Every other judge here scores content and none knows what time it is, so a passage from a 2023 snapshot counts exactly as much as one written this morning. Four readings rather than a boolean — `valid`, `expired`, `superseded`, `undetermined` — and `undetermined` is never entitled, because a reading that did not run is not a reading that passed. Supersession is checked *before* a volatility window is required: a later reading of the same fact demotes an earlier one whether or not anybody declared how fast that fact changes. A passage dated after the question is `undetermined` rather than fresh, since `asOf - observedAt` is negative and a negative age sits inside every window. Scenario 35 |
| [`AbstentionPolicyKit`](https://github.com/rajatslakhina/abstention-policy-kit) | Arbitrates between the eleven judges above, which each rule alone and cannot hear each other. First-refusal-wins handles one judge being certain; it has nothing to say about three judges each being *uneasy*, and a judge unwilling to block on its own finding currently discards the finding entirely. `SignalReading` has four cases rather than three: `unavailable` is not `clear`, because folding them together makes a pipeline more confident the more of its judges fail to run. Concurrence is tested *before* the coverage floor — if three judges each found something the turn is already not one to answer, and reporting a coverage shortfall instead sends the caller to fetch more sources when the evidence it has is the problem. Counts origins, not signals. Never overturns a refusal. Scenario 36 |
| [`SignalDependenceKit`](https://github.com/rajatslakhina/signal-dependence-kit) | Asks how many of the judges above are the same judge. A panel that counts its members counts wrong: two gates sharing a corpus agree because they read the same thing, two sharing an embedding fail together, and a gate computed from another agrees by construction — every one of those is one opinion arriving twice, and an aggregator counting origins reads it as corroboration. `derived` edges close transitively; everything else merges by *complete* linkage, so A sharing a corpus with B and B a model with C never collapses all three. Mechanisms combine as `1 - product(1 - s)` rather than as a maximum, because two judges sharing both a corpus and a model are more entangled than two sharing only the corpus. Clean findings deflate on exactly the same terms as concerns, so the reduction can *tighten* a coverage floor and is not a device for loosening gates; refusals are never deflated at all. `DependenceRegistry` audits the declared graph against observed co-firing, because the entanglement nobody declared is the kind that hurts. Scenario 37 |
| [`ConformalGateKit`](https://github.com/rajatslakhina/conformal-gate-kit) | Derives the thresholds every gate above was given by hand. Split conformal risk control takes labelled outcomes and a risk budget and returns the most permissive threshold whose empirical loss still leaves room for the one draw you have not seen: `(w(tau) + 1) / (n + 1) <= alpha`, a finite-sample bound with no assumption about the score distribution. The `+ 1` prices that unseen draw, which is why a thin calibration set is refused outright rather than given a loose number — at `alpha = 0.05`, 18 outcomes buy nothing at all, even with zero observed errors. Only the joint loss is certified: selective risk is not monotone in the threshold, so it is reported beside the certificate labelled uncertified and never folded into the promise. Stratified certification names the slice an aggregate bound is quietly failing. The `AbstentionPolicyKit` bridge has four arms, two of them `unavailable` — an infeasible outcome and a valid certificate that admits nothing are both facts about the gate, and reading either as a per-item verdict builds a gate that refuses every request it will ever see. Scenario 38 |
| [`CensoredFeedbackKit`](https://github.com/rajatslakhina/censored-feedback-kit) | Audits the population the row above was calibrated on. A gate only ever learns about the requests it let through, so a calibration set drawn from production is drawn from the gate's own admissions and the conformal guarantee — arithmetically correct — is a guarantee about the wrong population. This reports partial-identification bounds over all the traffic, separates refusals whose loss is pinned by the loss definition from refusals that are genuinely unknown, and refuses to reweight a deterministic gate at all: a threshold admits with probability 1 or 0, so no finite inverse-probability weight exists for the refused region. Where a real exploration rate was logged it reports Horvitz–Thompson beside self-normalised with the Kish effective sample size, so weight explosion is visible rather than clamped. `ExplorationPlan` prices the fix in the same inequality the row above refuses on. `CertificateQualifier` reads a certificate against the log behind it and withdraws enforcement when the promise is unsupported. Scenario 39 |
| [`ExplorationChannelKit`](https://github.com/rajatslakhina/exploration-channel-kit) | Produces the labels the row above can only quote a price for. A deterministic gate cannot be corrected after the fact, so the only route to an estimate is to admit some would-be refusals deliberately — and this is the one component here whose job is to let a refusal through. `ExplorationChannel` is an actor that cannot overspend, cannot reach past its region however much budget remains, and cannot admit anything the gate did not refuse; every declining arm carries its reason, because a channel that quietly explores nothing looks exactly like one that is working. `RegionPlanner` splits the bound into an irreducible term that falls as the band widens and a sampling term that rises, and returns nothing rather than recommending a band that only ties not-exploring. `ChannelFeedbackBridge` keeps the band's records apart from the population's: exploration makes the *band* correctable, never the gate. Scenario 40 |
| [`LabelReturnKit`](https://github.com/rajatslakhina/label-return-kit) | Puts a clock on the row above. The channel records that an admission had a chance; nothing until now asked what came back, or what the admissions still outstanding do to a figure computed from the rest. `ReturnLedger` is an actor that refuses four kinds of label an id-matching ledger would accept — unmatched, duplicate, a label naming a threshold that has since moved, and one dated at or before its own admission. `CorrectedRisk` returns an interval whose **floor is exactly what closing the books right now reports**, so the most optimistic reading is named rather than quoted as the answer; the point estimate is withheld outright when returns are selective by region. `WaitCurve` reads the same ledger at a series of cutoffs, which is what turns a risk number back into a function of when somebody looked. Scenario 41 |
| [`DelaySignalKit`](https://github.com/rajatslakhina/delay-signal-kit) | Reads the thing the row above holds and does not use: **how long each label took**. Losses verify slower than clean answers, so at any cutoff the labels you have are enriched for clean ones and every figure quoted off them is optimistic. `DelaySignalEstimator` fits a two-class exponential delay mixture by expectation-maximisation over a panel that is still half censored, splitting each outstanding request between the classes by how plausible its silence is under each. `SeparationTest` is the identifiability condition rather than a quality check — with equal rates the fit returns the naive count exactly — and it carries a likelihood-ratio test as well as a ratio threshold, because the threshold alone cleared its bar on a fixture with no signal in it. `DelaySignalReturn` reconciles the correction against `LabelReturnKit`'s bracket and calls a correction outside it a contradiction rather than averaging the two. Scenario 42 |

| [`DelayShapeKit`](https://github.com/rajatslakhina/delay-shape-kit) | Answers the question the row above assumes away: **what shape is that delay, actually?** `DelaySignalKit` models each class's delay as a constant hazard and argues the case honestly — an outstanding request carries one bit and a second parameter would fit it two ways. That is true of the censored half and silent about the other one: a label that *came back* carries its whole delay and its class, and several parameters are identifiable from a pile of those. `ShapeFitting` ranks four families by AIC over an interval-censored likelihood, `AdequacyCheck` asks whether the winner describes the data at all, and `ShapeVerdict` has three arms that hand back nothing and mean different things — the exponential holding is a finding, not a fallback. The sample declares whether it is censored or truncated because the two need different likelihoods and applying both lands further from the truth than applying neither. Scenario 43 |
| [`DelayCurveKit`](https://github.com/rajatslakhina/delay-curve-kit) | The non-parametric answer to the row above. `DelayShapeKit` picks a family and declines when none fits; a correction that needed a survival curve then gets nothing. This assumes no family at all — a Kaplan-Meier product-limit estimate straight from the labels that returned and the requests still waiting — and pays for it with a hard right edge: `survival(at:)` returns `nil` past the last observation unless every request reported, and `RestrictedMean.over(_:horizon:)` **throws** rather than clamping a horizon that runs past the data. Bands are built on the log(-log) scale so they stay inside `(0,1)` without clamping, and thin risk sets are marked rather than deleted because Greenwood understates the tails. `LogRank` is computed, reported, and deliberately not used to decide: it assumes proportional hazards and cancels exactly where this ecosystem's hazards cross. `HorizonSweep` exists because the intended replacement failed the same way first. Scenario 44 |
| [`CurveDivergenceKit`](https://github.com/rajatslakhina/curve-divergence-kit) | The supremum under the row above. `DelayCurveKit`'s horizon sweep asks at every horizon and still reduces each one to a single difference, so it has to be asked in the right place; a supremum does not. `sup|S1-S2|` and the Kuiper sum come out of one scan over the shared window, each carrying **the tick it was attained at** — the part no scalar summary can produce. `SeparationShape` tells dominance from a crossing, which an area difference of zero cannot, since zero arises both from identical curves and from evenly crossing ones. The null is a permutation rather than a table, because the supremum between two Kaplan-Meier curves is not distribution-free under censoring; exchangeability is flagged via the censoring gap and not corrected for. `RenyiSupremum` is reported and deliberately not used to decide. Scenario 45 |
| [`LabelClockKit`](https://github.com/rajatslakhina/label-clock-kit) | Upstream of every row above it in the delay family, and the one that asks who could have built their arms. A record that stores one optional for both *has anything come back?* and *what did it say?* cannot form a censored arm: a unit carries a class exactly when its label has returned, and the landmark method excludes exactly those units, so **every landmark arm is empty at every landmark** — by proof, not by scarcity. `SeparationTable` measures whether the two facts are recorded for the same units (one cell, classified-and-outstanding, is the sole source of censoring) and `ClockSeparation` whether they are recorded at the same ticks. `ArmFormer` applies the landmark procedure and refuses by name. Scenario 46 |
| [`SelectionTrustKit`](https://github.com/rajatslakhina/selection-trust-kit) | The second axis under `ToolAuthorityKit`. That package refuses a call whose **arguments** came from a poisoned passage, which is content trust and works. This one is the case a ceiling cannot see: the planner reads the passage and then proposes refunding a **real** order, read out of the app's own table. `ToolAuthorityKit`'s ladder is `operatorAuthored < modelAuthored < untrusted` and has no case for *our data, their choice* — the nearest is `.modelAuthored`, which sits under the refund ceiling — so it returns the **same verdict whether the planner or the user picked the order**. `TaintFloor` is a monotone session high-water mark inherited across a baton pass, so a downstream agent cannot launder taint by authoring a fresh value; `.userConfirmed` values are exempt from it and `.appDerived` values deliberately are not. `ConfirmationReceipt` binds a digest over the resolved parameters rather than a boolean, blast radius included. The commit slot is reserved *before* the confirmation `await`, because actor isolation does not survive a suspension point: budget 1 and four concurrent invocations raise four prompts in the naive order and one in the correct one. Scenario 47 |
| [`ArgumentAttributionKit`](https://github.com/rajatslakhina/argument-attribution-kit) | The granularity under both of the two above. A taint floor marks every argument untrusted once any untrusted passage has been read, and cannot separate an argument whose **bytes** came out of that passage from one that merely followed it in time. Five rungs find the candidate — `exact`, `normalized`, `numeric` (a number written in words is still the number), `tokenSubset`, and a `semantic` rung that is **not installed by default** — and a specificity model prices whatever they located in bits, words against the corpus unigram and numbers by their written length, so a match on a `5` is `.weak` rather than attribution. There is no `.notDerived` case and `OverTaintReport` has no `overTaint` property: it carries a lower bound on derived arguments and an upper bound on over-tainting and refuses to name a point between them, because a value can come from a passage and share no key with it. Scenario 48 |
| [`EffectiveVoteKit`](https://github.com/rajatslakhina/effective-vote-kit) | The number every panel in this demo assumes and none of them measures. `SignalDependenceKit` deflates a panel using dependence strengths a caller **declares**; this measures them from what the judges actually did, as a design effect on the mean pairwise correlation with a Fisher interval. Two bases with opposite blind spots — agreement between **votes** is always computable and runs high because judges agree on easy items, agreement between **mistakes** needs labels and is the quantity that governs panel size — and neither is silently substituted for the other. `PanelAudit` has **no combined `effectiveVotes` property**: it reports the corpus and the one-vote-margin subset as separate populations, because selecting on margin conditions on the sum of the votes being correlated and drags the measurement down on its own, so only one direction of difference survives as a finding. Refusals carry the figure they withheld. Scenario 49 |
| [`ProxyLabelKit`](https://github.com/rajatslakhina/proxy-label-kit) | The label the row above needs and no deployment has. `EffectiveVoteKit` measures agreement between **mistakes**, which requires knowing which judge was wrong; scenario 49 can only do that because `PanelSpec.isSafeToAnswer` is a fact about how each corpus was *built*. A running system has a downstream outcome instead — a later contradiction, a user correction — and a decision to treat it as a label. That decision is priced here against a small audited subset, and the pricing is the easy half. The hard half is that an outcome arrives against an **item**, not a judge, so one mislabelled item flips every judge on it together: correlated label noise does not blur an error correlation toward zero the way independent noise does, it **manufactures one**. `NoiseRegime` is detected from the labels' provenance and never chosen by a caller, because on the same table the two regimes land on opposite sides of the measurement. `FeasibleAssociation` has **no `correctedPhi`**: an audit buys an interval, every rate inside it inverts to a different truth, and a midpoint would sell a precision nobody paid for. Scenario 50 |

| [`SampleWidthKit`](https://github.com/rajatslakhina/sample-width-kit) | The half of the interval the row above does not carry. Scenario 50 ends by reporting a bound that **missed** — `independence x temporal` bounded to `[0.0815, 0.2565]` against a truth of `0.0000` — and naming the reason: the bound prices the audit's uncertainty about the flip rate and nothing about the ninety-six items the table came from. This package supplies the other half. `MarginFeasibleRange` is **exact**: phi is linear in the top-left cell once the margins are fixed, so a table where ten of a hundred items carry a signal cannot express a phi above `0.3333`, and an interval quoting past that is quoting values no sample could produce. `IntervalPropagation` sweeps the sampling interval through the same de-noising rather than handing it a point, and the bound that missed becomes `[-0.2110, 0.4320]`, which contains the truth. `SampleSufficiency` asks the question a pipeline actually asks and refuses when the corpus cannot answer it. Scenario 51 |
| [`FamilyErrorKit`](https://github.com/rajatslakhina/family-error-kit) | The level every row above was quoted at, and none of them held. Scenarios 49 through 51 publish a coefficient, an interval and a sufficiency verdict for **every pair** of the four-judge panel — six readings, each correct alone, each at a nominal 95%. The chance that all six cover is not 95%, and the largest of the six was selected out of six candidates by the quantity being quoted. `FamilyErrorKit` corrects for the six. `PairOverlapGraph` shows independence was never available — **12 of the 15 pairings of those pairs share a judge, 80% overlap** — so `BenjaminiYekutieli` is the default and pays `H(6) = 2.4500` for it. `SimultaneousInterval` re-quotes `answerability x temporal` from `[-0.3577, 0.2071]` to `[-0.4425, 0.3015]`, **0.1793 wider**, widening on the `atanh` scale the interval is actually symmetric on rather than on the one it is printed in. `NullMaximum` says what six null readings over ninety-six items produce at the top of a page. And `FamilyLedger` **refuses** a family that never declared its size — the failure that makes a filtered report look better than the run that produced it. Scenario 52 |
| [`EffectiveComparisonKit`](https://github.com/rajatslakhina/effective-comparison-kit) | The denominator scenario 52 divided by. Benjamini-Yekutieli charged `H(6) = 2.4500` because a panel's overlapping pairs do not satisfy positive regression dependence — a price for *arbitrary* dependence, paid by a family whose dependence is a count. `PanelDesign` derives the correlation structure of the six comparisons from the panel's own shape; the permutation estimator measures what it is worth. **BY's multiplier is 14.7000x and this panel's measured dependence is 4.7930x.** The scenario also records the distinction the package exists for: the spectral estimators return the panel's **rank** (Li-Ji: 4.0000, the four judge effects behind all six comparisons) and a threshold needs its **tail count** (4.8912). `MultiplicityBudget` **refuses** to be built from a rank, and the ledger **refuses** to spend a correlation matrix nobody declared. On this page the calibration publishes the same one finding BY does, and the scenario says so rather than manufacturing a difference. Scenario 53 |
| [`ObservedNullKit`](https://github.com/rajatslakhina/observed-null-kit) | The distribution scenario 53 draws its threshold from, checked against the panel that produced it. Scenario 53 fits a Gaussian copula to a structural correlation matrix; this one resamples the gates' own grades. On this page the fitted route **cannot run at all** — `answerability` and `morphology` agreed on all **96** items, so a constant indicator leaves no matrix to fit and no Frechet bound to check. **The bootstrap needs neither**, pricing the tail at `2.4495` across the **199** readings a 96-item lattice admits. The scheme decides the question and travels with the answer: an item bootstrap is a family tail and spendable, a judge-label permutation is a chance baseline and **refused**, an item permutation leaves every count invariant so its null is a point mass and is **refused**. Scenario 54 |
| [`ChanceAgreementKit`](https://github.com/rajatslakhina/chance-agreement-kit) | The chance question scenario 54 declines to spend. A chance baseline is the **mean of a resampling scheme**, and Cohen's, Scott's and Bennett's terms are each exactly that for one scheme; `ExactChanceMoments` supplies the **variance** none of them carries. On this page it finds something four scenarios above could not: **every distinct pair of gates has an association of exactly nil**. `PanelSpec.all` is a fully crossed design, so every joint count equals `a_j * b_k / n` to `0.000000` and every kappa is exactly `0.0000`. The one nonzero coefficient is `answerability` against `morphology` at `1.0000` — two judges that are one judge. It also pins an identity on the real panel: the finite-population term Scott drops is `(c-1)` times Gwet's whole chance term over `(2n-1)`, all three reading `0.002454188482`. Scenario 55 |
| [`PanelDesignKit`](https://github.com/rajatslakhina/panel-design-kit) | The fixture every coefficient above is computed over, treated as an input that can be wrong. `PanelSpec.all` crosses every level of every axis, which makes the corpus reproducible on every machine and makes every joint count the product of its marginals — so its true association is not small, it is **exactly zero**, and five scenarios of coefficients over it were estimating nil. `DesignDiagnosis` measures that as `max |observed - expected|`, `certify()` is the only call that refuses, and `AttainableAgreement` prices the range two marginals allow before either judge speaks. Above two categories it **declines to say** which counts inside that range exist, and `BinaryPanelBuilder` throws `constructionRequiresBinary`. Scenario 56 |
| [`SquareDesignKit`](https://github.com/rajatslakhina/square-design-kit) | The refusal scenario 56 leaves standing, answered. These judges cast **three-way** verdicts, so the panel that needs repairing is square and the sibling can only repair binary ones. Fixing the trace at `t` leaves a transportation problem with a forbidden diagonal, feasible exactly when `(a_k - d_k) + (b_k - d_k) <= n - t`, which solves to a per-category floor and makes attainability the one-line test `sum_k floor_k(t) <= t <= sum_k min(a_k, b_k)`. On this panel that turns `nil` into `false` and prints what nothing here could previously ask for: `answerability / independence` reaches only **25 of the 49** counts in its range, and the 24 it misses are every odd number. `SquarePanelBuilder` then builds the repair — same two judges, same verdict rates, **kappa moved from `0.0000` to `-0.5000` and `0.5000`** with nothing changed but which item each verdict landed on. Scenario 57 |
| [`AssociationFitKit`](https://github.com/rajatslakhina/association-fit-kit) | The other half of the specification scenario 57 completed. `SquareDesignKit` fixes a panel's **trace**, which on a three-category panel pins one number and leaves eight cells to whatever the construction happens to do. This one states the **association** as a structure and lets the trace follow, fitting it onto required margins by iterative proportional fitting — which provably cannot move a local odds ratio, because row and column scalings cancel out of every one of them (**4.441e-16** on this demo's own margins). Four structures on one set of margins give four different panels: agreement `0.5000`, `0.5986`, `0.7254`, with quasi-independence **refused** because forbidding the diagonal leaves judge one's 72 affirmations only 48 columns to land in. Then it prices whole verdicts: **every margin exact on every structure**, association moved by up to `2.011e-01`. Scenario 58 |
| [`AssociationTransportKit`](https://github.com/rajatslakhina/association-transport-kit) | Scenario 58 **chose** a structure. This one reads the corpus's own. Every construction in scenarios 50-58 starts from a structure somebody named; nothing here could measure one, say how precisely, or carry it elsewhere. It cross-tabulates two gates into the joint panel an association actually lives in — which scenario 58 never built, having used only margins — and **refuses** to read it undecided, because 5 of its 9 cells are empty and nothing in the counts says whether that is a rule or an absence. Read as a rule it cannot be seeded at all (`seedLineEmpty`); read as an absence it transports, agreement moving `0.5000 -> 0.5691` on balanced margins with the structure carried exactly. The finding is the interval: **0 of 4 blocks clear independence at 95% on 96 items**, the widest spanning a factor of **15766.2**, and 3 of the 4 ratios exist only because half an item was added to every cell. Scenario 59 |
| [`ExactAssociationKit`](https://github.com/rajatslakhina/exact-association-kit) | What scenario 59's intervals were worth. Every odds ratio above carries a **Woolf** interval — a normal approximation on the log scale, valid in the limit of large counts, on a panel of 96 items with five empty cells. Conditioning a block on all four margins leaves the odds ratio as the only parameter of Fisher's noncentral hypergeometric distribution, so the interval can be **summed rather than approximated**. On this corpus it finds something scenario 59 could not: **three of the four blocks have a zero margin**, which pins them to a single table — they never had an odds ratio to estimate, and every ratio they contributed was made by the half-item correction. The one readable block reads exact `[0.3574, 2.7979]` against Woolf's raw `[0.3970, 2.5192]`, **11.4% wider**, with a Fisher p of exactly `1.000000`. Swept over every table of at most twenty items with no empty cell, Woolf is **never** the wider of the two. Scenario 60 |
![Architecture](Screenshots/architecture.svg)

## What it demonstrates

1. **`ProviderGatewayKit`** routes a turn through an `LLMSession` backed by
   a `ProviderRouter`, across three different provider identities
   (on-device, cloud, self-hosted).
2. **`StructuredOutputKit`** builds the schema instructions appended to the
   prompt, then extracts and validates the routed reply — clean JSON,
   JSON fenced in prose, and a malformed-then-repaired reply that goes
   through a real second routed call, not just a canned retry string.
3. **`TokenMeterKit`** meters every routed hop (including the failed first
   attempt in the repair scenario) against registered per-provider rates,
   and prints a per-model and total cost report.
4. **`ResponseCacheKit`** sits in front of the same routed pipeline for a
   fourth scenario: the same question asked twice. The first call is a
   real MISS — routed and metered exactly like the scenarios above. The
   second call never reaches `ProviderRouter` at all; `ResponseCache`
   answers from its own storage, and the cost that would have been
   re-paid shows up in `estimatedSavings` instead of a second metered hop.
5. **`ToolRegistryKit`** handles a fifth scenario: a routed turn "decides"
   to call a `get_weather` tool. `ToolRegistry.dispatch(_:)` decodes and
   schema-validates the arguments *before* the registered handler runs,
   and the handler's result is fed back into a second routed turn for the
   model's final, schema-validated answer — two metered hops, one
   validated tool call, no unchecked handler input.
6. **`AgentLoopKit`** handles a sixth scenario, and generalizes the one
   above: rather than hand-wiring a single tool-call round trip across two
   manually built `LLMSession`s, `AgentLoop.run(initialPrompt:)` drives a
   bounded loop that chains *two* dependent `get_weather` calls (comparing
   Austin and Boston) before the model converges on a final answer.
   `TokenMeterKit` meters every step entirely after the fact, straight off
   the returned `AgentTranscript` — `AgentLoopKit` never needs to know
   `TokenMeterKit` exists.
7. **`GuardrailKit`** handles a seventh scenario, sitting in front of *and*
   behind the same routed pipeline: a user prompt carrying a real email
   address is redacted by `GuardrailPipeline.screenRequest(_:)` before it
   ever reaches `ProviderRouter`/`LLMSession` — the provider only ever sees
   the sanitized text — and the reply is screened again with
   `screenResponse(_:)` on the way back out. A second prompt trips a
   banned-phrase content policy rule and is blocked outright: no provider
   call is made and nothing is metered for it. Every screening — redacted,
   allowed, or blocked — is recorded as a `GuardrailEvent` by an
   `InMemoryGuardrailEventRecorder`.
8. **`TraceKit`** handles an eighth scenario: the same decide/dispatch/answer
   round trip the fifth scenario hand-rolled, but with each step wrapped in
   `Tracer.withSpan(name:kind:parentID:operation:)` under one manually
   managed root `agentStep` span. `Tracer.trace(rootID:)` reconstructs the
   full nested trace afterward, and an `EvalGate` scores it against
   `NoErrorSpansScorer` and `MaxDurationScorer` — turning "did this composed
   call succeed, and fast enough" into an enforced pass/fail check instead
   of eyeballed print output.
9. **`RetrievalKit`** handles a ninth scenario, and is the first one that
   isn't fronting a *routed* call but *preceding* it: a `Retriever` indexes
   four short documents (one per sibling package) with a deterministic
   `HashingEmbeddingProvider`, then `retrieveContextBlock(query:)` ranks
   and returns the chunks most relevant to a real question. That context
   block is prepended to the prompt handed to a routed `LLMSession.send()`
   call, and the reply is decoded as a `RAGAnswer` — the actual
   retrieve-then-generate pattern, with `RetrievalKit` doing real cosine
   similarity ranking rather than a hand-picked "relevant" string.
10. **`PromptTemplateKit`** handles a tenth scenario: `PromptRegistry`
    registers a context+question system-prompt template at v1, promotes a
    more explicit v2 that becomes active immediately, and
    `render(name:variables:mode:)` renders that active version (strict
    mode) into real prompt text. Only that *rendered string* — never the
    raw template — is handed to a routed `LLMSession.send()` call, decoded
    as a `RAGAnswer` and metered like every other scenario:
    `PromptTemplateKit` renders, `ProviderGatewayKit` sends.
    `rollbackToPrevious(name:)` then restores v1, and a second
    `render(mode: .lenient)` call leaves an unresolved placeholder as
    literal text rather than throwing — every register/promote/render/
    rollback action along the way is captured by an
    `InMemoryPromptAuditRecorder`.
11. **`RetryPolicyKit`** handles an eleventh scenario: `RetryExecutor` wraps
    a routed `LLMSession.send()` call against a `FlakyProvider` that
    genuinely throws for its first two attempts, then succeeds — a real
    transport-layer failure, not a malformed-reply repair like the third
    scenario. The same `LLMSession` is retried across all three attempts
    rather than rebuilt per attempt: `CircuitBreaker`'s default
    `failureThreshold` is 3 consecutive failures, so two failures followed
    by a success never trips it. `ExponentialBackoffRetryPolicy` computes
    the wait between attempts and an `InMemoryRetryEventRecorder` captures
    every attempt including the two failures; only the final, successful
    call is metered — matching how real LLM billing charges for completed
    responses, not failed ones.
12. **`ContextCompactionKit`** handles a twelfth scenario: a routed
    `LLMSession` conversation grows across four real turns (`LLMSession`
    is given a deliberately huge 100,000-token internal budget so its own
    `ContextBudgetManager` never trims anything during this scenario), then
    `session.currentTranscript()` is bridged into
    `[ContextCompactionKit.CompactableMessage]` and run through a full
    three-tier `ContextCompactor` — sliding-window, truncating, summarizing
    — against a 100-token budget the raw 9-message transcript can't fit.
    The *compacted* result (not the raw transcript) is joined into a text
    block and handed to the next routed `session.send()` call, decoded as
    a `RAGAnswer` and metered like every other scenario. An
    `InMemoryCompactionEventRecorder` captures the before/after token and
    message counts and which strategies actually fired.
13. **`AgentMemoryKit`** handles a thirteenth scenario: a `MemoryStore`
    holds three memories written in an earlier "session" — a pinned persona
    fact, a genuine preference, and a low-importance aside —
    `recall(query:topK:)` ranks them by semantic similarity blended with
    recency, importance, and access frequency (not raw vector distance
    alone) and returns the two most relevant. Their content, not a
    hand-picked string, is folded into the prompt for a routed
    `LLMSession.send()` call, decoded as a `RAGAnswer` and metered like
    every other scenario. A final `decay(pruneBelow:)` call then fades and
    prunes the low-importance aside while the pinned persona fact survives
    untouched — demonstrating the guarantee that pinning in this package
    has no loophole.
14. **`SemanticRouterKit`** handles a fourteenth scenario: a `SemanticRouter`
    registers three support intents (weather, order status, small talk),
    each described by seed utterances and carrying the model a match should
    route to in its `metadata`. An incoming message is classified by
    embedding distance to the closest intent above its threshold, and the
    matched route's `metadata["model"]` — not a hard-coded branch — selects
    which provider the real routed `LLMSession.send()` call targets. This is
    semantic routing (by meaning) feeding provider routing (by capability):
    the reply is then decoded as a `WeatherReport` and metered like every
    other scenario.
15. **`OutputRepairKit`** handles a fifteenth scenario, the loop layer that
    sits *around* validation. An `OutputRepairLoop` drives a real routed
    `LLMSession` as its `ResponseProducing`: the provider's first reply omits
    a required field, so the loop's `WeatherRepairContract` rejects it with a
    structured `RepairIssue`, `DefaultRepairPrompter` folds that reason into a
    correction prompt, and the second routed call repairs it. Both hops — the
    rejected one and the repaired one — are metered under `repair-host`.
    Where `StructuredOutputKit`'s scenario shows *its own* internal retry,
    this shows a reusable repair loop wrapping *any* routed model, with a hard
    attempt budget and an auditable `RepairEvent` trail.
16. **`StreamAggregatorKit`** handles a sixteenth scenario, the front of the
    pipeline. A streaming provider never returns a finished reply — it emits a
    sequence of deltas, and its tool-call arguments arrive as JSON fragments
    keyed by index. A `StreamAggregator` reassembles that stream (a content
    preamble plus a `get_weather` call whose arguments dribble out across two
    fragments) into one `AssembledMessage`; the reassembled tool call is then
    dispatched through `ToolRegistryKit`, and the `usage` the stream carried is
    billed by `TokenMeter` at its exact counts under `stream-host` rather than
    re-estimated from text. `StreamAggregatorKit` has no compile-time
    dependency on the gateway — the `DeltaSource` is its only seam.
17. **`BatchInferenceKit`** handles a seventeenth scenario, the one that stops
    treating a routed call as a single event. Five prompts go into one
    `BatchProcessor` with `ConcurrencyLimit(2)`, and every item is a real
    `ProviderRouter`/`LLMSession` round trip: a `GatewayBatchExecutor` adapter
    is the `BatchExecuting` seam, so the batch genuinely fans out through
    `ProviderGatewayKit` rather than answering from canned strings. The output
    shows all three of the package's guarantees at once — `stats.peakActive`
    comes back as 2, proving the bound held rather than being merely requested;
    `report.outcomes` is in submission order regardless of which item finished
    first; and the third reply, which arrives missing the required `conditions`
    field, is rejected by `StructuredOutputKit` inside the adapter and isolated
    as a single `BatchItemError` under `.continueOnFailure` while the other four
    still complete. Billing is the closing seam: `BatchProcessor` sums
    `BatchTokenUsage` over *successful* items only, so the batch settles with
    one `TokenMeter.record` against `stats.usage` under `batch-host` and the
    failed item costs nothing — the same principle the retry scenario applies to
    failed attempts. `BatchInferenceKit` carries no retry or cost logic of its
    own by design, which is exactly why those two jobs stay with
    `RetryPolicyKit` and `TokenMeterKit` here instead of being duplicated.
18. **`RealtimeSessionKit`** handles an eighteenth scenario, the one that stops
    assuming the connection lasts. A live session sends two turns through a
    `GatewayRealtimeTransport` — the `RealtimeTransport` seam, so each turn is a
    real `ProviderRouter`/`LLMSession` round trip — and the socket drops with the
    second turn still unacknowledged. `handleDisconnect()` answers
    `retry(attempt: 1, delayTicks: 125)`: a full-jitter ceiling of 250 ticks with
    the jitter source pinned to its midpoint, which is the only reason a backoff
    number is assertable at all. The reconnect lands inside the 30-tick resume
    window, so the server is asked to continue from the client's *own* cursor
    rather than start over, and the unacknowledged turn is replayed — two turns
    costing three gateway hops, which is what at-least-once actually means rather
    than what it promises. The buffered server event is then accepted once and its
    immediate redelivery caught as `duplicate(repeatedID)`. All three hops, replay
    included, bill under `realtime-host`, so the cost of the retry is visible
    instead of hidden. This scenario sits *underneath*
    `StreamAggregatorKit`: that package reassembles the deltas of one response,
    this one owns the session those responses arrive on, and neither depends on
    the other at compile time.
19. **`IdempotencyKit`** closes a nineteenth scenario, and it is the exact
    counterpart of the eighteenth. There, a replay after a reconnect genuinely
    cost a second gateway hop, because at-least-once delivery means the effect
    really is re-sent. Here the duplicate never reaches a provider at all. A
    weather alert for Shimla is filed three times under one key derived from the
    payload — `k-25b33bd81297ca7c`, the same key either way round because the
    fields are canonicalised in sorted order before hashing — and the
    `GatewayEffectExecutor` behind the `EffectExecuting` seam records **one**
    gateway hop for those three requests, which is evidence rather than a claim,
    since a replay cannot reach the type that counts. Reusing that key with the
    severity changed from `high` to `low` is refused instead of answered with the
    earlier alert. A second alert, for Kochi, fails with an indeterminate gateway
    timeout — the failure mode that costs money — so the key is frozen: the retry
    is blocked, the hop count stays at one, and only after
    `resolve(key:as: .notApplied)` does the alert actually get filed. Two executed
    hops bill under `idem-host` at 15+33 tokens; the two replays bill nothing, by
    construction rather than by subtraction. `IdempotencyKit` deliberately does no
    retrying of its own — `RetryPolicyKit` decides *when* to try again, this
    decides *whether trying again is safe* — and has no compile-time dependency on
    any other package here.

Each scenario uses a `ScriptedProvider` — a demo-only conformer to
`ProviderGatewayKit`'s real `LLMProvider` protocol that answers from a
fixed script instead of a live network or on-device runtime, exactly the
same pattern `ProviderGatewayKit` uses internally for its own
`SimulatedCloudProvider`. Everything *around* that one scripted seam —
routing, session turn-serialization, schema validation, extraction, the
retry loop, caching, tool dispatch, and cost accounting — is the real,
compiled code from all nineteen tagged packages. (`RetryPolicyKit`'s own
scenario additionally uses a `FlakyProvider` — a demo-only conformer that
genuinely throws for its first two calls, since retrying only makes sense
against a real transport-layer failure, not a scripted success.)

Note: `ProviderGatewayKit` ships its own minimal, string-only
`ToolRegistry`/`ToolCallRequest` types for basic tool round-tripping.
`ToolRegistryKit` is a separate, richer package for host apps that want
real `JSONSchema` argument validation and structured `JSONValue` results
before a handler ever runs — this demo qualifies both types explicitly
(`ToolRegistryKit.ToolRegistry`, `ToolRegistryKit.ToolCallRequest`) since
both packages export a same-named type.

## Installation

This repository is a runnable demo, not a library — there's nothing to add
to your own `Package.swift`. To build it yourself:

```bash
git clone https://github.com/rajatslakhina/llm-ecosystem-demo.git
cd llm-ecosystem-demo
swift run LLMEcosystemDemo
20. **`SchemaMigrationKit`** adds a twentieth scenario, and it is the third
    distinct answer this toolkit gives to "don't pay for the same work twice."
    `ResponseCacheKit` avoids a second hop for an identical question.
    `IdempotencyKit` avoids a second hop for a retried side effect. Here the
    cached answer is neither identical nor retried — it is *stale in shape*, a
    reply stored under last year's contract, carrying a numeric `conditionCode`
    and a `stationId` that today's `WeatherReport` has no slot for. The registry
    classifies v1 -> v2 as BREAKING and says exactly why (`conditionCode`
    removed, `stationId` removed, `conditions` added), then **refuses** the
    migration, because the step admits it cannot carry `stationId` across.
    Passing `allowingLoss: true` runs it: the condition code is folded into the
    `conditions` band, the station id is dropped and named in the result, and
    the migrated payload is handed to the real `StructuredOutputDecoder`, which
    accepts it. All of that costs **zero gateway hops** — a schema migration is
    local computation, not a re-generation. The one hop the scenario does spend
    is a live routed turn whose reply already satisfies v2, so
    `negotiate(v2, v2)` returns `exact v2` and nothing migrates; it bills 9+17
    tokens under `schema-host`. Going the other way — serving a client still on
    v1 — needs no opt-in at all, because the band maps cleanly back onto a code
    and nothing is lost; that contrast is what makes the earlier refusal mean
    something.

```

Swift Package Manager resolves `ProviderGatewayKit`, `TokenMeterKit`,
`StructuredOutputKit`, `ResponseCacheKit`, `ToolRegistryKit`, `AgentLoopKit`,
`GuardrailKit`, `TraceKit`, `RetrievalKit`, `PromptTemplateKit`,
21. **`ToolAuthorityKit`** adds a twenty-first scenario, and it is the one
    scenario where a package's job is to *stop* the pipeline rather than move
    it along. `RetrievalKit` retrieves a knowledge-base passage that an
    attacker seeded with an instruction. `ProviderGatewayKit` routes a real
    turn, and the model does what the passage told it to: it proposes an
    outbound send of the customer list. `ToolRegistryKit` would have validated
    those arguments against the tool's schema and dispatched them, because
    they are perfectly well-formed — being well-formed is not the same as
    being permitted. `AuthorityBroker` refuses it on an axis no other layer
    models: the arguments' **provenance**. The same grant admits untrusted
    arguments for `read_order` and refuses them for `mailer.externalSend`,
    because a wrong order id costs a wrong answer while a wrong recipient
    costs the customer list — so the legitimate read is allowed and really
    dispatched. The refund is neither allowed nor refused but escalated:
    `.approvalRequired` carries the resource, the arguments and the provenance
    to a human, whose signature is bound by digest to that exact call — re-presented
    against a $4000 refund it throws `approvalDigestMismatch`, and the
    `ToolRegistry` ends the scenario having dispatched exactly the two calls
    that were authorized. One gateway hop, billed under `authority-host`, because
    an authorization decision is local computation.

22. **`GroundingKit`** closes the set with a twenty-second scenario, and it is
    the one that checks the *answer* rather than the machinery around it.
    `RetrievalKit` indexes and retrieves three real passages.
    `ProviderGatewayKit` routes a real turn. `StructuredOutputKit` decodes the
    reply and **accepts it** — every required field present and correctly typed,
    because a hallucination is not a schema violation. `GroundingVerifier` then
    asks the question nothing else in the pipeline is positioned to ask, and
    answers it three different ways for three sentences: the retention claim is
    `supported` at 100% and correctly cited; the export-limit claim says 5000
    where `kb-limits` says 500, which is `contradicted` rather than unsupported
    because the source does not merely fail to mention it — it says otherwise;
    and the enterprise claim cites `kb-enterprise`, a document that was never
    retrieved at all. `.strict` refuses with three violations, each naming its
    claim. `.stripping` removes c2 and c3 and publishes what survives. All of it
    costs **zero extra gateway hops**, which is the contrast with
    `OutputRepairKit`: repair pays a second hop to ask the model to try again,
    while verification is local computation. One hop, billed under
    `grounding-host`.

23. **`QuotaGovernorKit`** adds the twenty-third scenario, and it is the only
    one that can say *no*. Every scenario before it spends whatever it needs;
    `TokenMeterKit` can price a hop, but only once it has been paid for, and
    nothing in the toolkit could refuse the hop after it. `QuotaGovernor.reserve`
    holds an estimate against every scope on a `tenant-acme / run-atlas` path
    before `ProviderGatewayKit` routes the turn, `TokenMeter` prices the reply,
    and `settle` closes the reservation against that real figure — so the metered
    cost is the input to the next admission decision, not a summary at the end.
    Step 1 shows the per-axis claim rather than asserting it: a 150-token /
    60,000-microcent estimate held 180 / 72,000 under 20% headroom, the hop really
    cost 112 / 95,280, and the settlement reports **refunded 68 tokens / 0
    microcents** and **overran 0 tokens / 23,280 microcents** — under on tokens and
    over on money in one request, which one signed number would have netted out and
    reported as neither. Refunded holds then let the loop get further than a fixed
    reservation would have, and it still stops: 3 of 8 steps run before step 4 is
    refused with `run-atlas is out of tokens: 164 left, 180 requested`. A second
    run estimates badly — 180 held, 737 spent — so it breaches its ceiling, sits in
    arrears at -237 tokens, and is refused on its next request. `tenant-acme`
    absorbs both and finishes with 98,927 of 100,000 tokens, which is the nesting
    doing its job: a run that will not stop cannot reach past its own ceiling.

24. **`CostEstimatorKit`** adds the twenty-fourth scenario, and it answers the
    question scenario 23 leaves open: where did that estimate come from? There it
    was a literal. Here it is computed from the loop shape the caller already
    decided on before dispatching, and the loop below genuinely resends its
    transcript so the forecast is predicting the run that actually happens. That
    is the whole point — a flat "one call times four" estimate says **200 input
    tokens** and the run really uses **715**. Output length is the one input a
    plan cannot supply, so it sits behind `OutputLengthPredictor` and is learned
    per `InputShape`. Pass 1 carries a deliberately wrong prior of 15 output
    tokens per step against a model that writes closer to 56, and **overruns at
    81% on tokens and 130% on cost** — the ±50% prior band was wide enough to have
    warned first. Passes 2 and 3 land **within tolerance at 1%**, because the EMA
    predictor has seen a real run. The band does not tighten on contact: it goes
    **50% → 81% → 41%**, widening after the miss is recorded and only coming back
    down as accurate runs accumulate. A band that narrowed immediately after being
    wrong would be the wrong behaviour. Both packages price off the same rates —
    `estimator-host` at $2.80 / $11.20 per million is registered once with
    `TokenMeter` and once in the estimator's own `PriceBook` — so the reported
    error is error in predicting *work*, not two catalogs disagreeing. The forecast
    hands over as the two integers `QuotaGovernorKit` reserves against, and neither
    package imports the other.

25. **`WorkloadProfilerKit`** adds the twenty-fifth scenario, and it closes the
    loop the previous one opened. Scenario 24 forecasts from a `WorkloadPlan`
    somebody typed by hand, and its own narrative admits the prior of 15 output
    tokens per step was wrong. This scenario runs three real routed loops of 3, 4
    and 5 steps, records what each hop actually sent and received, and derives the
    plan from those runs instead of declaring one. Run 1 sends **408 input tokens
    across 3 steps — 266% of the 153** a flat estimate predicts, with **4‰
    unexplained**, which is real integer-division rounding in the demo's
    tokenizer rather than a number massaged to zero. The derived plan says **4
    steps, 1 tool call per step at 28 tokens, 56 output tokens per step**, at
    **medium** confidence with **477‰** dispersion — medium rather than high
    because three runs of deliberately different lengths are a wide sample, and
    the package reports that instead of hiding it. Then the check nobody in this
    series had: scenario 24's declared plan against these runs **drifts on exactly
    1 of 7 fields**, and it is `expectedOutputTokensPerStep`, **declared 15,
    observed 56, understated by 2733‰**. The two packages were written on
    different days and agree independently about which number was wrong. Feeding
    the derived plan back into a real `CostEstimatorKit.WorkloadPlan` forecasts
    **708 in / 224 out** where the flat estimate says 204 in — so the estimate is
    now a measurement with a provenance rather than a literal with a history.
    `profiler-host` is registered at the same $2.80 / $11.20 per million in both
    `TokenMeter` and the estimator's `PriceBook`, per the standing rule, and
    neither package imports the other.

26. **`ClaimConsistencyKit`** adds the twenty-sixth scenario, and the result worth
    reading is the *boundary* between it and scenario 22, not a clean win for
    either. `GroundingKit` scores lexical overlap and, above a threshold, checks
    two conflicts of its own — `polarity` and `quantity` — so it is not blind
    here. It routes one real turn with four claims, each citing a document that
    genuinely is about it, and the two layers are then run over `GroundingKit`'s
    **own** claim-to-source matches, unchanged.

    They agree on the first: `is enabled by default` against `is not enabled by
    default`, **100% overlap**, both call it a contradiction. They part on the
    other three. `GroundingKit`'s quantity check compares numeric terms *as
    written*, so `retries 5 times` against `retries at least 3 times` reads as a
    conflict — **it is a satisfied bound, and the grounding verdict is a false
    positive**. `ClaimConsistencyKit` parses the bound and returns `AGREES`,
    which matters more than the additions: a false alarm is what teaches a reader
    to stop reading the report. The last two carry no negation and no numbers at
    all, so nothing in an overlap score can reach them — `some providers` widened
    to `all providers` (**supported, 83%**) and `enabled` swapped for `disabled`
    (**supported, 75%**) — and both come back `CONTRADICTS`. Net: grounding
    refuses on 2 violations, consistency rejects naming `c1, c3, c4`, and the
    second pass costs **zero** extra gateway hops, where the published fix for
    this class of error is an NLI model call per claim.

27. **`SourceConflictKit`** adds the twenty-seventh scenario, and it is the first
    one in this demo that runs *before* a turn rather than after it. Every
    truthfulness check above — grounding, citation verification, claim
    consistency — judges a paragraph that has already been generated and already
    been paid for. This one asks whether the retrieved passages agree with **each
    other**, which is the failure the research literature keeps naming and which
    nothing else in this pipeline covers.

    The integration worth reading is the oracle. `ContradictionOracle` asks
    exactly the question `ClaimConsistencyKit` already answers — *do these two
    sentences agree* — so scenario 26's package plugs straight into scenario 27's
    seam. Seven passages over three topics are audited twice, once with the
    built-in lexical oracle and once with the propositional one, and the
    difference is measurable: lexical splits the retry topic into **3 positions
    and withholds 2 passages**; the propositional oracle finds **2 positions and
    withholds 1**. The passage it rescues is `s-blog` — `retries 5 times` against
    `retries at least 3 times`, a satisfied bound that lexical reads as `3 vs 5`
    and throws away. Withheld evidence is evidence the model never sees, so a
    false positive here is not a cosmetic reporting bug.

    Two honest boundaries the run makes visible. First, `some providers` against
    `all providers` is **not** reported by either oracle, and that is correct:
    `all X` entails `some X`, so two sources saying that are compatible even
    though an *answer* widening `some` to `all` is not — source-source and
    claim-source are different questions, and this stage only asks the first.
    Second, `judge` is synchronous, so an actor-based checker cannot be called
    inline; the pairs are judged once up front and served through a table-backed
    oracle, in one canonical id order, which is how the seam's symmetry contract
    survives a checker that never promised it.

    Cost: the whole audit is local computation, **0 extra gateway hops**, and the
    losing position never reaches the model. `conflict-host` is registered at
    $2 / $8 per million so the one surviving turn bills visibly rather than
    defaulting to $0.

`RetryPolicyKit`, `ContextCompactionKit`, `AgentMemoryKit`,
`SemanticRouterKit`, `OutputRepairKit`, `StreamAggregatorKit`,
`BatchInferenceKit`, `RealtimeSessionKit`, `IdempotencyKit`, and
`SchemaMigrationKit`, `ToolAuthorityKit`, `GroundingKit`, and
`QuotaGovernorKit`, `CostEstimatorKit`, `WorkloadProfilerKit`, and
`ClaimConsistencyKit` straight from
their `1.0.0` tags — no local checkouts or path overrides needed.

## Sample output

![Demo output](Screenshots/demo.svg)

*The capture above is from an earlier run and shows twenty-four scenarios; it is left
as captured rather than edited, because a doctored total is worse than a dated one.
The current run is **sixty scenarios, $0.2068255 metered total**. `architecture.svg`
is likewise a point-in-time subset. The package table and narrative above are current.*

28. **`ClaimSegmenterKit`** adds the twenty-eighth scenario, and it is the only
    one that changes nothing about the pipeline except the unit it measures. Every
    truthfulness check in this demo — grounding, citation verification, claim
    consistency, source conflict — begins by cutting text into claims, and all
    four take that cut as given.

    The answer is built so each sentence pairs a true clause with a false one,
    each citing the document that is genuinely about it. `GroundingKit`'s verifier
    then runs twice, with nothing swapped but the segmenter behind its
    `ClaimSegmenting` seam.

    At sentence granularity it returns **3 claims and 5 violations**, and both
    errors it makes point in opposite directions. `c1` comes back **contradicted
    (71%)**, which condemns `The response cache is enabled by default` — a true
    statement — along with the false half beside it. `c2` comes back
    **partiallySupported (57%)**, which absolves `streaming is enabled by default`
    — a false statement — along with the true half beside it. One verdict cannot
    describe two assertions, and neither error is visible in the output.

    At clause granularity it returns **5 claims and 3 violations**: `c1 supported
    (100%)`, `c2 contradicted (100%)`, `c3 supported (100%)`, `c5 supported
    (100%)`. The claim that is wrong is named and the claims that are right are
    not condemned with it. `c2` is the repaired one — the segmenter carried
    `The response cache` in to replace `it`, because `it is not shared across
    sessions` verified alone is a coin flip.

    **The finding worth the scenario is `c4`, and it is not a win.** `Streaming is
    enabled by default` was scored **67% against `kb-cache`** — a document it never
    cited — because the lexical scorer found more overlap with *the response cache
    is enabled by default* than with the streaming source it did cite. Isolating
    the clause was necessary and was not sufficient: the smaller a claim gets, the
    more of its wording it shares with a near neighbour. The demo detects and
    prints this rather than smoothing it over. It is a real limit of matching by
    overlap and it belongs to the layer below the segmenter.

    One sentence is **left whole and the refusal reported**: `Requests queue behind
    the limiter, and the queue is bounded` has no auxiliary in its first clause, so
    there is no subject for the second to inherit. Under-splitting loses
    granularity; over-splitting invents assertions the model never made.


29. **`CitationBindingKit`** adds the twenty-ninth scenario, and it exists because
    scenario 28 ended by reporting a defect it could see but not fix. Its last line
    was `c4 cited [kb-stream] but was scored against kb-cache - the overlap scorer
    picked a neighbour`, followed by the admission that the fix belonged to the
    layer below.

    This is that layer, run over the exact same claims from the exact same
    segmenter, so the only difference in the output is the difference between the
    two questions:

    ```
      claim  grounding scored against   binding attributed to   agree?
      c1     kb-cache                   kb-cache                yes
      c4     kb-cache                   kb-stream               NO
    ```

    **`c4` is where the two layers part company.** `GroundingKit` scored
    `Streaming is enabled by default` against `kb-cache` — the document about the
    *cache* being enabled by default — because that is what it overlaps most.
    `CitationBindingKit` attributes it to `kb-stream`, which is what the answer
    actually cited. Neither layer is wrong about its own question; only one of
    them is answering the question a reader assumes was asked.

    **And the honest part: no `strongerUncitedSource` finding was raised.** Under
    this package's scorer `kb-stream` and `kb-cache` both align at 67% with that
    claim — a tie, and a tie is not a decisive margin. That is the designed
    behaviour, not a miss. Two documents that score identically are two documents
    that say something equally similar, and calling that a misattribution would
    raise a finding on every near-duplicate corpus until nobody read the findings.
    The divergence between the two *layers* is real and is reported; the claim that
    one *document* beat another is not made, because the evidence does not support
    it.

30. **`ClaimDecontextualizerKit`** adds the thirtieth scenario, and it goes under
    both of the two before it. Scenarios 28 and 29 each ended on the same defect
    from opposite sides — a finely-cut claim gets scored against whichever passage
    shares the most wording — and both treated it as a scoring problem. Some of it
    is not. A claim reading `It is not shared across sessions` has no subject at
    all. There is nothing in it to score correctly.

    The scenario resolves what it can and then runs `GroundingKit` twice, over the
    answer as written and over the answer as resolved:

    ```
      sentence  outcome          detail
      s0        standalone       nothing to resolve
      s1        resolved         The response cache is not shared across sessions.  (+2 tokens)
      s2        standalone       nothing to resolve
      s3        REFUSED no ant.  nothing agrees with "They" (plural) - left as written
    ```

    **No verdict moved.** That is the honest result and it is stated in the output
    rather than smoothed over: the predicate alone — `shared`, `sessions` — was
    enough for the overlap scorer to reach `kb-share` without ever needing the
    subject. On this passage the rewrite made an already-correct verdict
    *justified*; it did not make a wrong one right.

    **The refused claim is the sharper case.** `They expire after an hour` has no
    antecedent that agrees with it — the plural referent is only implied — so the
    resolver declines. Grounding scored it anyway:

    ```
      c3     unsupported 0% vs kb-cache
    ```

    Zero per cent against a document about the response cache, reported as
    `unsupported`. A reader takes that as "checked and found wanting" when the
    claim was never interpretable in the first place. The resolver's refusal is
    the only signal in the pipeline that distinguishes the two, and it is a
    signal the verifier below it cannot produce.

31. **`AnswerabilityKit`** adds the thirty-first scenario, and it is the first
    one that runs *upstream* of the money. Scenarios 26 through 30 built a chain
    that gets steadily better at telling you an answer was wrong. All of it
    happens after a provider call that has already been paid for.

    The scenario asks one question — *When did the streaming aggregator start
    dropping frames?* — against a corpus written entirely about the aggregator
    that never once states a time. It runs the question twice.

    Ungated, the model answers `began dropping frames in build 41`, and
    `GroundingKit` scores it:

    ```
      grounding: partiallySupported 43% vs doc-agg-drop
    ```

    **Not `unsupported` — partially supported.** `build 41` appears in no source,
    but every other word in that sentence overlaps `doc-agg-drop`, and an overlap
    scorer has no way to notice that the single token carrying the answer is the
    single token nothing backs. The hop was paid for, and the verdict it bought is
    reassuring about a fabrication.

    Gated, nothing is sent:

    ```
      verdict BLOCKED insufficient - missing: a time
      subject    streaming aggregator start dropping frames  affirm 0.60
      attribute  a time                                      affirm 0.00   <- nothing speaks to this
      coverage 50%, evidence examined: 3 passage(s)
      approvedQuestion: nil
      refusal reaching the user: no evidence covers: a time
    ```

    The subject scores 0.60 — the corpus really is about the aggregator, which is
    exactly why a similarity threshold sends this question. The attribute scores
    zero, and naming *which* aspect failed is something grounding cannot do,
    because by then it is judging prose rather than a need.

    `approvedQuestion: nil` is the line worth dwelling on. It is `nil` for every
    verdict except `.answerable`, so a caller that forgets to switch on the verdict
    has no text to forward and fails closed. Forwarding an unjudged question is
    still possible — it requires naming `unjudgedQuestion`, which puts the decision
    in the caller's own code rather than in a default.

    Cost: **$0.00021 ungated, $0 gated.** The metered total moved from $0.0508015
    to $0.0510115, and the delta is exactly that one hop.

32. **`MorphologyMatchKit`** adds the thirty-second scenario, and it is the
    failure mode that arrives with scenario 31. The gate refuses when nothing
    in the corpus speaks to an aspect. But "nothing speaks to it" is an
    inference drawn from a matcher finding no overlap, and that inference is
    worth exactly as much as the matcher's recall.

    The question asks about `requests` that were `retried`. The corpus says a
    client `retries` a `request`. Every word matches and none of them matches:

    ```
      lexical matcher:    BLOCKED insufficient - missing: requests retried
        subject    requests retried          affirm 0.00   <- reported as absent
        approvedQuestion: nil
      morphology matcher: ANSWERABLE
        subject    requests retried          affirm 1.00
    ```

    Same gate, same policy, same corpus — one matcher swapped underneath it.
    The conflations that earned the admission are printed rather than assumed,
    because an unauditable change of mind in a refusal path is not an
    improvement:

    ```
      retry      <- retried, retries, retry
      request    <- request, requests
    ```

    And the refusals matter as much as the merges. `note` keys to `note`, not
    `not`, under `guardedStem` — a key landing on a negation cue would make
    every clause mentioning a note read as a denial, which is an invented
    contradiction rather than a missed match.

    The line worth keeping from this scenario is the cost comparison. The
    lexical refusal cost **$0**; the correct answer cost **$0.000186**. A
    meter records hops that happened, so **a gate that refuses too much looks
    cheaper than one that is right**, and nothing in this demo's cost report
    would ever have surfaced the bug. It took a user asking a reasonable
    question and being told no.

33. **`EvidenceSensitivityKit`** adds the thirty-third scenario, and it asks
    the question scenarios 31 and 32 both stop one step short of. Both of
    them end with the gate saying yes. Neither asks *yes on the strength of
    what?*

    One question, two retrieval outcomes, same gate and same matcher. Both
    report the identical `answerable (affirm 1.00 / deny 0.00)` — the gate
    genuinely cannot tell them apart. In A the answer survives losing any
    passage and any document, and the analysis returns `robust`. In B
    retrieval happened to return only chunks of the runbook, so what reads as
    two confirmations is one source read twice.

    Passage-level leave-one-out is **structurally blind** to B: remove either
    chunk and the other still answers, so nothing pivots. Only the
    document-level pass sees that there was never a second source, and it
    reports `coincidental(2 passages, all from runbook)`.

    The hop is spent on A and withheld on B, which inverts scenario 32's cost
    lesson. There a false refusal was free, so an over-refusing gate looked
    cheap. Here the meter records not "an answer" but **an answer worth
    paying for** — $0.000294 for the stable one, $0 and a review queue for
    the other.

34. **`SourceIndependenceKit`** adds the thirty-fourth scenario, and it turns
    scenario 33's rule back on scenario 33's own assumption.

    Scenario 33 established how this ecosystem now spends money: pay for a
    verdict only if it survives its own evidence being taken apart. To apply
    that rule it has to know which document each passage came from, and it
    knew because `SensitivityPassage` carries a hand-written `document`
    field. Its own doc comment says so — *provenance has to be carried
    alongside.* Carried from where? A retriever returns URLs.

    The same four passages, question and judge run twice, changing nothing
    but where the document identifier comes from. Pass A takes it from the
    passage id, which is what a caller without one reaches for. Four
    documents, nothing pivots, `robust` — and under scenario 33's rule the
    hop is **authorised and paid**. Three of those four passages are one page
    reached three ways: a link with `utm_` parameters, an AMP copy, and an
    `index.html`.

    Pass B derives the key instead. Two sources, `pivotal` on
    `example.com/docs/rollback`, $0 and a review queue.

    `itemPivots` is empty in **both** passes, which is the part worth
    keeping. Passage-level leave-one-out was never going to catch this, and
    scenario 33 already knew that — it is why the document pass exists. What
    scenario 33 could not know is that the document identifiers it was handed
    might be fiction.

    The cost line inverts scenario 33's in turn. There the meter recorded an
    answer worth paying for. Here it records $0.000282 for the hop that
    should not have happened and nothing at all for the analysis that
    prevented it — **the correct pass is invisible to the meter, and the
    mistaken one shows up as spend.** No cost report in this demo would ever
    have surfaced this.

37. **`SignalDependenceKit`** adds the thirty-seventh scenario, and it asks the
    question scenario 36 could not: **were those judges separate judges?**

    Scenario 36 declined a turn because three origins each raised something.
    Counting origins is how it got there, and counting is exactly what cannot
    tell you whether two of them were one. Here the same corpus goes through
    four judges and the demo does not assert their entanglement — it derives it.
    The morphology judge *is* the answerability engine with its matcher swapped,
    which is how scenario 31 wires it, so their agreement is one technique
    agreeing with itself. The independence and temporal judges were handed
    passages carrying the same document ids, so the shared-input edge is
    computed by intersecting those ids rather than written down by hand.

    **Four judges, two voices, 2.38 effective votes.** The abstention survives —
    two voices still concur — but it now rests on a number that means something.
    Note which judge represents the first voice: `answerability` reported
    *clean*, and it speaks for a voice holding a concern, because a merged voice
    takes the more serious of its members' readings. A voice half of which found
    something has found something.

    Part F is the case that keeps this honest. A corpus with nothing against it
    goes through the same deflation and **answers**, and pays for the turn. A
    reduction that could only ever narrow the panel would be a way of never
    answering rather than a way of counting.

    Part E is the one a declared graph cannot reach. Over six rounds the registry
    reports `independence + temporal` co-firing **100%** of the time against the
    **67%** the graph declares. The edge was not missing; it was
    *under*-declared, which is the failure mode nobody looks for — a pipeline
    that has correctly identified its entangled pair and still overestimates how
    much daylight is between them.

38. **`ConformalGateKit`** adds the thirty-eighth scenario, and it asks the
    question underneath both of the last two: **what error rate does any of
    this actually hold?**

    Scenario 36 abstained because two judges concurred. Scenario 37 asked
    whether those two were separate. Neither asked where the number *2* came
    from. It was chosen because it seemed reasonable, and thirty-seven
    scenarios later nothing in this demo could say what it buys.

    Part A puts the demo's own labelled turns through the gate and gets a
    refusal: **two calibration points cannot certify `alpha = 0.05`; nineteen
    are needed.** That is not a failure of the scenario. It is the honest state
    of a pipeline that has been judging carefully for thirty-seven scenarios and
    labelling nothing.

    So part B labels some. Every non-empty subset of each corpus, asked at three
    instants — a real turn each time, since retrieval returning two of three
    passages is the ordinary case and a question asked later is a question the
    temporal judge answers differently. Thirty turns, scored by the same three
    analysers the rest of this demo uses, and **labelled by subtracting two
    dates rather than by asking a judge**: a calibration set graded by the gate
    it is protecting measures the gate's agreement with itself, which is 100% by
    construction. **Answering everything carries 53.3% selective risk; the
    certified threshold of 0.167 holds a joint bound of 0.0323 and costs 60% of
    the turns.**

    Part C is the finding worth the scenario. Promised per corpus instead of on
    average, the `strong` slice **breaches with a perfect record** — nine turns,
    six answered, none wrong, and still over budget, because `1/10` exceeds
    `0.05` however clean those nine were. Per-slice control costs a full
    calibration set per slice, not one between them, and no threshold holds in
    both corpora at once.

    Part D stands the certified gate beside the judges it was derived from. It
    clears the strong corpus, which is paid for; it refuses the weak one on its
    own authority, with the number it refused on attached.

39. **`CensoredFeedbackKit`** adds the thirty-ninth scenario, and it asks where
    the row above got its labels.

    Scenario 38 enumerated every non-empty subset of each corpus at three
    instants and graded all thirty by subtracting two dates — a completeness no
    deployed gate has ever had. In production a label exists only for a turn
    that was **answered**: a turn this stack refuses is never sent, never
    verified and never graded, so it cannot be in the set the gate is
    calibrated on.

    Part A asks scenario 36's arbiter which of the thirty it would have let
    through. **Fifteen.** And **nothing is censored** — which is not
    reassurance. The nonconformity score is computed from those same three
    readings, so a turn they refuse sits at the top of the scale by
    construction and the gate would never have answered it either. Every
    refusal is pinned at zero by the loss definition and none is unknown. A
    certificate whose admissions are a function of the arbiter's own inputs is
    measuring itself — scenario 37's finding, one level up.

    Part B rules on the merged panel instead, which is the app's real pipeline
    order: `signalDependence` collapses entangled voices before the arbiter
    counts them. Admission moves — **seventeen answered rather than fifteen,
    and the observed risk falls from 0.2000 to 0.1765 on a population that has
    not changed.** It still censors nothing, and the direction is why: merging
    can only remove a concurring voice, so it loosens rather than refusing
    anything new. Censoring needs a gate that refuses for a reason the score
    cannot see, and every judge in this panel feeds the score. The `ai-chat-app`
    in this series has four such gates and does produce it. This demo, stated
    plainly rather than manufactured, does not.

    Part C is the finding, and the bias runs the other way. **Nothing was
    censored and the promise still does not hold.** Scenario 38 certified
    `0.0323` over a population containing thirteen turns the arbiter would never
    have sent — and those are the easy ones, which is why they were refused.
    Restricted to the turns this stack would actually answer, **the labelled
    loss alone is 0.1000, double the budget, with no unknowns in it at all.**
    A calibration set is not made honest by being complete.

    Part D shows what withdrawing enforcement does. The certificate is
    `unsupported`, so it is not enforced, and the strong corpus is answered on
    the judges alone. This is the only stage in the stack whose effect is to
    stop a gate refusing, and it is allowed to for one reason: the refusals it
    withdraws rested on a guarantee that was never supported.


40. **`ExplorationChannelKit`** adds the fortieth scenario, and it tries to buy
    what scenario 39 could only quote a price for.

    Scenario 39 left a number sitting there — nineteen labelled refusals to
    certify `alpha = 0.05` — with nothing in the ecosystem able to produce one.
    Producing them is not a question about censoring. It is a question about
    which refusals you can afford to admit.

    Part A's finding is not about exploration at all. **Eighteen of the thirty
    turns the conformal gate is calibrated on score above its own threshold**,
    so the gate would refuse the majority of the set that certifies it. That is
    scenario 39's finding read from the other end, and it is the reason there is
    anything here to explore. Their depths run from 0.0333 to 0.3333 below the
    cut.

    Part B runs a channel over them at frequency 0.5 with a budget of $0.0100.
    **Three labels for three admissions, the budget spent to the cent.** The
    whole refused set stays `not correctable` — fifteen of the eighteen sit
    below the region's floor and could never have been admitted at any budget.
    The band alone becomes `correctable` at admission probability 0.5000. That
    split is the package's central claim and its limit: exploration made the
    band correctable, not the gate. The two estimates over it disagree loudly —
    **Horvitz–Thompson 0.4286 against self-normalised 1.0000** — because all
    three labels came back wrong. Self-normalised reports what was seen;
    Horvitz–Thompson divides it across the band it stands for. On an effective
    sample size of **3.00** both are honest and neither is worth acting on.

    Part C sweeps the bands and reproduces, on the gate's real calibration
    scores, the regime switch the package's own demo shows on synthetic depths.
    At $0.0100 the optimum is **interior**: the band reaching 0.1667 bounds at
    **0.8421**, while the band covering every refusal bounds at **0.9703** — a
    worse bound, on two labels rather than three, for less money. Raise the
    budget to $0.2000 and it stops binding: the widest band wins outright at
    **0.3301**. More exploration is better exactly until you cannot afford the
    whole band.

    Neither band gets near nineteen labels. The honest reading is that a band
    worth buying exists and the certificate is still out of reach — which is a
    more useful answer than "explore more".

41. **`LabelReturnKit`** adds the forty-first scenario, and it asks where
    scenario 40's three labels came from — specifically, *when*.

    Scenario 40 could label an admission in the same statement that admitted it,
    because this demo holds every turn's ground truth in memory. No deployed
    system has that. Outcomes arrive later, incompletely, and the ones that
    arrive first are not a random half: a clean answer is confirmed quickly, and
    a wrong one surfaces through a complaint or a correction, which is slower.
    The delay here is built from the demo's own data — a turn's nonconformity
    score plus a six-tick penalty for having been wrong.

    Part A is the population: **12 turns the gate admitted at `p = 1.00`, plus
    the 3 refusals the channel bought at `p = 0.50`**. The refusals nobody
    answered are deliberately absent — there is no outcome to wait for, and
    their absence is scenario 39's censoring rather than this scenario's
    incompleteness.

    Part B reads it at eight cutoffs. **The floor sits at `0.0000` for nine
    ticks and the promise looks kept the whole way.** Every loss lands at t10
    together, and the verdict goes straight from `undetermined` to `withdrawn`
    against a budget of `0.0500` on a measured `0.3333`. Nothing changed at t10
    except that the evidence arrived.

    Part C is the finding, and it runs against the package's own headline.
    **The pooled figure withdraws a certificate the gate never broke.** Split by
    region, the twelve turns the gate chose to answer contain **not one loss** —
    `[0.0000, 0.0000]`, holds with the full `0.0500` to spare. All three losses
    are refusals the channel bought, at `[1.0000, 1.0000]`, and it bought them
    precisely because the gate was unsure. They are enriched for exactly the
    outcome being counted.

    So comparing the pooled rate to `alpha` compares a promise about answered
    traffic against a population deliberately stocked with the refused kind.
    **Exploration does not only cost money — it makes the naive risk figure
    worse by construction**, and an audit that cannot say which region a loss
    came from will read that as a gate failing. Scenario 40 bought the labels;
    this one shows that where you put them decides what they mean.

    Part D bands the three admissions by depth and reports that it cannot: all
    three sit at exactly `0.1667`, so there is nothing for the selectivity check
    to compare. Left in rather than tuned away — the check is only as good as
    the spread of what was bought, and a channel that drew three turns from one
    depth bought no ability to detect a depth-selective return.

45. **`CurveDivergenceKit`** adds the forty-fifth scenario, and it is the first
    one in this series whose honest result is *"this is not the case the package
    was built for."*

    Scenario 44 part C established that the two label classes separate on delay
    without fitting anything, using a log-rank statistic and a sweep of
    restricted means. Both are areas, and an area over a window that contains a
    crossing is a positive region added to a negative one. A supremum is a
    height: it takes the largest disagreement anywhere in the shared window and
    cannot cancel, and it reports **the tick it happened at** without being
    asked about any horizon.

    On this panel the two curves do not cross. The loss class has produced
    **nothing** by t8 while the clean class has almost entirely resolved, so the
    loss curve is flat at one against a curve at zero: `KS 1.0000 at t8`,
    permutation `p 0.0010`, shape `first stays above throughout`. Log-rank
    reports `chi2 216.1638` on the same pair. **They agree, and they agree
    because dominance is the geometry where an area and a height say the same
    thing.** The scenario says so in its own output rather than implying the
    supremum rescued something.

    It did find a real defect, though — not in this repository. `CurveDivergenceKit`
    1.0.0 *declined* this comparison: it refused whenever one arm had no label
    inside the shared window, on the reasoning that there was no tick to compare
    at. Running it here fired that refusal on this demo's strongest result. A
    flat line at one against a fallen curve is the largest gap two survival
    curves can have. The refusal was removed in 1.0.1, and this scenario is the
    reason the shared demo exists: no unit test in that package disagreed with
    it, because every one of them had been written by the same person who
    believed it.

    The `48.89%` censoring gap is printed next to the verdict and not corrected
    for. A permutation null assumes the class labels are exchangeable, which is
    a claim about how the two classes were *observed* and not only about how
    fast they resolve — and nothing in this panel can tell a slow class from a
    class read late.

47. **`SelectionTrustKit`** adds the forty-seventh scenario, and it is the first in
    this series to be pointed at another package's model rather than at data.
    Scenario 21 has `ToolAuthorityKit` refusing an outbound send because its
    arguments carry an untrusted provenance. Scenario 47 asks the question that
    ceiling cannot answer: the planner reads the same poisoned passage and then
    proposes refunding order 9001, a real order whose id came out of the app's own
    table. Every argument is authentic. `ToolAuthorityKit` answers `APPROVAL
    REQUIRED` — and answers `APPROVAL REQUIRED` again when the *user* picks the
    same order, because on its ladder nothing about the two cases differs.
    `SelectionTrustKit` refuses the first and prompts on the second. The gap
    between those two verdicts is the whole claim, and it is printed rather than
    argued. This is not a defect in `ToolAuthorityKit`: a ceiling is doing exactly
    what a ceiling does, and the finding is that one axis cannot express the
    question.

46. **`LabelClockKit`** adds the forty-sixth scenario, and what it measures is
    the two scenarios before it.

    `delayCurveSample(_:asOf:wrong:)` splits the population on `wasWrong` and
    *then* marks a turn outstanding when its delay runs past the cut-off. Read
    those two steps in order. The second says the label has not come back. The
    first says which class the turn is in — and for an outstanding turn that is
    knowable here only because the fixture generated it. A service holding real
    traffic has exactly the outstanding turns and none of their classes, so the
    censored observations in scenarios 44 and 45 are honest arithmetic over a
    class assignment nothing in production could make. The statistics were never
    wrong; the claim that a live gate could reproduce them was.

    The audit puts a number on it. Cohort taken from `wasWrong`, timestamped
    when the label returned: `phi 1.0000`, `censorable 0/480`, all 325 paired
    turns simultaneous. **Seventeen landmarks across the whole follow-up, 17
    refusals, 0 arms formed** — and not from scarcity. A turn carries a cohort
    exactly when its label has come back, and the landmark method excludes
    exactly those, so the surviving set is empty by construction at every
    landmark rather than by luck.

    Then it runs the comparison a gate actually can. The conformal
    nonconformity score exists before any answer is judged, which is the whole
    qualification for being a cohort. Banding on it gives `separated (155
    censorable units)`, a longest lead of 15 ticks, and two arms at t+1 —
    `flagged: 160 units, 84 outstanding` against `unflagged: 320 units, 71
    outstanding`. Handed to the same `DelayCurveKit` and `CurveDivergenceKit`
    as scenario 45: `KS 0.6646, p 0.0010`, first stays above throughout. The
    band is the coarse one — any nonconformity, or none — because this scorer
    emits three distinct values across these turns and its median is its
    minimum, so a quantile split would put every turn on one side. That is
    stated in the output rather than smoothed over.


48. **`ArgumentAttributionKit`** adds the forty-eighth scenario, and it is the one
    that asks scenarios 21 and 47 a question neither of them can answer about
    itself: *which argument did the passage actually touch?* Both of those
    refusals are stamped on a whole call. Scenario 48 runs both calls through an
    attribution ladder against the passages `RetrievalKit` really returned, and
    the two answers come out opposite. Scenario 47's refund — `orderId 9001`,
    `amount 40` — attributes to **nothing**, which is correct: those bytes came
    out of the app's order table, and what the passage supplied was the choice,
    not the value. Scenario 21's injected send attributes **2 of 3**: the
    recipient `audit-backup@example.net` is found verbatim at `21.97` bits and
    `customer-list` is found across a punctuation boundary at `10.98`, while
    `orders/1234` is ours and is tainted only by proximity. Three packages, three
    different questions, and the pair of verdicts is the evidence that none of
    them subsumes another. The report it prints carries a lower bound and an
    upper bound and refuses to name a number between them, because a value can
    come from a passage and share no key with it.


49. **`EffectiveVoteKit`** adds the forty-ninth scenario, and it is the first one
    that audits a number an earlier scenario has been publishing for twelve runs.
    Scenario 37 deflates a four-judge panel using a `DependenceGraph` whose
    strengths are **declared**: `answerability` and `morphology` share a heuristic,
    `independence` and `temporal` share an input. Both declarations are right in
    kind. Neither has ever been checked in degree, because nothing here could
    measure a degree. Scenario 49 runs those same four analysers over ninety-six
    constructed corpora, labels each corpus by **how it was built** rather than by
    what any judge said about it, and measures what the four actually did.
    Both declarations turn out to be wrong, in opposite directions. The shared
    heuristic is declared `0.70` and measures `1.0000`: those two are not
    correlated, they are the same judge on this corpus, and swapping the matcher
    changed nothing. The shared input is declared `0.60` and measures `0.0000`:
    reading the same document ids produced no shared mistake at all. And the
    aggregate hides both — `2.42` effective votes declared against `2.67`
    measured, close enough to read as agreement while every component underneath
    it is wrong. The pivotal stratum reports `4.00 of 4`, which is not credible
    and is not meant to be: selecting a one-vote margin conditions on the sum of
    the votes being correlated, so the library refuses to call that direction a
    finding.

## Quality

50. **`ProxyLabelKit`** adds the fiftieth scenario, and it takes away the one
    thing scenario 49 was handed for free. That scenario measures error agreement
    between four analysers, which it can only do because each corpus carries a
    label describing how it was **built**. No deployment has that. It has a
    downstream outcome and a decision to call it a label.

    Scenario 50 runs the same ninety-six corpora twice — once with the
    construction label, once with a proxy derived from an item-scoped outcome
    that is wrong 12% of the time — and no judge changes a single verdict
    between the two runs. The aggregate barely moves: **2.6667 effective votes
    to 2.7747**, close enough that every check anyone would run on it passes.

    Underneath, four pairs whose true association is exactly **0.0000** move to
    -0.0819, -0.0090, -0.0090 and +0.0650. That correlation was not measured. It
    was manufactured by the label, on a panel where nothing about the judges
    changed.

    The audit prices the proxy at `0.1000 [0.0466, 0.2015]`, which contains the
    real 0.12. And then the fiftieth scenario reports a bound that **misses**:
    `independence x temporal` is bounded to `[0.0815, 0.2565]` against a truth of
    `0.0000`. That is not a defect in the deconvolution — the interval carries
    the flip rate's uncertainty and not the table's, and ninety-six items put
    roughly 0.10 of sampling error on a phi near zero. The scenario says so on
    the line beneath, because a bound printed without the assumption it rests on
    is worse than no bound.

51. **`SampleWidthKit`** adds the fifty-first scenario, and it answers the
    question the fiftieth ended on. Scenario 50 reported four pairs moving off a
    true association of exactly `0.0000`, and a bound that excluded that truth.
    Both readings come from ninety-six items, and neither scenario asked what
    ninety-six items can support.

    Scenario 51 asks. **Five of the six movements are unresolved** — the interval
    around each straddles the value it moved away from, and the counts that would
    settle them run from 574 items to 47,617. The sixth is not a movement at all:
    `answerability x morphology` sits at a phi of exactly `1.0000`, where the
    Fisher transform is unbounded, and the scenario prints that refusal rather
    than dropping the row. An earlier draft of this scenario used `try?` and
    quietly showed five pairs where six existed, which is the failure this whole
    series keeps finding: **a gap that looks like an absence is worse than a
    refusal that looks like a problem.**

    Then it repairs the bound. The same de-noising, handed the sampling interval
    `[-0.2233, 0.3428]` instead of the single number `0.0650`, returns
    `[-0.2110, 0.4320]` — **0.4680 wider, and it contains the truth**. Nothing
    about the de-noising changed. It was handed both uncertainties instead of one.

52. **`FamilyErrorKit`** adds the fifty-second scenario, and it corrects the
    page the three before it wrote. Scenarios 49, 50 and 51 each publish a
    reading for every pair of the four-judge panel. Six readings, six
    intervals, every one at a nominal 95% — and nothing anywhere asked what
    six of them hold at together.

    Scenario 52 asks. **12 of the 15 pairings of those six pairs share a
    judge** — 80% overlap, which is not an assumption anyone has to argue
    about but a count the panel's shape fixes. Independence was never
    available, so `BenjaminiYekutieli` is the ledger's default and pays
    `H(6) = 2.4500` for dropping it.

    Then it widens. `answerability x temporal` goes from `[-0.3577, 0.2071]`
    to `[-0.4425, 0.3015]` — **0.1793 wider**, at a member level of
    `0.991667` each. The widening happens on the `atanh` scale the Fisher
    interval is symmetric on; scaling the printed half-width instead returns
    `[-0.4554, 0.3048]`, and the package marks that route `exact: false`
    rather than letting it pass as the same answer.

    The finding is which pair could not be re-quoted. **The largest reading
    on the page is the one member the correction cannot touch** —
    `answerability x morphology` sits at a phi of exactly `1.0000`, where
    `atanh` is unbounded, and the scenario prints that refusal in the same
    place scenario 51 hit it. Scenario 51 widened these readings for the
    corpus. Nothing until now widened them for each other.

- **Build:** `swift build` — clean, zero warnings, resolving all sixty
  dependencies from their real tagged releases.
- **Run:** `swift run LLMEcosystemDemo` — exercises the real, compiled code
  of all sixty packages together; the output above is a genuine capture,
  not a mock-up.
- **Lint:** `swiftlint lint --strict` — zero violations. (An earlier version
  of this README noted `swiftlint` wasn't installable in the sandbox this
  demo was originally built in and that the source had been hand-checked
  instead — that limitation was specific to that sandbox, not this
  package; on a machine with the toolchain installed natively, the real
  binary runs and passes clean.)

This repository intentionally has no test target — it's an integration
demo, not a library with independently testable units. Correctness here
means "the sixty real packages compose and run," which the sample output
above demonstrates directly rather than through unit assertions.

## Architecture

```
Your prompt schema (JSONSchemaConvertible)
        │
        ▼
StructuredOutputKit.PromptBuilder  ──instructions──▶  ProviderGatewayKit.LLMSession
        ▲                                                       │
        │                                              routed reply text
        │                                                       ▼
StructuredOutputKit.StructuredOutputDecoder  ◀──raw text── ProviderRouter + ScriptedProvider
        │
        ▼
   typed, validated value                     TokenMeterKit.TokenMeter records
                                               usage + cost for every routed hop

ResponseCacheKit.ResponseCache sits in front of a second LLMSession/ProviderRouter
pair for the fourth scenario: response(for:) is checked before every routed
send() — a HIT returns immediately with no router call; a MISS routes, meters,
then store()s the reply for the next identical request.

For the fifth scenario, a routed turn's reply is decoded as a tool-call
request; ToolRegistryKit.ToolRegistry.dispatch(_:) schema-validates the
arguments, runs the registered handler, and the result is fed into a
second routed turn whose reply is decoded as the final typed answer.

For the sixth scenario, AgentLoopKit.AgentLoop.run(initialPrompt:) drives
the same LLMSession + ToolRegistry pair through a bounded decide/act/
observe loop across two dependent get_weather calls; TokenMeterKit meters
every step straight off the returned AgentTranscript, after the fact.

For the seventh scenario, GuardrailKit.GuardrailPipeline sits on both sides
of an LLMSession/ProviderRouter pair: screenRequest(_:) redacts PII from
the user's prompt before send() is ever called, and screenResponse(_:)
screens the routed reply on the way back out. A second prompt trips a
BannedPhraseRule and is blocked before any router call happens at all.
Every screening is recorded as a GuardrailEvent, regardless of verdict.

For the eighth scenario, TraceKit.Tracer wraps the same decide/dispatch/
answer round trip the fifth scenario hand-rolled: each LLMSession.send()
and ToolRegistry.dispatch(_:) call is wrapped in withSpan(name:kind:
parentID:operation:) under one root agentStep span. Tracer.trace(rootID:)
reconstructs the full nested trace afterward, and EvalGate.run(_:scorers:)
scores it against NoErrorSpansScorer and MaxDurationScorer, producing an
EvalGateReport instead of a print statement someone has to read by hand.

For the ninth scenario, RetrievalKit.Retriever indexes four documents with
a HashingEmbeddingProvider, then retrieveContextBlock(query:) ranks stored
chunks by cosine similarity and returns the top matches as a prompt-ready
text block — computed entirely locally, no routed call involved yet. That
block is prepended to the prompt for a single routed LLMSession.send()
call, decoded as a RAGAnswer. RetrievalKit has no compile-time dependency
on ProviderGatewayKit; the seam is exactly what a host app would wire up
itself — retrieve, then prepend, then send.

For the tenth scenario, PromptTemplateKit.PromptRegistry registers a
context+question system-prompt template at v1, promotes a more explicit
v2 that becomes active immediately, and render(name:variables:mode:) renders
that active version (strict mode) into real prompt text — only that
rendered string, never the raw template, is handed to a routed
LLMSession.send() call, decoded as a RAGAnswer and metered exactly like
every other scenario. rollbackToPrevious(name:) then restores v1, and a
second render(mode: .lenient) call leaves an unresolved placeholder as
literal text instead of throwing. Every register/promote/render/rollback
action is captured by an InMemoryPromptAuditRecorder. PromptTemplateKit
has no compile-time dependency on ProviderGatewayKit either — the seam is
the same one every sibling kit uses: render (or retrieve, or dispatch)
first, then send.

For the eleventh scenario, RetryPolicyKit.RetryExecutor wraps a routed
LLMSession.send() call against a FlakyProvider that genuinely throws for
its first two attempts, then succeeds. The same LLMSession is retried
across all three attempts rather than rebuilt per attempt: CircuitBreaker's
default failureThreshold is 3 consecutive failures, so two failures
followed by a success never trips it. ExponentialBackoffRetryPolicy
computes the wait between attempts, an InMemoryRetryEventRecorder captures
every attempt (including the two failures), and only the final, successful
call is metered — matching how real LLM billing charges for completed
responses, not failed ones.

For the twelfth scenario, a routed LLMSession conversation grows across
four real turns (LLMSession's own ContextBudgetManager is given a
deliberately huge 100,000-token budget so it never trims anything here).
session.currentTranscript() is bridged into
[ContextCompactionKit.CompactableMessage] — the two role enums share the
same case names, so mapping through rawValue is the whole seam — and run
through ContextCompactor.compact(_:budget:) with all three tiers chained
(SlidingWindowCompactionStrategy, TruncatingCompactionStrategy,
SummarizingCompactionStrategy) against a 100-token budget the raw
9-message transcript can't fit. The compacted CompactionResult.messages —
not the raw transcript — are joined into a text block and handed to the
next routed LLMSession.send() call, decoded as a RAGAnswer and metered
exactly like every other scenario. An InMemoryCompactionEventRecorder
captures the before/after token and message counts and which strategies
fired. ContextCompactionKit has no compile-time dependency on
ProviderGatewayKit either — the same seam every sibling kit uses.

For the thirteenth scenario, AgentMemoryKit.MemoryStore holds three
memories written in an earlier "session" (a pinned persona fact, a
preference, and a low-importance aside) and recall(query:topK:) ranks them
via CompositeMemoryScorer — semantic similarity blended with recency,
importance, and access frequency, not raw vector distance alone — and
returns the two most relevant. Their content is folded into the prompt for
a routed LLMSession.send() call, decoded as a RAGAnswer and metered exactly
like every other scenario. A final decay(pruneBelow:) call fades and prunes
the low-importance aside while the pinned persona fact survives untouched.
AgentMemoryKit has no compile-time dependency on ProviderGatewayKit either
— the same seam every sibling kit uses: recall, then fold into the prompt,
then send.

For the fourteenth scenario, SemanticRouterKit.SemanticRouter registers
three support intents, each with seed utterances and a metadata["model"]
pointing at the model a match should route to. route(query:) embeds the
incoming message once and returns the closest intent above its threshold;
the matched route's metadata — not a hard-coded branch — chooses which
provider the real routed LLMSession.send() call targets, whose reply is
decoded as a WeatherReport and metered exactly like every other scenario.
This is the two-layer routing seam: SemanticRouterKit routes by meaning,
ProviderGatewayKit routes by capability, and the two join only at the
metadata value — neither depends on the other at compile time.

For the fifteenth scenario, OutputRepairKit.OutputRepairLoop.run(initialPrompt:
producer:) wraps a routed LLMSession as its ResponseProducing seam. The
scripted provider's first reply omits the required conditions field, so the
loop's WeatherRepairContract.validate(_:) returns .invalid with a structured
RepairIssue; DefaultRepairPrompter folds that issue into a correction prompt,
the loop re-prompts the same LLMSession, and the second routed reply validates.
Both hops are metered under repair-host (registered with its own rate so the
cost isn't a silent $0), and an InMemoryRepairEventRecorder captures the five
RepairEvents. OutputRepairKit has no compile-time dependency on
ProviderGatewayKit or StructuredOutputKit — the producer and the contract are
the only seams: produce, validate, feed the reasons back, then re-produce.

For the seventeenth scenario, BatchInferenceKit.BatchProcessor.process(_:) runs
five BatchRequests with ConcurrencyLimit(2) against a GatewayBatchExecutor — the
BatchExecuting seam — which builds a ProviderRouter/LLMSession per item and
validates each routed reply with StructuredOutputDecoder. One session per item
rather than one shared across the batch: LLMSession serializes the turns of a
conversation, and a batch's items are independent requests, not turns. The
adapter's throw on the one reply missing conditions becomes a single
BatchItemError of kind .executorFailure, and .continueOnFailure keeps the other
four running; BatchReport.outcomes still comes back in submission order, and
BatchStats.peakActive reports 2 — measured at admission, so it is proof the bound
held rather than a sample that happened to look right. BatchProcessor sums
BatchTokenUsage across successful items only, and that single total is what
TokenMeter.record bills under batch-host, so the failed item costs nothing.
BatchInferenceKit has no compile-time dependency on ProviderGatewayKit,
TokenMeterKit, or RetryPolicyKit — it deliberately ships no retry or cost logic,
which is what leaves those two jobs where they already belong.

For the eighteenth scenario, RealtimeSessionKit.RealtimeSession drives a full
drop-and-resume cycle over a GatewayRealtimeTransport — the RealtimeTransport
seam — which routes each turn through its own ProviderRouter/LLMSession and
validates the reply with StructuredOutputDecoder. Turn c1 is acknowledged and
leaves the outbox; turn c2's ack never arrives before the socket drops, so
handleDisconnect() returns retry(attempt: 1, delayTicks: 125) — a full-jitter
ceiling of 250 ticks with the jitter source pinned to its midpoint, which is why
the number is assertable at all. reconnect(elapsedTicks: 4) is inside the 30-tick
resume window, so the transport is asked to continue from the client's own cursor
(lastServerSequence: 1) rather than start over, and the unacknowledged c2 is
replayed: two turns cost three gateway hops, which is what at-least-once actually
means rather than what it promises. The buffered srv-2 is then accepted and its
immediate redelivery is caught as duplicate(repeatedID) by the id window. All
three hops — the replay included — are billed under realtime-host, so the cost of
the retry is visible instead of hidden. RealtimeSessionKit has no compile-time
dependency on ProviderGatewayKit or StreamAggregatorKit: it sits underneath the
aggregator, owning the session that streamed responses arrive on rather than the
reassembly of any one of them.

For the nineteenth scenario, IdempotencyKit.IdempotencyGuard wraps the same kind
of routed call in an at-most-once guarantee. GatewayEffectExecutor is the
EffectExecuting seam: it builds a ProviderRouter/LLMSession per effect and
validates the reply with StructuredOutputDecoder, and it appends to its hop list
only when it actually runs — so "the duplicate was free" is measurable rather
than asserted. Three attempts at filing the Shimla alert under the derived key
k-25b33bd81297ca7c produce executed, replayed, replayed and exactly one gateway
hop. The same key with severity changed is rejected as keyReuseConflict, because
replaying the stored alert would answer a question nobody asked. The Kochi alert
fails indeterminate — a timeout after the request was sent, so the alert may
already be filed — and the guard freezes the key rather than let an optimistic
retry file it twice; the hop count stays at one until a reconciler calls
resolve(key:as: .notApplied), after which it executes for real. Only the two
executed hops (15+33 tokens) bill under idem-host. Where RealtimeSessionKit made
the cost of a replay visible, IdempotencyKit removes it: this is the guard that
makes the rest of the toolkit's retrying safe to point at a side effect.
For the twentieth scenario, SchemaMigrationKit.SchemaRegistry owns the one thing
none of the other nineteen packages does: a payload's shape changing over time.
StructuredOutputKit validates one payload against one schema and PromptTemplateKit
versions prompt text, but neither can take an object written under v1 and produce
a valid v2. The registry walks adjacent registered versions only — a v1 -> v3
shortcut step is refused at registration, because it would let a payload reach v3
without ever being checked against v2 — and it validates the result of every hop
against the schema that hop promised, so a step that claims v2 and does not
deliver it fails at that step rather than three layers later as a decode error.
FieldValueJSON is the single adapter between the package's own FieldValue
vocabulary and the JSON text StructuredOutputDecoder consumes; that adapter is
the entire cost of SchemaMigrationKit having no compile-time dependency on any
sibling package. Loss is declared per step rather than inferred from a diff,
because only the step's author knows whether a vanished field was folded into
another one (conditionCode -> conditions, lossless) or genuinely discarded
(stationId, lossy) — and a path that drops anything is refused until the caller
says so.

```


58. **`AssociationFitKit`** adds the fifty-eighth scenario, and it is the other half of the
    specification scenario 57 completed. `SquareDesignKit` fixes a panel's **trace**; on a
    three-category panel that pins one number and leaves eight cells to whatever the
    construction happens to do. This package fixes the **association** instead — as a
    structure rather than a scalar — and lets the trace be the consequence.

    Iterative proportional fitting is the method the applied literature already uses, and
    what makes it right here is what it cannot change: scaling a row multiplies every cell
    in it by one factor, and a local odds ratio takes two cells from each of two rows and
    two columns, so every factor cancels. On this demo's own margins the fit moved the
    margins into place and changed the nine odds ratios by **4.441e-16**.

    Four structures on one set of margins give four different panels — agreement `0.5000`,
    `0.5986` and `0.7254` for independence, uniform association at 3, and a diagonal weight
    of 6 — which is the point: **the agreement rate was never a free parameter, it is what
    the margins and the structure leave.** Quasi-independence is refused outright on this
    panel, and the refusal names why: forbidding the diagonal leaves judge one's 72
    affirmations only 48 columns to land in.

    **The scenario's sharpest result is a negative one.** Asked to compare its panel against
    `SquareDesignKit`'s at the same trace, the two came back **identical cell for cell** —
    because no judge in this corpus has ever abstained, so the third category is empty and
    the panel is really two-by-two, where one free cell means any single requirement fixes
    the whole table. That is `PanelDesignKit`'s finding arrived at from the opposite
    direction, and it is a fact about the fixture rather than about either package.

    Then it prices the last step. A fit is real-valued and a panel is made of whole verdicts,
    and the rounding keeps **every margin exact on every structure** while moving the
    association by up to `2.011e-01` here and `7.500e-01` in the package's own demo. A page
    that quotes a designed odds ratio and computes over the rounded panel is quoting a number
    the panel does not have.

59. **`AssociationTransportKit`** adds the fifty-ninth scenario, and it asks the question this
    series has only ever asked in the other direction. Scenarios 50 through 58 all start from a
    structure somebody **named** — independence, uniform association, a diagonal weight — and
    ask what table carries it. Nobody has asked the corpus what structure it already has.

    Answering that needs something scenario 58 never built. A margin says how often each gate
    said each thing; an association lives in how often they said them **together**, so this
    scenario cross-tabulates the pair into a joint panel first. On this corpus that panel is
    `[[36, 36, 0], [12, 12, 0], [0, 0, 0]]` — 96 items with **five of nine cells empty**.

    **It refuses to read it undecided, and the refusal is the point.** A count of zero means
    either "these gates cannot produce this pair" or "they have not yet", and nothing in the
    counts distinguishes them. Read as a rule, the empty third category cannot be seeded at all
    and the transport fails with `seedLineEmpty(index: 2, isRow: true)`. Read as an absence, the
    same panel carries onto balanced margins without complaint and agreement moves from `0.5000`
    to `0.5691`. Same table, same arithmetic, opposite outcomes, and the only difference is a
    decision iterative proportional fitting normally takes silently on the caller's behalf.

    **The sharpest number is the interval.** Every reading carries Woolf's standard error, and
    on 96 items **0 of 4 blocks clear independence at 95%** — the widest spanning a factor of
    **15766.2**, and the one block with any real precision would need **1320 items** to separate
    its `2.9200` from nil. Scenarios 50 through 58 publish coefficients over this fixture. The
    structure underneath them is not distinguishable from no structure at all, and three of its
    four odds ratios exist only because half an item was added to every cell.

    The scenario also found a defect in the package on its first run and it was fixed rather
    than described. Block `(0, 0)` is `36, 36, 12, 12`, which reads `1.0000` raw and `1.0000`
    corrected — it does not move, and `1.0.0` reported that as a move **away** from
    independence. `CorrectionDirection` in `1.1.0` has three cases instead of two.

60. **`ExactAssociationKit`** adds the sixtieth scenario, and it audits the one before it.

    Scenario 59 measured the corpus's own structure and put an interval around every block of
    it. That interval is **Woolf's** — the log odds ratio plus or minus `1.96` standard errors,
    where the error is the square root of the summed reciprocals of four counts. It is the
    standard choice and it is **asymptotic**: a normal approximation, valid in the limit of
    large counts. This corpus has 96 items and five of its nine cells are empty.

    Conditioning a two-by-two block on **all four** of its margins removes every nuisance
    parameter and leaves the odds ratio alone, as the noncentrality parameter of Fisher's
    noncentral hypergeometric distribution over a finite support. Probabilities can then be
    summed rather than approximated, and an interval built by inverting two one-sided exact
    tests needs no normal approximation and no repair for an empty cell.

    **The first finding is that three of the four blocks were never estimable.** Their margins
    contain a zero, which pins them to exactly one table: no method reads an association off
    them, and `ExactAudit` lists them as `degenerateBlocks` rather than repairing them. Every
    odds ratio those three blocks contributed to scenarios 50 through 59 was created by the
    half-item correction. On the one block that is readable, both methods run on the raw counts:
    exact `[0.3574, 2.7979]`, Woolf `[0.3970, 2.5192]`, the exact interval **11.4% wider** on
    the log scale, and both covering `1`. Its conditional MLE is exactly `1.0000` and its Fisher
    two-sided p is exactly `1.000000` — the corpus's one estimable block is at independence.

    **The second finding is a direction, not a caveat.** "Asymptotic methods are approximate"
    leaves open which way they err. Swept over every two-by-two table of at most twenty items
    with no empty cell — a few thousand of them, a test in the package's own repository — the
    exact interval was **never** the narrower of the two, and the closest Woolf came was still
    18.2% short. Woolf is not sometimes optimistic in this range. It is optimistic on all of it.

    The package also carries `midP`, the same inversion with the observed table counted half in
    each tail, and `ExactReading.conservatism` to price the exact method's guarantee: the
    readable block's exact interval is 9.3% wider than its mid-p one, which is what a discrete
    support costs when it cannot place a tail probability at exactly `0.025`.


## License

MIT © 2026 Rajat S. Lakhina. See [LICENSE](LICENSE).


53. **`EffectiveComparisonKit`** adds the fifty-third scenario, and it measures
    the number scenario 52 had to assume. Benjamini-Yekutieli is valid under
    arbitrary dependence and charges `H(6) = 2.4500` for the privilege. That is
    the right default when you cannot see the dependence. This panel's
    dependence is visible: **12 of the 15 pairings share a judge**, and the
    design fixes the correlation between two comparisons that do at exactly a
    half, which is also the largest value the geometry admits.

    Measured rather than assumed, **BY's multiplier of 14.7000x becomes
    4.7930x**. The threshold moves from `8.512e-03` to `1.043e-02` and the
    critical reading from a family-wide bar to `|z| = 2.5612`.

    The scenario's more useful half is the mistake it does not make. Four of the
    five estimators return the panel's **rank** — Li-Ji lands on `4.0000`, the
    four judge effects every one of the six comparisons is built from — and a
    multiplicity threshold is a statement about the family's **maximum**, whose
    count here is `4.8912`. On a ten-judge panel those two numbers are `10` and
    `32.65`, and the rank is the flattering one. So `EffectiveCount` carries the
    question it answers, `MultiplicityBudget` throws `rankSpentAsThreshold`
    rather than dividing by a rank, and the ledger throws
    `creditFromAssumedCorrelation` rather than spending independence nobody
    measured. Both refusals are exercised in part D with a headline, a reason and
    a recovery action.

    **On this page the calibration changes nothing**: one finding survives under
    Benjamini-Yekutieli and the same one survives under `m_eff = 4.8912`. That is
    reported rather than dressed up. A correction that would have made a
    difference on some other page is not a correction that made one here, and the
    scenario that pretends otherwise is the one this series is written against.
54. **`ObservedNullKit`** adds the fifty-fourth scenario, and it stops assuming
    the thing scenario 53 spends. That correction is derived from panel
    geometry, which is honest about the *design* and still carries two claims
    about a *distribution*: that the family's null is Gaussian, and that a
    correlation of one half is something these gates' agreement rates can
    produce. This panel has grades. Both can be checked instead of assumed.

    **One of them cannot even be stated here, and that is the result.**
    `answerability` and `morphology` agreed on **all 96 items**. A constant
    agreement indicator has no correlation with anything, so the fitted route
    has no matrix to fit — and a Frechet bound needs two marginals with
    variance, so the attainability question has no answer either. The scenario
    prints both refusals rather than rounding them to "fine". **The bootstrap
    needs neither and answers anyway**, pricing the tail at `2.4495` over the
    **199** readings a 96-item lattice admits, where the raw quantile happened
    to land on the grid already.

55. **`ChanceAgreementKit`** adds the fifty-fifth scenario, one level below
    scenario 54. `ObservedNullKit` prices the *family tail* and its ledger
    refuses anything that is not one, because a judge-label permutation destroys
    exactly the dependence a multiplicity denominator exists to price. That left
    a question standing: for one pair, is this reading above chance at all, and
    what is "chance" here?

    The answer is that **a chance baseline is the mean of a resampling scheme**,
    and picking a coefficient is picking an assumption you did not state. Cohen
    holds each judge's own rate fixed; Scott treats the judges as
    interchangeable; Bennett discards both rates. Their chance terms are the
    exact means of those three schemes, and Gwet's is the mean of none of them.

    **On this page the finding is about the page.** Every distinct pair of gates
    has an association of exactly nil: `PanelSpec.all` is a fully crossed design,
    so each joint count equals the product of its marginals over `n` to
    `0.000000`, and every coefficient is exactly `0.0000` with a deviate of
    `0.000`. Four scenarios above publish coefficients, intervals, corrections
    and thresholds over this panel; this is the first one able to say that the
    true pairwise association underneath all of them is zero by construction, and
    that the single nonzero reading — `answerability` against `morphology` at
    `1.0000` — is a coefficient of one between two judges that are one judge.

56. **`PanelDesignKit`** adds the fifty-sixth scenario, and it is the answer to
    what scenario 55 found rather than another reading of it. Scenario 55 noticed
    that this demo's panel carries no association; this one treats that as a
    property of the **fixture** — the thing every coefficient above is computed
    over, and the one input nobody checks.

    Three readings come out of it. **The agreement rates two judges can produce
    are bounded on both sides**: `answerability` and `temporal` can agree on
    between 8.33% and 41.67% of items whatever either of them knows, so a fixture
    asked for anything outside that is asked for a panel they forbid. **Inside the
    range most rates do not exist either** — a two-category panel with fixed
    margins has one free cell, so the agreement count steps by two and only 25 of
    the 49 integers between floor and ceiling are reachable. And **`certify` is
    the only call that refuses**: diagnosing a fixture is arithmetic, certifying
    one is a claim that it had association in it to find.

    **The whole-panel test passes, and that is the finding.** Five of the six
    pairs sit at exactly `0.000000`; the sixth is `answerability` against
    `morphology`, which is one judge counted twice. Certify the panel as a whole
    and it is accepted — a single duplicated judge is enough to answer "does any
    pair carry something". Certify each pair on its own and every distinct pair
    refuses. Two more things were not the expected answer: the affirm grid of a
    fully crossed design is **not itself fully crossed**, because these judges are
    functions of the axes rather than the axes, and identical marginals forbid an
    agreement count of `n - 1` at every category count, since the item that leaves
    a category leaves it one short and something has to move in.

    Then it builds the panel the last six scenarios have needed. Same two judges,
    same rates — 72 and 48 affirmations of 96 — repaired to an odds ratio of six.
    As the corpus built it: `kappa 0.0000`, deviate `0.000`, `p = 5.00e-01`.
    Designed: `kappa 0.2917`, deviate `3.283`, `p = 5.14e-04`. **Only the pairing
    changed.** The first row cannot show a coefficient because there is none to
    show; the second is a fixture, not a finding, which is what a control panel is
    supposed to be.


    Part D also exercises the two refusals the package exists for. A
    **judge-label permutation** — the construction recent panel-reliability work
    uses — shuffles each gate independently, which breaks the dependence a
    denominator is supposed to price; it answers a chance baseline and the
    ledger will not spend it. An **item permutation** looks like a permutation
    test and leaves every agreement count invariant, so its null is a point mass
    sitting exactly on the reading it claims to judge. Measuring either is free.
    Spending them is the operation that gets gated.

57. **`SquareDesignKit`** adds the fifty-seventh scenario, and it is the call
    scenario 56 declines. `PanelDesignKit` prices the attainable agreement range
    exactly at every category count and then stops: above two categories
    `admits(count:)` returns `nil` and `BinaryPanelBuilder` throws
    `constructionRequiresBinary`, on the grounds that the general case is a
    transportation problem with a forbidden diagonal and a prescribed trace. It
    is. It also has a closed form, and these judges cast **three-way** verdicts,
    so the panel that actually needs repairing here is one the sibling cannot
    build.

    Fixing the trace at `t` means choosing a diagonal that sums to `t` and
    leaving a transportation problem on `n - t` items. A row may send to every
    column but its own, and any two rows between them may send anywhere, so the
    singletons are the only subsets Hall's condition binds on — the remainder is
    feasible exactly when `(a_k - d_k) + (b_k - d_k) <= n - t`. Solving that for
    `d_k` gives a per-category floor, and a trace is attainable exactly when
    `sum_k floor_k(t) <= t <= sum_k min(a_k, b_k)`. Each floor climbs at half the
    target's rate and there are `k` of them, which is why the sum can overtake
    `t` and fall back: **that is a hole, and it is the thing this demo could not
    previously ask about.**

    On this panel the answer is not marginal. `answerability / independence`
    ranges over `24...72` and reaches **25 of the 49** integers in it; the 24 it
    misses are every odd number, because one of the three categories is unused
    and a panel with two live categories moves in steps of two. Part B puts the
    two calls side by side on the same margins: `PanelDesignKit.admits(count:
    71)` returns `nil`, `SquareDesignKit.admits(trace: 71)` returns `false`, and
    the refusal names the neighbours `70 / 72` rather than rounding onto one of
    them silently.

    Part C then does what scenario 56 could only do in binary. Same two judges,
    the same three-way verdict rates, rebuilt at the floor, the observed count
    and the ceiling: `kappa` moves `-0.5000`, `0.0000`, `0.5000` and the deviate
    `-5.627`, `0.000`, `5.627`. **Nothing changed but which item each verdict
    landed on.** Part D checks the identical-margins theorem on the one pair of
    this panel that has identical margins — `answerability` against
    `morphology`, which agreed on all **96** items because it is one judge
    counted twice. At `t = n - 1` every per-category floor reads `a_k`, so their
    sum is `n`, which is never at most `n - 1`: a pair with the same rates can
    agree on everything, and cannot agree on all but one.
