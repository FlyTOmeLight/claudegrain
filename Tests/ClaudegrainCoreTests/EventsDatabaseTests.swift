import XCTest
@testable import ClaudegrainCore

final class EventsDatabaseTests: XCTestCase {
    private var dbURL: URL!

    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-test-\(UUID()).db")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    func testInsertsAndAggregates() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            UsageEvent(
                timestamp: now, sessionId: "s1",
                cwd: "/Users/me/projects/repo-a", gitBranch: "main",
                model: "claude-sonnet-4-6",
                tools: ["Bash"],
                inputTokens: 100, outputTokens: 200, cacheCreationTokens: 0, cacheReadTokens: 50_000
            ),
            UsageEvent(
                timestamp: now, sessionId: "s1",
                cwd: "/Users/me/projects/repo-a", gitBranch: "main",
                model: "claude-opus-4-7",
                tools: ["mcp__exa__search"],
                inputTokens: 0, outputTokens: 100, cacheCreationTokens: 10_000, cacheReadTokens: 0
            ),
            UsageEvent(
                timestamp: now, sessionId: "s2",
                cwd: "/Users/me/projects/repo-b", gitBranch: nil,
                model: "claude-haiku-4-5",
                tools: ["Edit"],
                inputTokens: 500, outputTokens: 1000, cacheCreationTokens: 0, cacheReadTokens: 0
            ),
        ]
        try await db.insertEvents(
            events,
            from: "/tmp/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 100, inode: 42, deviceId: 1, sizeAtLastRead: 100)
        )

        let totals = try await db.dailyTotals(on: now)
        XCTAssertGreaterThan(totals.costUSD, 0)
        XCTAssertEqual(totals.totalTokens, 100 + 200 + 50_000 + 100 + 10_000 + 500 + 1000)
        XCTAssertEqual(totals.byModel.count, 3)

        let repos = try await db.topRepos(on: now)
        XCTAssertEqual(repos.count, 2)
        XCTAssertEqual(repos[0].repo, "projects/repo-a")

        let tools = try await db.topTools(on: now)
        XCTAssertEqual(tools.map(\.toolName).sorted(), ["Bash", "Edit", "mcp__exa__search"])

        let mcpHit = tools.first(where: { $0.toolName.hasPrefix("mcp__") })
        XCTAssertEqual(mcpHit?.mcpServer, "exa")

        let cache = try await db.cacheHitRate(on: now)
        // cache_read=50_000, denom = in(100+0+500) + cache_create(10_000) + cache_read(50_000) = 60_600
        XCTAssertEqual(cache, 50_000.0 / 60_600.0, accuracy: 0.001)
    }

    func testCursorRoundTrip() async throws {
        let db = try EventsDatabase(url: dbURL)
        let cursor = JSONLReader.Cursor(offset: 12345, inode: 7, deviceId: 2, sizeAtLastRead: 12345)
        try await db.insertEvents(
            [],
            from: "/tmp/x.jsonl",
            startingAt: 0,
            cursor: cursor
        )
        let read = try await db.cursor(for: "/tmp/x.jsonl")
        XCTAssertEqual(read, cursor)
    }

    func testIdempotentInsertsBySource() async throws {
        let db = try EventsDatabase(url: dbURL)
        let event = UsageEvent(
            timestamp: Date(), sessionId: "s",
            cwd: "/x", gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: ["Bash"],
            inputTokens: 10, outputTokens: 20, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        let cursor = JSONLReader.Cursor(offset: 50, inode: 1, deviceId: 1, sizeAtLastRead: 50)
        try await db.insertEvents([event], from: "/tmp/dup.jsonl", startingAt: 0, cursor: cursor)
        try await db.insertEvents([event], from: "/tmp/dup.jsonl", startingAt: 0, cursor: cursor)

        let totals = try await db.dailyTotals(on: Date())
        XCTAssertEqual(totals.totalTokens, 30, "second insert at same (file, offset) should be ignored")
    }
}
