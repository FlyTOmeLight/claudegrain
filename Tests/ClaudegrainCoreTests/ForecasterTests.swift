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

    func testConfidenceTiers() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt:    now.addingTimeInterval(-1200),
            resetsAt:     now.addingTimeInterval(16_800),
            usedFraction: 0.20,
            totalTokens:  1
        )

        func bucketsOf(_ n: Int) -> [CostBucket] {
            (0..<n).map { i in
                CostBucket(
                    start: now.addingTimeInterval(Double(-300 * (n - i))),
                    end:   now.addingTimeInterval(Double(-300 * (n - i - 1))),
                    costUSD: 0.10
                )
            }
        }

        let r3  = await f.forecastSessionBlock(block: snap, recent: bucketsOf(3))
        let r5  = await f.forecastSessionBlock(block: snap, recent: bucketsOf(5))
        let r10 = await f.forecastSessionBlock(block: snap, recent: bucketsOf(10))

        XCTAssertEqual(r3.confidence,  .low)
        XCTAssertEqual(r5.confidence,  .medium)
        XCTAssertEqual(r10.confidence, .high)
    }

    // MARK: - v2 cycle-aware (ADR-0016)

    /// Default `hourly: []` keeps v1 behavior — basis stays `.ewma`.
    func testEmptyHourlyKeepsEwmaBasis() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10, totalTokens: 1
        )
        let buckets = makeRecentBuckets(now: now, count: 5)
        let r = await f.forecastSessionBlock(block: snap, recent: buckets)
        XCTAssertEqual(r.basis, ForecastResult.Basis.ewma)
    }

    /// Trusted hourly + recent buckets → blend basis.
    func testHourlyTriggersBlendBasis() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200), // 4.5h remaining
            usedFraction: 0.10, totalTokens: 1
        )
        let recent = makeRecentBuckets(now: now, count: 5)
        let r = await f.forecastSessionBlock(
            block: snap,
            recent: recent,
            hourly: trustedAllHours(),
            now: now
        )
        XCTAssertEqual(r.basis, ForecastResult.Basis.blend, "trusted hourly + recent ⇒ blend")
    }

    /// Trusted hourly with empty `recent` → pure pattern basis.
    func testEmptyRecentWithHourlyGivesPatternBasis() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10, totalTokens: 1
        )
        let r = await f.forecastSessionBlock(
            block: snap,
            recent: [],
            hourly: trustedAllHours(),
            now: now
        )
        XCTAssertEqual(r.basis, ForecastResult.Basis.pattern, "no current burn but trusted pattern ⇒ pattern")
    }

    /// Sparse / untrusted hourly (sample_count<1 in window) → falls back to ewma.
    func testUntrustedHourlyFallsBackToEwma() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10, totalTokens: 1
        )
        let recent = makeRecentBuckets(now: now, count: 5)
        // All buckets exist but sample_count = 0 → not trusted.
        var untrusted: [HourlyBucket] = []
        for wd in 1...7 {
            for h in 0...23 {
                untrusted.append(HourlyBucket(weekday: wd, hour: h, costUSD: 5.0, tokens: 0, sampleCount: 0.0))
            }
        }
        let r = await f.forecastSessionBlock(
            block: snap, recent: recent, hourly: untrusted, now: now
        )
        XCTAssertEqual(r.basis, ForecastResult.Basis.ewma, "no trusted hourly slots → no blend")
    }

    /// Pattern much heavier than current burn → blend hitAt closer than pure ewma.
    func testHighPatternCostMovesHitEarlier() async {
        let f = Forecaster()
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10, totalTokens: 1
        )
        let recent = makeRecentBuckets(now: now, count: 5)
        let heavyHourly = trustedAllHours(costPerHour: 1000.0)

        let pureEwma = await f.forecastSessionBlock(block: snap, recent: recent, hourly: [],          now: now)
        let blended  = await f.forecastSessionBlock(block: snap, recent: recent, hourly: heavyHourly, now: now)

        XCTAssertEqual(blended.basis, ForecastResult.Basis.blend)
        if let bHit = blended.hitAt, let eHit = pureEwma.hitAt {
            XCTAssertLessThan(bHit, eHit, "heavy pattern ⇒ projected to hit earlier")
        } else if pureEwma.hitAt == nil {
            XCTAssertNotNil(blended.hitAt, "pattern should make blend project a hit even if ewma alone wouldn't")
        }
    }

    // MARK: - Helpers

    private func trustedAllHours(costPerHour: Double = 1.0, samples: Double = 5.0) -> [HourlyBucket] {
        var out: [HourlyBucket] = []
        for wd in 1...7 {
            for h in 0...23 {
                out.append(HourlyBucket(weekday: wd, hour: h, costUSD: costPerHour, tokens: 0, sampleCount: samples))
            }
        }
        return out
    }

    private func makeRecentBuckets(now: Date, count: Int, costUSD: Double = 1.0) -> [CostBucket] {
        var out: [CostBucket] = []
        for i in 0..<count {
            let startOffset = Double(-1500 + 300 * i)
            let endOffset   = Double(-1200 + 300 * i)
            out.append(CostBucket(
                start: now.addingTimeInterval(startOffset),
                end:   now.addingTimeInterval(endOffset),
                costUSD: costUSD
            ))
        }
        return out
    }
}
