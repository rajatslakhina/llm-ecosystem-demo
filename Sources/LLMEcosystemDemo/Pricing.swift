import Foundation
import ProviderGatewayKit
import TokenMeterKit

/// The pricing table, lifted out of `EcosystemDemo` so that type stays inside SwiftLint's
/// 250-line body limit as scenarios keep being added. It crossed the limit on the
/// twenty-seventh; extracting the table is the fix, not raising the limit.
extension EcosystemDemo {
    /// Registers illustrative rates for every routed provider this demo uses.
    ///
    /// TokenMeterKit ships a small default catalog keyed on real model names like `gpt-4o`, but a
    /// host app routes against whatever identifiers its own providers use. Registering your own
    /// rates against those identifiers is the expected integration pattern rather than a
    /// workaround — and skipping it is why an unregistered provider silently reports $0.
    static func buildMeter() async -> TokenMeter {
        let registry = PricingRegistry()
        for (identifier, pricing) in rates {
            await registry.register(pricing, for: identifier.rawValue)
        }
        return TokenMeter(registry: registry)
    }

    private static var rates: [(ProviderIdentifier, ModelPricing)] {
        [
            (.onDevice, ModelPricing(inputPerMillion: 0, outputPerMillion: 0)),
            (.cloud, ModelPricing(inputPerMillion: 3, outputPerMillion: 15)),
            (.selfHosted, ModelPricing(inputPerMillion: 1, outputPerMillion: 4)),
            (.promptTemplateHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.retryHost, ModelPricing(inputPerMillion: 1.5, outputPerMillion: 6)),
            (.compactionHost, ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10)),
            (.memoryHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.routerHost, ModelPricing(inputPerMillion: 1.8, outputPerMillion: 7)),
            (.repairHost, ModelPricing(inputPerMillion: 2.2, outputPerMillion: 9)),
            (.streamHost, ModelPricing(inputPerMillion: 1.6, outputPerMillion: 6.5)),
            (.batchHost, ModelPricing(inputPerMillion: 2.6, outputPerMillion: 10.5)),
            (.realtimeHost, ModelPricing(inputPerMillion: 1.9, outputPerMillion: 7.5)),
            (.idempotencyHost, ModelPricing(inputPerMillion: 2.4, outputPerMillion: 9.5)),
            (.schemaHost, ModelPricing(inputPerMillion: 2.1, outputPerMillion: 8.5)),
            (.authorityHost, ModelPricing(inputPerMillion: 2.3, outputPerMillion: 9.2)),
            (.groundingHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.quotaHost, ModelPricing(inputPerMillion: 2.4, outputPerMillion: 9.6)),
            (.estimatorHost, ModelPricing(inputPerMillion: 2.8, outputPerMillion: 11.2)),
            (.profilerHost, ModelPricing(inputPerMillion: 2.8, outputPerMillion: 11.2)),
            (.consistencyHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.conflictHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.segmenterHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.citationHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.decontextHost, ModelPricing(inputPerMillion: 2, outputPerMillion: 8)),
            (.answerabilityHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.morphologyHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.sensitivityHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.independenceHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.temporalHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.abstentionHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.explorationHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.labelReturnHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.delaySignalHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.delayShapeHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.delayCurveHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.curveDivergenceHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.labelClockHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.selectionTrustHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12)),
            (.argumentAttributionHost, ModelPricing(inputPerMillion: 3, outputPerMillion: 12))
        ]
    }
}
