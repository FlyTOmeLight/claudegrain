import XCTest
@testable import ClaudegrainCore

final class PriceTableLoaderTests: XCTestCase {
    override func tearDown() async throws {
        CostCalculator.resetPriceTable()
    }

    func testParsesAnthropicEntriesAndConvertsPerTokenToPerMTok() {
        let json = """
        {
          "sample_spec": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 0,
            "output_cost_per_token": 0
          },
          "claude-opus-4-20250514": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 0.000015,
            "output_cost_per_token": 0.000075,
            "cache_creation_input_token_cost": 0.00001875,
            "cache_read_input_token_cost": 0.0000015
          },
          "bedrock/claude-3-haiku": {
            "litellm_provider": "bedrock",
            "input_cost_per_token": 0.00000025,
            "output_cost_per_token": 0.00000125
          }
        }
        """.data(using: .utf8)!

        let table = PriceTableLoader.parse(json: json)
        XCTAssertEqual(table.count, 1, "should keep only direct anthropic entries with non-zero pricing")
        let opus = table["claude-opus-4-20250514"]
        XCTAssertNotNil(opus)
        XCTAssertEqual(opus?.inputPerMTok ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(opus?.outputPerMTok ?? 0, 75, accuracy: 0.001)
        XCTAssertEqual(opus?.cacheWritePerMTok ?? 0, 18.75, accuracy: 0.001)
        XCTAssertEqual(opus?.cacheReadPerMTok ?? 0, 1.5, accuracy: 0.001)
    }

    func testFillsMissingCacheFieldsWithAnthropicMultipliers() {
        let json = """
        {
          "claude-haiku-4-5-20251001": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 0.000001,
            "output_cost_per_token": 0.000005
          }
        }
        """.data(using: .utf8)!
        let table = PriceTableLoader.parse(json: json)
        let h = table["claude-haiku-4-5-20251001"]
        XCTAssertNotNil(h)
        XCTAssertEqual(h?.cacheWritePerMTok ?? 0, 1.25, accuracy: 0.001)
        XCTAssertEqual(h?.cacheReadPerMTok ?? 0, 0.10, accuracy: 0.001)
    }

    func testSetPriceTableOverlayPreservesBuiltinKeys() {
        let overlay: [String: ModelPricing] = [
            "claude-opus-4-20250514": ModelPricing(inputPerMTok: 12, outputPerMTok: 60, cacheWritePerMTok: 15, cacheReadPerMTok: 1.2)
        ]
        CostCalculator.setPriceTable(merging: overlay)
        defer { CostCalculator.resetPriceTable() }

        let table = CostCalculator.priceTable
        XCTAssertNotNil(table["claude-opus-4-20250514"])
        XCTAssertNotNil(table["claude-sonnet-4-6"], "builtin keys must survive overlay")
    }

    func testCostUsesOverlayWhenModelIdMatches() {
        CostCalculator.setPriceTable(merging: [
            "claude-opus-4-20250514": ModelPricing(inputPerMTok: 100, outputPerMTok: 100, cacheWritePerMTok: 100, cacheReadPerMTok: 100)
        ])
        defer { CostCalculator.resetPriceTable() }

        let event = UsageEvent(
            timestamp: Date(), sessionId: "s", cwd: nil, gitBranch: nil,
            model: "claude-opus-4-20250514",
            tools: [],
            inputTokens: 1_000_000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        XCTAssertEqual(CostCalculator.cost(for: event), 100, accuracy: 0.001)
    }
}
