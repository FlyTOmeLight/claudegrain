import XCTest
@testable import ClaudegrainCore

final class EventsExporterTests: XCTestCase {
    func testEnumRawValues() {
        XCTAssertEqual(ExportDimension.perRepoDaily.rawValue,  "per-repo daily")
        XCTAssertEqual(ExportDimension.perToolDaily.rawValue,  "per-tool daily")
        XCTAssertEqual(ExportDimension.perModelDaily.rawValue, "per-model daily")
        XCTAssertEqual(ExportDimension.rawEvents.rawValue,     "raw events")
        XCTAssertEqual(ExportFormat.csv.rawValue,  "csv")
        XCTAssertEqual(ExportFormat.json.rawValue, "json")
    }

    func testExporterInit() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        _ = EventsExporter(db: db)
    }

    func testPerRepoDailyCSVHasDisclaimerHeaderAndRows() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            UsageEvent(timestamp: now,                          sessionId: "s1", cwd: "/a",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 1_000_000, outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now.addingTimeInterval(60),   sessionId: "s2", cwd: "/a",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 500_000,   outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now,                          sessionId: "s3", cwd: "/b",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 200_000,   outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
        ]
        try await db.insertEvents(events, from: "/test.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).csv")
        let range = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600))

        try await exporter.export(range: range, dimension: .perRepoDaily, format: .csv, to: outURL)

        let csv = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("# claudegrain export"),                "missing disclaimer line")
        XCTAssertTrue(csv.contains("Not the Anthropic billing source"),    "missing accuracy disclaimer")
        XCTAssertTrue(csv.contains("Dimension: per-repo daily"),           "missing dimension annotation")
        XCTAssertTrue(csv.contains("date,repo,events,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd"),
                      "missing column header")
        XCTAssertTrue(csv.contains(",/a,2,1500000,"))
        XCTAssertTrue(csv.contains(",/b,1,200000,"))
    }
}
