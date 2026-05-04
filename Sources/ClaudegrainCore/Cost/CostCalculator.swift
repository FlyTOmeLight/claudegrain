import Foundation

public struct ModelPricing: Sendable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheWritePerMTok: Double
    public let cacheReadPerMTok: Double
}

/// Source: anthropic.com/pricing snapshot. Update as Anthropic publishes new tiers.
/// Numbers in USD per 1M tokens.
public enum CostCalculator {
    public static let priceTable: [String: ModelPricing] = [
        "claude-opus-4-7": ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5),
        "claude-opus-4-5": ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5),
        "claude-sonnet-4-6": ModelPricing(inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30),
        "claude-haiku-4-5": ModelPricing(inputPerMTok: 1, outputPerMTok: 5, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.10),
    ]

    public static func cost(for event: UsageEvent) -> Double {
        let pricing = pricing(for: event.model)
        return Double(event.inputTokens) * pricing.inputPerMTok / 1_000_000
            + Double(event.outputTokens) * pricing.outputPerMTok / 1_000_000
            + Double(event.cacheCreationTokens) * pricing.cacheWritePerMTok / 1_000_000
            + Double(event.cacheReadTokens) * pricing.cacheReadPerMTok / 1_000_000
    }

    static func pricing(for model: String) -> ModelPricing {
        if let exact = priceTable[model] { return exact }
        // Fallback: family match.
        if model.contains("opus") { return priceTable["claude-opus-4-7"]! }
        if model.contains("sonnet") { return priceTable["claude-sonnet-4-6"]! }
        if model.contains("haiku") { return priceTable["claude-haiku-4-5"]! }
        return priceTable["claude-sonnet-4-6"]!
    }
}
