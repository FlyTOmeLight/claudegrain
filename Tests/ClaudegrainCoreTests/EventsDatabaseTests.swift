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

    func testCostPerModelGroupsByFamily() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let opus = makeEvent(model: "claude-opus-4-7", inputTokens: 1_000_000, ts: now)
        let sonnet1 = makeEvent(model: "claude-sonnet-4-6", inputTokens: 1_000_000, ts: now, sessionId: "s1")
        let sonnet2 = makeEvent(model: "claude-sonnet-4-6", inputTokens: 500_000, ts: now, sessionId: "s2")
        let expectedOpus = CostCalculator.cost(for: opus)
        let expectedSonnet = CostCalculator.cost(for: sonnet1) + CostCalculator.cost(for: sonnet2)

        try await db.insertEvents(
            [opus, sonnet1, sonnet2],
            from: "/tmp/cpm-family.jsonl",
            startingAt: 0,
            cursor: .init(offset: 3, inode: 1, deviceId: 1, sizeAtLastRead: 3)
        )

        let map = try await db.costPerModel(
            since: now.addingTimeInterval(-60),
            until: now.addingTimeInterval(60)
        )

        XCTAssertEqual(map[.opus] ?? 0, expectedOpus, accuracy: 0.0001)
        XCTAssertEqual(map[.sonnet] ?? 0, expectedSonnet, accuracy: 0.0001)
        XCTAssertNil(map[.haiku])
    }

    func testTokensPerModelSumsAllChannels() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let event = makeEvent(
            model: "claude-opus-4-7",
            inputTokens: 100,
            outputTokens: 200,
            cacheCreationTokens: 1000,
            cacheReadTokens: 5000,
            ts: now
        )
        try await db.insertEvents(
            [event],
            from: "/tmp/tpm.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 1)
        )

        let map = try await db.tokensPerModel(
            since: now.addingTimeInterval(-60),
            until: now.addingTimeInterval(60)
        )

        let opus = try XCTUnwrap(map[.opus])
        XCTAssertEqual(opus.input, 100)
        XCTAssertEqual(opus.output, 200)
        XCTAssertEqual(opus.cacheCreation, 1000)
        XCTAssertEqual(opus.cacheRead, 5000)
        XCTAssertEqual(opus.total, 6300)
    }

    func testCostPerModelHonorsTimeWindow() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let stale = makeEvent(model: "claude-opus-4-7", inputTokens: 9_000_000, ts: yesterday, sessionId: "stale")
        let fresh = makeEvent(model: "claude-opus-4-7", inputTokens: 1_000_000, ts: now, sessionId: "fresh")
        let expectedFresh = CostCalculator.cost(for: fresh)

        try await db.insertEvents(
            [stale, fresh],
            from: "/tmp/cpm-window.jsonl",
            startingAt: 0,
            cursor: .init(offset: 2, inode: 2, deviceId: 1, sizeAtLastRead: 2)
        )

        let map = try await db.costPerModel(
            since: now.addingTimeInterval(-3600),
            until: now.addingTimeInterval(60)
        )

        XCTAssertEqual(map[.opus] ?? 0, expectedFresh, accuracy: 0.0001)
    }

    /// Same logical assistant turn replayed in two distinct jsonl files
    /// (parent + sidechain). With a real `dedup_key` the second one is skipped.
    func testDedupAcrossSourceFiles() async throws {
        let db = try EventsDatabase(url: dbURL)
        let event = UsageEvent(
            timestamp: Date(), sessionId: "s",
            cwd: "/x", gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: ["Bash"],
            inputTokens: 100, outputTokens: 200, cacheCreationTokens: 0, cacheReadTokens: 0,
            messageId: "msg_abc", requestId: "req_123"
        )
        let cursorA = JSONLReader.Cursor(offset: 50, inode: 1, deviceId: 1, sizeAtLastRead: 50)
        let cursorB = JSONLReader.Cursor(offset: 80, inode: 2, deviceId: 1, sizeAtLastRead: 80)
        try await db.insertEvents([event], from: "/tmp/parent.jsonl", startingAt: 0, cursor: cursorA)
        try await db.insertEvents([event], from: "/tmp/sidechain.jsonl", startingAt: 0, cursor: cursorB)

        let totals = try await db.dailyTotals(on: Date())
        XCTAssertEqual(totals.totalTokens, 300, "duplicate dedup_key across files must be ignored")
    }

    func testCostPerBucketReturnsContiguousFiveMinBuckets() async throws {
        let db = try EventsDatabase(url: dbURL)
        let anchor = Date(timeIntervalSince1970: 1_777_000_000)
        // 0:00–0:05 → cost 0.10, 0:05–0:10 → 0, 0:10–0:15 → cost 0.30
        let events = [
            makeEvent(model: "claude-opus-4-7", inputTokens: 100,
                      ts: anchor.addingTimeInterval(60)),                                 // bucket 0
            makeEvent(model: "claude-opus-4-7", inputTokens: 300,
                      ts: anchor.addingTimeInterval(11 * 60)),                            // bucket 2
        ]
        try await db.insertEvents(
            events,
            from: "/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 1)
        )

        let buckets = try await db.costPerBucket(
            start: anchor,
            span: 15 * 60,
            bucketSize: 5 * 60
        )

        XCTAssertEqual(buckets.count, 3)
        XCTAssertGreaterThan(buckets[0].costUSD, 0)
        XCTAssertEqual(buckets[1].costUSD, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(buckets[2].costUSD, 0)
        XCTAssertGreaterThan(buckets[2].costUSD, buckets[0].costUSD)   // 300 input > 100 input
        XCTAssertEqual(buckets[0].start, anchor)
        XCTAssertEqual(buckets[2].end,   anchor.addingTimeInterval(15 * 60))
    }

    func testCostInWindowSumsCostsInRange() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            makeEvent(model: "claude-opus-4-7", inputTokens: 1_000_000, ts: now.addingTimeInterval(-100), sessionId: "before"),
            makeEvent(model: "claude-opus-4-7", inputTokens: 2_000_000, ts: now,                          sessionId: "middle"),
            makeEvent(model: "claude-opus-4-7", inputTokens: 3_000_000, ts: now.addingTimeInterval(100),  sessionId: "after"),
        ]
        try await db.insertEvents(
            events,
            from: "/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 3, inode: 1, deviceId: 1, sizeAtLastRead: 3)
        )

        let total = try await db.costInWindow(
            start: now.addingTimeInterval(-50),
            end:   now.addingTimeInterval(50)
        )

        // Only the middle event (at `now`) is in window.
        let middleCost = CostCalculator.cost(for: events[1])
        XCTAssertEqual(total, middleCost, accuracy: 0.0001)
    }

    func testCacheHitRateInWindow() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let event = makeEvent(
            model: "claude-opus-4-7",
            inputTokens: 100,
            outputTokens: 0,
            cacheCreationTokens: 50,
            cacheReadTokens: 350,
            ts: now
        )
        try await db.insertEvents(
            [event],
            from: "/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 1)
        )

        let rate = try await db.cacheHitRateInWindow(
            start: now.addingTimeInterval(-60),
            end:   now.addingTimeInterval(60)
        )

        // cache_read / (input + cache_create + cache_read) = 350 / 500 = 0.70
        XCTAssertEqual(rate, 0.70, accuracy: 0.0001)
    }

    // MARK: - v4 tools_json (ADR-0015)

    func testToolsJsonRoundTrip() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            makeEvent(model: "claude-sonnet-4-6", inputTokens: 10, ts: now,
                     sessionId: "s1", tools: ["Read", "Read", "Bash"]),
            makeEvent(model: "claude-sonnet-4-6", inputTokens: 10, ts: now,
                     sessionId: "s2", tools: []),
        ]
        try await db.insertEvents(
            events,
            from: "/tmp/tools.jsonl",
            startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        let row0 = try await db.toolsRaw(sourceFile: "/tmp/tools.jsonl", offset: 0)
        XCTAssertEqual(row0, ["Read", "Read", "Bash"])
        let row1 = try await db.toolsRaw(sourceFile: "/tmp/tools.jsonl", offset: 1)
        XCTAssertNil(row1, "empty tools must persist as NULL, not '[]'")
    }

    func testToolsJsonPreservesOrderAndDuplicates() async throws {
        let db = try EventsDatabase(url: dbURL)
        try await db.insertEvents(
            [makeEvent(model: "m", ts: Date(), tools: ["a", "b", "a", "c", "a"])],
            from: "/tmp/dup.jsonl",
            startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        let raw = try await db.toolsRaw(sourceFile: "/tmp/dup.jsonl", offset: 0)
        XCTAssertEqual(raw, ["a", "b", "a", "c", "a"],
                      "tools_json must store raw array; share dedup happens at read time")
    }

    private func makeEvent(
        model: String,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        ts: Date,
        sessionId: String = "s",
        cwd: String? = "/repo",
        tools: [String] = []
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            sessionId: sessionId,
            cwd: cwd,
            gitBranch: nil,
            model: model,
            tools: tools,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}
