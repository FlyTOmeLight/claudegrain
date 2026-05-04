import XCTest
@testable import ClaudegrainCore

final class LimitEstimatorTests: XCTestCase {
    private var dbURL: URL!

    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-est-\(UUID()).db")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    // MARK: - Pure helpers

    func testP90SingleValueReturnsItself() {
        XCTAssertEqual(LimitEstimator.p90([100_000]), 100_000)
    }

    func testP90EmptyReturnsNil() {
        XCTAssertNil(LimitEstimator.p90([]))
    }

    func testP90LinearInterpolation() {
        // 10 values, rank = 0.9 * 9 = 8.1 → between sorted[8]=90 and sorted[9]=100 → 91
        let values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        XCTAssertEqual(LimitEstimator.p90(values), 91)
    }

    func testBuildBlocksGapTriggersNewBlock() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [(ts: Date, tokens: Int)] = [
            (t0, 100),
            (t0.addingTimeInterval(60), 200),                    // same block
            (t0.addingTimeInterval(6 * 3600), 300),              // >5h gap → new block
            (t0.addingTimeInterval(6 * 3600 + 120), 400),        // same as block 2
        ]
        let blocks = LimitEstimator.buildBlocks(rows: rows, blockDuration: 5 * 3600, now: Date())
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].totalTokens, 300)
        XCTAssertEqual(blocks[1].totalTokens, 700)
    }

    func testBuildBlocksRollOverWhenPastEnd() {
        // Continuous traffic spanning >5h: ts past first block end forces new block.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [(ts: Date, tokens: Int)] = [
            (t0, 100),
            (t0.addingTimeInterval(2 * 3600), 200),              // within block 1
            (t0.addingTimeInterval(5 * 3600 + 60), 300),         // past block 1 end
        ]
        let blocks = LimitEstimator.buildBlocks(rows: rows, blockDuration: 5 * 3600, now: Date())
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].totalTokens, 300)
        XCTAssertEqual(blocks[1].totalTokens, 300)
    }

    // MARK: - Snapshot integration

    func testEmptyHistoryReturnsZeroFraction() async throws {
        let db = try EventsDatabase(url: dbURL)
        let est = LimitEstimator(db: db)
        let now = Date()
        let snap = try await est.estimateSessionBlock(now: now)
        XCTAssertEqual(snap.usedFraction, 0)
        XCTAssertEqual(snap.totalTokens, 0)
        XCTAssertEqual(snap.resetsAt.timeIntervalSince(snap.startedAt), 5 * 3600, accuracy: 1)
    }

    func testSingleBlockUsesItselfAsLimit() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        // Single in-progress block: 1000 tokens, no history.
        try await db.insertEvents(
            [event(now.addingTimeInterval(-60), tokens: 1000)],
            from: "/tmp/a.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 1)
        )

        let snap = try await LimitEstimator(db: db).estimateSessionBlock(now: now)
        XCTAssertEqual(snap.totalTokens, 1000)
        XCTAssertEqual(snap.usedFraction, 1.0, accuracy: 0.001)
    }

    func testCurrentBlockFractionAgainstP90History() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()

        // 5 historical blocks at 100/200/300/400/500 tokens, each 1 day apart.
        // P90 of [100,200,300,400,500] with rank 0.9*4=3.6 → between 400 and 500 → 460.
        var events: [UsageEvent] = []
        for (i, tok) in [100, 200, 300, 400, 500].enumerated() {
            let day = now.addingTimeInterval(-Double(5 - i) * 86400)
            events.append(event(day, tokens: tok))
        }
        // Current block: 230 tokens just now.
        events.append(event(now.addingTimeInterval(-60), tokens: 230))

        try await db.insertEvents(
            events,
            from: "/tmp/h.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 2, deviceId: 1, sizeAtLastRead: 1)
        )

        let snap = try await LimitEstimator(db: db).estimateSessionBlock(now: now)
        XCTAssertEqual(snap.totalTokens, 230)
        XCTAssertEqual(snap.usedFraction, 230.0 / 460.0, accuracy: 0.01)
    }

    func testWeeklyEstimatorReturnsBoundedFraction() async throws {
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        // Spread events across 14 days.
        var events: [UsageEvent] = []
        for d in 0..<14 {
            events.append(event(now.addingTimeInterval(-Double(d) * 86400), tokens: 1000))
        }
        try await db.insertEvents(
            events,
            from: "/tmp/w.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 3, deviceId: 1, sizeAtLastRead: 1)
        )

        let snap = try await LimitEstimator(db: db).estimateWeekly(now: now)
        XCTAssertGreaterThanOrEqual(snap.usedFraction, 0)
        XCTAssertLessThanOrEqual(snap.usedFraction, 1.5)
        XCTAssertEqual(snap.resetsAt.timeIntervalSince(now), 7 * 86400, accuracy: 1)
    }

    // MARK: - Helper

    private func event(_ ts: Date, tokens: Int) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            sessionId: UUID().uuidString,
            cwd: "/tmp/repo",
            gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: ["Bash"],
            inputTokens: tokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
    }
}
