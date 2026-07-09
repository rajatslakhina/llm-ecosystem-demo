# LLM Ecosystem Demo

A single runnable demo that wires together all three packages in this
ecosystem — [`ProviderGatewayKit`](https://github.com/rajatslakhina/foundation-model-provider-gateway),
[`TokenMeterKit`](https://github.com/rajatslakhina/token-meter-kit), and
[`StructuredOutputKit`](https://github.com/rajatslakhina/structured-output-kit)
— against each other's real, tagged `1.0.0` releases. Where each package's
own demo shows that package in isolation, this one shows the seam between
them: a routed call that gets decoded into a typed value and metered for
cost, in one pipeline.

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

Each scenario uses a `ScriptedProvider` — a demo-only conformer to
`ProviderGatewayKit`'s real `LLMProvider` protocol that answers from a
fixed script instead of a live network or on-device runtime, exactly the
same pattern `ProviderGatewayKit` uses internally for its own
`SimulatedCloudProvider`. Everything *around* that one scripted seam —
routing, session turn-serialization, schema validation, extraction, the
retry loop, and cost accounting — is the real, compiled code from all
three tagged packages.

## Installation

This repository is a runnable demo, not a library — there's nothing to add
to your own `Package.swift`. To build it yourself:

```bash
git clone https://github.com/rajatslakhina/llm-ecosystem-demo.git
cd llm-ecosystem-demo
swift run LLMEcosystemDemo
```

Swift Package Manager resolves `ProviderGatewayKit`, `TokenMeterKit`, and
`StructuredOutputKit` straight from their `1.0.0` tags — no local checkouts
or path overrides needed.

## Sample output

![Demo output](Screenshots/demo.svg)

## Quality

- **Build:** `swift build` — clean, zero warnings, resolving all three
  dependencies from their real tagged releases.
- **Run:** `swift run LLMEcosystemDemo` — exercises the real, compiled code
  of all three packages together; the output above is a genuine capture,
  not a mock-up.
- **Lint:** a `.swiftlint.yml` matching the rest of the ecosystem is
  included; the `swiftlint` binary isn't installable in the sandbox this
  was built in (no apt/brew/mint package, and building it from source
  pulls a prebuilt binary artifact from a GitHub release, which that
  sandbox's network policy blocks). The source was hand-checked line by
  line against every rule the config enables instead.

This repository intentionally has no test target — it's an integration
demo, not a library with independently testable units. Correctness here
means "the three real packages compose and run," which the sample output
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
```

## License

MIT © 2026 Rajat S. Lakhina. See [LICENSE](LICENSE).
