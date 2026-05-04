import Foundation
import os

public struct ModelPricing: Sendable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheWritePerMTok: Double
    public let cacheReadPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double, cacheWritePerMTok: Double, cacheReadPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cacheWritePerMTok = cacheWritePerMTok
        self.cacheReadPerMTok = cacheReadPerMTok
    }
}

/// Computes per-event USD cost. Backed by a thread-safe price table that is
/// either the built-in default (used until first launch with network) or a
/// LiteLLM-sourced catalog populated by `PriceTableLoader`.
public enum CostCalculator {
    /// Built-in fallback. Used cold-start until `PriceTableLoader` lays down a
    /// fresh catalog, and as a last resort for unknown model ids.
    /// USD per 1M tokens.
    public static let defaultPriceTable: [String: ModelPricing] = [
        "claude-opus-4-7":   ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5),
        "claude-opus-4-5":   ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5),
        "claude-sonnet-4-6": ModelPricing(inputPerMTok: 3,  outputPerMTok: 15, cacheWritePerMTok: 3.75,  cacheReadPerMTok: 0.30),
        "claude-haiku-4-5":  ModelPricing(inputPerMTok: 1,  outputPerMTok: 5,  cacheWritePerMTok: 1.25,  cacheReadPerMTok: 0.10),
    ]

    private static let _table = OSAllocatedUnfairLock<[String: ModelPricing]>(initialState: defaultPriceTable)

    /// Current snapshot of the active price table (default ⊕ any loaded overlay).
    public static var priceTable: [String: ModelPricing] {
        _table.withLock { $0 }
    }

    /// Overlay `incoming` on top of defaults — caller wins for matching keys,
    /// builtins survive for keys the loader didn't know about.
    public static func setPriceTable(merging incoming: [String: ModelPricing]) {
        _table.withLock { current in
            var merged = defaultPriceTable
            for (k, v) in incoming { merged[k] = v }
            current = merged
        }
    }

    /// Reset to built-in defaults. Test hook; not normally called at runtime.
    public static func resetPriceTable() {
        _table.withLock { $0 = defaultPriceTable }
    }

    public static func cost(for event: UsageEvent) -> Double {
        let p = pricing(for: event.model)
        return Double(event.inputTokens) * p.inputPerMTok / 1_000_000
            + Double(event.outputTokens) * p.outputPerMTok / 1_000_000
            + Double(event.cacheCreationTokens) * p.cacheWritePerMTok / 1_000_000
            + Double(event.cacheReadTokens) * p.cacheReadPerMTok / 1_000_000
    }

    static func pricing(for model: String) -> ModelPricing {
        let table = priceTable
        if let exact = table[model] { return exact }
        // Family-substring fallback against built-in defaults — small, predictable.
        if model.contains("opus") { return defaultPriceTable["claude-opus-4-7"]! }
        if model.contains("sonnet") { return defaultPriceTable["claude-sonnet-4-6"]! }
        if model.contains("haiku") { return defaultPriceTable["claude-haiku-4-5"]! }
        return defaultPriceTable["claude-sonnet-4-6"]!
    }
}
