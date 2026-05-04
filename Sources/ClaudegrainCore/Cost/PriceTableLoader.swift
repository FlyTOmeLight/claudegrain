import Foundation

/// Pulls Anthropic model pricing from LiteLLM's public price catalog and feeds
/// `CostCalculator`. Disk cache survives offline launches; remote fetch happens
/// in the background so first paint is never blocked on network.
///
/// LiteLLM source of truth — community-maintained, frequently updated:
/// https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
public actor PriceTableLoader {
    public static let shared = PriceTableLoader()

    private let cacheURL: URL
    private let session: URLSession
    private let remote: URL

    public init(
        cacheURL: URL? = nil,
        session: URLSession = .shared,
        remote: URL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    ) {
        self.cacheURL = cacheURL ?? EventsDatabase.defaultDirectory.appendingPathComponent("prices.json")
        self.session = session
        self.remote = remote
    }

    /// Synchronously apply any disk-cached table to `CostCalculator`. Cheap;
    /// safe to await before ingest bootstrap so cold-start uses the freshest
    /// table seen so far.
    public func applyDiskCache() {
        guard let parsed = loadFromDisk(), !parsed.isEmpty else { return }
        CostCalculator.setPriceTable(merging: parsed)
    }

    /// Fetch the remote LiteLLM catalog, persist to disk, and update
    /// `CostCalculator`. Silent on network/parse failure — built-in defaults
    /// (or last-good cache) remain in effect.
    public func refresh() async {
        do {
            try await FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let (data, response) = try await session.data(from: remote)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let parsed = Self.parse(json: data)
            guard !parsed.isEmpty else { return }
            try? data.write(to: cacheURL, options: .atomic)
            CostCalculator.setPriceTable(merging: parsed)
        } catch {
            // Keep current table; will retry on next launch / refresh.
        }
    }

    /// Convenience: disk first, then remote.
    public func bootstrap() async {
        applyDiskCache()
        await refresh()
    }

    private func loadFromDisk() -> [String: ModelPricing]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let parsed = Self.parse(json: data)
        return parsed.isEmpty ? nil : parsed
    }

    /// Parse LiteLLM's JSON catalog. Filters to `litellm_provider == "anthropic"`
    /// (the direct rows; not the `bedrock/`, `vertex_ai/` mirrors) and converts
    /// per-token prices to per-MTok USD.
    public static func parse(json: Data) -> [String: ModelPricing] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return [:]
        }
        var out: [String: ModelPricing] = [:]
        for (key, value) in root {
            guard let entry = value as? [String: Any] else { continue }
            guard (entry["litellm_provider"] as? String) == "anthropic" else { continue }

            let inPer = (entry["input_cost_per_token"] as? Double) ?? 0
            let outPer = (entry["output_cost_per_token"] as? Double) ?? 0
            guard inPer > 0 || outPer > 0 else { continue }

            // Cache fields are optional in LiteLLM. Fall back to Anthropic's
            // documented multipliers (5-min write = 1.25× input, read = 0.1× input).
            let cWritePer = (entry["cache_creation_input_token_cost"] as? Double) ?? (inPer * 1.25)
            let cReadPer = (entry["cache_read_input_token_cost"] as? Double) ?? (inPer * 0.1)

            out[key] = ModelPricing(
                inputPerMTok: inPer * 1_000_000,
                outputPerMTok: outPer * 1_000_000,
                cacheWritePerMTok: cWritePer * 1_000_000,
                cacheReadPerMTok: cReadPer * 1_000_000
            )
        }
        return out
    }
}
