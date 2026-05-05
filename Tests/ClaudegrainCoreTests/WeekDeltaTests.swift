import XCTest
@testable import ClaudegrainCore

final class WeekDeltaTests: XCTestCase {
    func testFirstWeekReturnsNilPctChange() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        // Event must fall in `[mondayUTC(now), now)` (half-open) — ts == now would be excluded.
        let event = makeEvent(model: "claude-opus-4-7", inputTokens: 1_000_000, ts: now.addingTimeInterval(-1))
        try await db.insertEvents(
            [event],
            from: "/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 1)
        )

        let delta = await WeekDelta.compute(db: db, now: now)

        XCTAssertGreaterThan(delta.thisWeekCost, 0)
        XCTAssertEqual(delta.lastWeekCost, 0.0, accuracy: 0.0001)
        XCTAssertNil(delta.pctChange)
    }

    func testNormalDelta() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        let monday = WeekDelta.mondayUTC(of: now)
        let lastMonday = monday.addingTimeInterval(-7 * 86_400)
        let lastEvent = makeEvent(
            model: "claude-opus-4-7",
            inputTokens: 1_000_000,
            ts: lastMonday.addingTimeInterval(3600),
            sessionId: "last"
        )
        let thisEvent = makeEvent(
            model: "claude-opus-4-7",
            inputTokens: 1_120_000, // 12% more input → 12% more cost (linear)
            ts: monday.addingTimeInterval(3600),
            sessionId: "this"
        )

        try await db.insertEvents(
            [lastEvent, thisEvent],
            from: "/test.jsonl",
            startingAt: 0,
            cursor: .init(offset: 2, inode: 1, deviceId: 1, sizeAtLastRead: 2)
        )

        let delta = await WeekDelta.compute(db: db, now: now)
        XCTAssertGreaterThan(delta.thisWeekCost, delta.lastWeekCost)
        XCTAssertEqual(delta.pctChange ?? 0, 0.12, accuracy: 0.01)
    }
}

private extension WeekDeltaTests {
    func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudegrain-test-\(UUID().uuidString).db")
    }

    func makeEvent(
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
