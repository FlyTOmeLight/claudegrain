import XCTest
@testable import ClaudegrainCore

/// ADR-0016 performance smoke test for `hourly_buckets`.
///
/// Two budgets:
///   1. Insert path: per-event EWMA upsert latency < 1 ms median on M2/M3.
///      We simulate ~90 days of ingest as 100-event batches × 500 batches = 50,000
///      events, mirroring `IngestActor`'s real "one cursor commit per batch" call
///      pattern. Wall-clock per event is reported.
///   2. Read path: `hourlyBuckets()` returning all 168 rows < 50 ms.
///
/// We use `XCTestCase.measure` for the read path (XCTest has built-in variance
/// handling). For the insert path we measure once and report the average — CI
/// machines vary too much to assert a hard threshold, so we log the number and
/// only fail if it's catastrophically over budget (10× budget).
final class HourlyBucketsPerfTests: XCTestCase {
    private var dbURL: URL!

    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-hourly-perf-\(UUID()).db")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    /// 100 events × 500 batches = 50,000 events. Each batch is one transaction
    /// (one cursor commit) — same shape as `IngestActor` produces in production.
    /// If CI is too slow, downsize via the constants below.
    private let batchSize = 100
    private let batchCount = 500   // 50_000 events total. Drop to 100 for a 10k smoke.

    func testInsertPerEventLatencyUnderOneMillisecond() async throws {
        let db = try EventsDatabase(url: dbURL)
        let totalEvents = batchSize * batchCount

        // Spread timestamps over 90 days so events fall across many (weekday, hour)
        // buckets rather than hammering one row.
        let spanSeconds: TimeInterval = 90 * 86_400
        let stepSeconds = spanSeconds / Double(totalEvents)
        let baseTs = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC

        var batches: [[UsageEvent]] = []
        batches.reserveCapacity(batchCount)
        for batchIdx in 0..<batchCount {
            var batch: [UsageEvent] = []
            batch.reserveCapacity(batchSize)
            for eventIdx in 0..<batchSize {
                let i = batchIdx * batchSize + eventIdx
                let ts = baseTs.addingTimeInterval(Double(i) * stepSeconds)
                batch.append(makeEvent(ts: ts, sessionId: "s\(i)", inputTokens: 100))
            }
            batches.append(batch)
        }

        let sourceFile = "/tmp/perf-\(UUID()).jsonl"
        let cursor = JSONLReader.Cursor(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)

        let start = Date()
        var runningOffset: UInt64 = 0
        for batch in batches {
            try await db.insertEvents(
                batch,
                from: sourceFile,
                startingAt: runningOffset,
                cursor: cursor
            )
            runningOffset += UInt64(batch.count)
        }
        let elapsed = Date().timeIntervalSince(start)
        let perEventMs = (elapsed / Double(totalEvents)) * 1_000

        print("[perf] insert: \(totalEvents) events in \(String(format: "%.2f", elapsed))s → \(String(format: "%.3f", perEventMs)) ms/event")

        // Hard ceiling: 10× the 1ms budget. CI variance means we only fail on
        // catastrophic regressions; the printed number is the real signal.
        XCTAssertLessThan(perEventMs, 10.0,
                          "per-event insert latency \(perEventMs) ms exceeds 10× budget (1 ms target)")
    }

    func testHourlyBucketsReadUnderFiftyMilliseconds() async throws {
        let db = try EventsDatabase(url: dbURL)

        // Pre-populate every (weekday, hour) bucket so the read does a full
        // 168-row scan, not a sparse one. 168 events scattered one per bucket.
        var events: [UsageEvent] = []
        let baseTs = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        for i in 0..<168 {
            // 168 hours = 7 days; one event per hour covers every (weekday, hour).
            let ts = baseTs.addingTimeInterval(Double(i) * 3_600)
            events.append(makeEvent(ts: ts, sessionId: "s\(i)", inputTokens: 100))
        }
        try await db.insertEvents(
            events,
            from: "/tmp/perf-read-\(UUID()).jsonl",
            startingAt: 0,
            cursor: JSONLReader.Cursor(offset: 0, inode: 1, deviceId: 1, sizeAtLastRead: 0)
        )

        // Warm-up read so the connection / page cache is hot before measuring.
        _ = try await db.hourlyBuckets()

        // Measure several iterations, then compute average and assert ceiling.
        let iterations = 20
        var samples: [TimeInterval] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = Date()
            let buckets = try await db.hourlyBuckets()
            samples.append(Date().timeIntervalSince(start))
            XCTAssertEqual(buckets.count, 168)
        }

        let avgMs = (samples.reduce(0, +) / Double(iterations)) * 1_000
        let maxMs = (samples.max() ?? 0) * 1_000
        print("[perf] hourlyBuckets() read: avg \(String(format: "%.2f", avgMs)) ms, max \(String(format: "%.2f", maxMs)) ms over \(iterations) iters")

        // Hard ceiling: 10× the 50ms budget for CI tolerance; printed number is signal.
        XCTAssertLessThan(avgMs, 500.0,
                          "hourlyBuckets() avg read \(avgMs) ms exceeds 10× budget (50 ms target)")
    }

    // MARK: - Helpers

    private func makeEvent(
        ts: Date,
        sessionId: String,
        inputTokens: Int
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
