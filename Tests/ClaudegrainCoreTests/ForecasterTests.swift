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
}
