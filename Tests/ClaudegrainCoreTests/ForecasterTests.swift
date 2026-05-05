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
}
