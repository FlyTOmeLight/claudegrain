import XCTest
@testable import ClaudegrainCore

/// V3-T12 / ADR-0016 — hourly_buckets table + 7-day EWMA decay.
final class HourlyBucketsTests: XCTestCase {
    private var dbURL: URL!

    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-hourly-\(UUID()).db")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    func testTableExistsAfterMigration() async throws {
        let db = try EventsDatabase(url: dbURL)
        let buckets = try await db.hourlyBuckets()
        XCTAssertEqual(buckets.count, 168, "7 weekdays × 24 hours = 168 rows zero-filled")
        XCTAssertTrue(buckets.allSatisfy { $0.costUSD == 0 && $0.sampleCount == 0 })
    }

    func testInsertPopulatesMatchingBucket() async throws {
        let db = try EventsDatabase(url: dbURL)
        let ts = isoDate("2026-05-10T14:30:00Z")! // Sun 14:30 UTC
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: ts)
        let hour = cal.component(.hour, from: ts)

        try await db.insertEvents(
            [makeEvent(ts: ts, inputTokens: 1_000)],
            from: "/tmp/h1.jsonl",
            startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )

        let bucket = try await db.hourlyBucket(weekday: weekday, hour: hour)
        XCTAssertEqual(bucket.sampleCount, 1.0, accuracy: 1e-6)
        XCTAssertEqual(bucket.tokens, 1_000)
        XCTAssertGreaterThan(bucket.costUSD, 0, "haiku cost > 0")
    }

    func testDecayHalvesAfterSevenDays() async throws {
        let db = try EventsDatabase(url: dbURL)
        let t0 = isoDate("2026-05-10T14:30:00Z")!
        let t1 = t0.addingTimeInterval(7 * 86400) // exactly 7 days later

        try await db.insertEvents(
            [makeEvent(ts: t0, inputTokens: 1_000)],
            from: "/tmp/d.jsonl", startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        try await db.insertEvents(
            [makeEvent(ts: t1, inputTokens: 1_000)],
            from: "/tmp/d.jsonl", startingAt: 1,
            cursor: .init(offset: 1, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: t0)
        let hour = cal.component(.hour, from: t0)
        let bucket = try await db.hourlyBucket(weekday: weekday, hour: hour)
        // Old sample count decayed to 0.5, plus new 1.0 → 1.5
        XCTAssertEqual(bucket.sampleCount, 1.5, accuracy: 0.01,
                      "7-day half-life: old 1.0 → 0.5, plus new 1.0 = 1.5")
    }

    func testSameHourMultipleEventsAccumulate() async throws {
        let db = try EventsDatabase(url: dbURL)
        let ts = isoDate("2026-05-10T14:30:00Z")!
        try await db.insertEvents(
            [
                makeEvent(ts: ts, sessionId: "a", inputTokens: 100),
                makeEvent(ts: ts.addingTimeInterval(60), sessionId: "b", inputTokens: 100),
                makeEvent(ts: ts.addingTimeInterval(120), sessionId: "c", inputTokens: 100),
            ],
            from: "/tmp/m.jsonl", startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: ts)
        let hour = cal.component(.hour, from: ts)
        let bucket = try await db.hourlyBucket(weekday: weekday, hour: hour)
        XCTAssertEqual(bucket.sampleCount, 3.0, accuracy: 0.01,
                      "no decay over seconds; 3 events = 3 samples")
        XCTAssertEqual(bucket.tokens, 300)
    }

    func testDifferentHoursDoNotCollide() async throws {
        let db = try EventsDatabase(url: dbURL)
        let ts1 = isoDate("2026-05-10T09:30:00Z")! // 9 UTC
        let ts2 = isoDate("2026-05-10T18:30:00Z")! // 18 UTC

        try await db.insertEvents(
            [makeEvent(ts: ts1, sessionId: "a", inputTokens: 100),
             makeEvent(ts: ts2, sessionId: "b", inputTokens: 100)],
            from: "/tmp/x.jsonl", startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        let cal = Calendar.current
        let wd1 = cal.component(.weekday, from: ts1)
        let h1  = cal.component(.hour,    from: ts1)
        let wd2 = cal.component(.weekday, from: ts2)
        let h2  = cal.component(.hour,    from: ts2)
        // The two timestamps are 9 hours apart UTC; in non-UTC locales they may
        // straddle midnight and land in different weekday rows. Read each by its
        // own (weekday, hour) coordinate.
        let b1 = try await db.hourlyBucket(weekday: wd1, hour: h1).sampleCount
        let b2 = try await db.hourlyBucket(weekday: wd2, hour: h2).sampleCount
        XCTAssertEqual(b1, 1.0, accuracy: 0.01)
        XCTAssertEqual(b2, 1.0, accuracy: 0.01)
        XCTAssertNotEqual((wd1, h1).0 * 24 + (wd1, h1).1,
                          (wd2, h2).0 * 24 + (wd2, h2).1,
                          "different hours/weekdays must occupy distinct buckets")
    }

    func testIsTrustedFloorAtSampleCountOne() async throws {
        let db = try EventsDatabase(url: dbURL)
        let ts = isoDate("2026-05-10T14:30:00Z")!
        try await db.insertEvents(
            [makeEvent(ts: ts, inputTokens: 100)],
            from: "/tmp/t.jsonl", startingAt: 0,
            cursor: .init(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: ts)
        let hour = cal.component(.hour, from: ts)
        let bucket = try await db.hourlyBucket(weekday: weekday, hour: hour)
        XCTAssertTrue(bucket.isTrusted, "1.0 sample → trusted")

        let untrusted = try await db.hourlyBucket(weekday: weekday, hour: (hour + 1) % 24)
        XCTAssertFalse(untrusted.isTrusted, "0.0 sample → untrusted")
    }

    // MARK: - Helpers

    private func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    private func makeEvent(
        ts: Date,
        sessionId: String = "s",
        inputTokens: Int = 0
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            sessionId: sessionId,
            cwd: "/repo",
            gitBranch: nil,
            model: "claude-haiku-4-5",
            tools: [],
            inputTokens: inputTokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
    }
}
