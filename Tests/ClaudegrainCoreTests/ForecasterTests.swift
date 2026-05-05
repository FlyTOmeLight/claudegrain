import XCTest
@testable import ClaudegrainCore

final class ForecasterTests: XCTestCase {
    func testEmptyBucketsReturnInsufficient() async {
        let f = Forecaster()
        let snap = SessionBlockSnapshot(
            startedAt: Date().addingTimeInterval(-1800),
            resetsAt:  Date().addingTimeInterval(16_200),
            usedFraction: 0.10,
            totalTokens: 1
        )
        let r = await f.forecastSessionBlock(block: snap, recent: [])
        XCTAssertFalse(r.willHit)
        XCTAssertNil(r.hitAt)
        XCTAssertEqual(r.basis,      .insufficient)
        XCTAssertEqual(r.confidence, .low)
    }

    func testLinearBasisFiresWhenPaceWillExceed() async {
        // 30 min elapsed, 10% used, remaining 4.5h.
        // Linear projection: 10% / 30min = 0.333%/min → 0.333 * 270min = 90% more
        // → total 100%. Should *just* hit at the reset boundary.
        // Two buckets only (sub-3) → forces .linear basis.
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt:    now.addingTimeInterval(-1800),
            resetsAt:     now.addingTimeInterval(16_200),
            usedFraction: 0.10,
            totalTokens:  1
        )
        let twoBuckets = [
            CostBucket(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300), costUSD: 1),
            CostBucket(start: now.addingTimeInterval(-300), end: now,                          costUSD: 1),
        ]
        let r = await f.forecastSessionBlock(block: snap, recent: twoBuckets)
        XCTAssertEqual(r.basis,      .linear)
        XCTAssertEqual(r.confidence, .low)
    }

    func testLinearBasisDoesNotFireWhenPaceSlow() async {
        let f = Forecaster()
        let now = Date()
        // 30 min elapsed, only 1% used → projects to ~10% by reset.
        let snap = SessionBlockSnapshot(
            startedAt:    now.addingTimeInterval(-1800),
            resetsAt:     now.addingTimeInterval(16_200),
            usedFraction: 0.01,
            totalTokens:  1
        )
        let r = await f.forecastSessionBlock(block: snap, recent: [
            CostBucket(start: now.addingTimeInterval(-300), end: now, costUSD: 0.01),
        ])
        XCTAssertEqual(r.basis,   .linear)
        XCTAssertFalse(r.willHit)
    }

    func testEwmaBasisAcceleratingPaceFires() async {
        // Buckets show accelerating cost: $0.05, $0.10, $0.20, $0.40 over 20 min.
        // EWMA(α=0.4) heavily weights the latest $0.40 bucket → high rate → will hit.
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt:    now.addingTimeInterval(-1200),
            resetsAt:     now.addingTimeInterval(16_800),
            usedFraction: 0.20,
            totalTokens:  1
        )
        let buckets = [
            CostBucket(start: now.addingTimeInterval(-1200), end: now.addingTimeInterval(-900), costUSD: 0.05),
            CostBucket(start: now.addingTimeInterval(-900),  end: now.addingTimeInterval(-600), costUSD: 0.10),
            CostBucket(start: now.addingTimeInterval(-600),  end: now.addingTimeInterval(-300), costUSD: 0.20),
            CostBucket(start: now.addingTimeInterval(-300),  end: now,                          costUSD: 0.40),
        ]
        let r = await f.forecastSessionBlock(block: snap, recent: buckets)
        XCTAssertEqual(r.basis, .ewma)
        XCTAssertTrue(r.willHit, "accelerating pace should predict a hit")
    }

    func testEwmaBasisSteadyLowPaceDoesNotFire() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt:    now.addingTimeInterval(-1200),
            resetsAt:     now.addingTimeInterval(16_800),
            usedFraction: 0.05,
            totalTokens:  1
        )
        let buckets = [
            CostBucket(start: now.addingTimeInterval(-1200), end: now.addingTimeInterval(-900), costUSD: 0.001),
            CostBucket(start: now.addingTimeInterval(-900),  end: now.addingTimeInterval(-600), costUSD: 0.001),
            CostBucket(start: now.addingTimeInterval(-600),  end: now.addingTimeInterval(-300), costUSD: 0.001),
            CostBucket(start: now.addingTimeInterval(-300),  end: now,                          costUSD: 0.001),
        ]
        let r = await f.forecastSessionBlock(block: snap, recent: buckets)
        XCTAssertEqual(r.basis, .ewma)
        XCTAssertFalse(r.willHit)
    }
}
