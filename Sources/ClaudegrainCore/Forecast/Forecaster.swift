import Foundation

public struct ForecastResult: Equatable, Sendable {
    public enum Confidence: String, Sendable { case low, medium, high }
    /// `pattern` and `blend` were added in v0.3 (ADR-0016). `pattern` is pure
    /// historical projection from `hourly_buckets`; `blend` mixes it with the
    /// current EWMA burn rate using a freshness-weighted α.
    public enum Basis:      String, Sendable { case ewma, linear, insufficient, pattern, blend }

    public let willHit: Bool
    public let hitAt: Date?
    public let confidence: Confidence
    public let basis: Basis

    public init(willHit: Bool, hitAt: Date?, confidence: Confidence, basis: Basis) {
        self.willHit = willHit
        self.hitAt = hitAt
        self.confidence = confidence
        self.basis = basis
    }

    public static let insufficient = ForecastResult(
        willHit: false, hitAt: nil, confidence: .low, basis: .insufficient
    )
}

public actor Forecaster {
    public init() {}

    /// Predict whether the current 5h block will hit 100% before reset.
    /// When `hourly` carries trusted buckets (ADR-0016), the projection blends
    /// the EWMA burn rate with the historical hourly pattern.
    public func forecastSessionBlock(
        block: SessionBlockSnapshot,
        recent: [CostBucket],
        hourly: [HourlyBucket] = [],
        now: Date = Date()
    ) -> ForecastResult {
        return forecast(
            usedFraction: block.usedFraction,
            elapsedSeconds: now.timeIntervalSince(block.startedAt),
            remainingSeconds: max(block.resetsAt.timeIntervalSince(now), 0),
            recent: recent,
            hourly: hourly,
            now: now
        )
    }

    /// Predict whether the current weekly window will hit 100% before reset.
    public func forecastWeekly(
        weekly: WeeklyUsageSnapshot,
        recent: [CostBucket],
        hourly: [HourlyBucket] = [],
        now: Date = Date()
    ) -> ForecastResult {
        // Weekly snapshot lacks startedAt; assume Monday-UTC start of current week.
        let start = Self.mondayUTC(of: now)
        let elapsed = now.timeIntervalSince(start)
        let remaining = max(weekly.resetsAt.timeIntervalSince(now), 0)
        return forecast(
            usedFraction: weekly.usedFraction,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            recent: recent,
            hourly: hourly,
            now: now
        )
    }

    // MARK: - Core algorithm

    private func forecast(
        usedFraction: Double,
        elapsedSeconds: Double,
        remainingSeconds: Double,
        recent: [CostBucket],
        hourly: [HourlyBucket],
        now: Date
    ) -> ForecastResult {
        // ADR-0016 v2 path. Trust the pattern only when there are enough trusted
        // buckets in the *future* slice we'd be projecting through. Thin pattern
        // data falls back to v1 (linear / ewma).
        let patternFracPerSec = patternFractionPerSecond(
            usedFraction: usedFraction,
            elapsedSeconds: elapsedSeconds,
            remainingSeconds: remainingSeconds,
            hourly: hourly,
            now: now
        )

        if recent.isEmpty {
            // No current burn signal. Pure pattern projection if we have one.
            if let p = patternFracPerSec {
                return projectFraction(
                    usedFraction: usedFraction,
                    fractionPerSecond: p,
                    remainingSeconds: remainingSeconds,
                    basis: .pattern,
                    confidence: .low,
                    now: now
                )
            }
            return .insufficient
        }

        if recent.count < 3 {
            // Linear v1 path; blend if pattern available.
            let linear = linearForecast(
                usedFraction: usedFraction,
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remainingSeconds
            )
            return maybeBlend(
                base: linear,
                baseFracPerSec: linearFractionPerSecond(usedFraction: usedFraction, elapsedSeconds: elapsedSeconds),
                patternFracPerSec: patternFracPerSec,
                usedFraction: usedFraction,
                remainingSeconds: remainingSeconds,
                recentCount: recent.count,
                now: now
            )
        }

        let ewma = ewmaForecast(
            usedFraction: usedFraction,
            elapsedSeconds: elapsedSeconds,
            remainingSeconds: remainingSeconds,
            buckets: recent
        )
        return maybeBlend(
            base: ewma,
            baseFracPerSec: ewmaFractionPerSecond(usedFraction: usedFraction, buckets: recent),
            patternFracPerSec: patternFracPerSec,
            usedFraction: usedFraction,
            remainingSeconds: remainingSeconds,
            recentCount: recent.count,
            now: now
        )
    }

    // MARK: - Pattern (ADR-0016)

    /// Sum of `cost_usd` over the (weekday, hour) slots covering [now, now+remaining],
    /// converted to fraction-per-second using the same `usedFraction/sumCost` anchor
    /// as the EWMA path. nil when fewer than 3 trusted slots intersect the window.
    private func patternFractionPerSecond(
        usedFraction: Double,
        elapsedSeconds: Double,
        remainingSeconds: Double,
        hourly: [HourlyBucket],
        now: Date
    ) -> Double? {
        guard !hourly.isEmpty, remainingSeconds > 0, usedFraction > 0 else { return nil }
        // index hourly by (weekday, hour) for O(1) lookup
        var lookup: [Int: HourlyBucket] = [:]
        var totalCost: Double = 0
        for b in hourly {
            lookup[b.weekday * 24 + b.hour] = b
            totalCost += b.costUSD
        }
        guard totalCost > 0 else { return nil }

        let cal = Calendar.current
        var trusted = 0
        var weightedCost: Double = 0
        var t = now
        let endTs = now.addingTimeInterval(remainingSeconds)

        // Walk hour-aligned chunks. First chunk = remainder of current hour.
        while t < endTs {
            let hourStart = cal.date(bySetting: .minute, value: 0, of: t).flatMap {
                cal.date(bySetting: .second, value: 0, of: $0)
            } ?? t
            let nextHour = cal.date(byAdding: .hour, value: 1, to: hourStart) ?? endTs
            let chunkEnd = min(nextHour, endTs)
            let chunkSeconds = chunkEnd.timeIntervalSince(t)
            let weekday = cal.component(.weekday, from: t)
            let hour = cal.component(.hour, from: t)
            if let bucket = lookup[weekday * 24 + hour], bucket.isTrusted {
                trusted += 1
                weightedCost += bucket.costUSD * (chunkSeconds / 3600.0)
            }
            t = chunkEnd
        }

        guard trusted >= 3 else { return nil }

        // Convert pattern $ → fraction/sec using the realized $/fraction anchor.
        // Same shape as ewmaForecast: usedFraction/sumCost-of-recent. Here we
        // anchor on the *full pattern total* totalCost, which is roughly the
        // 7-day decayed weekly total, divided across remaining seconds.
        let fractionPerDollar = usedFraction / totalCost
        return weightedCost * fractionPerDollar / remainingSeconds
    }

    /// Freshness weight α: more recent buckets → trust the EWMA path more.
    /// 0.8 when ≥5 recent buckets, 0.5 for 2–4, 0.3 for 0–1.
    private func freshnessAlpha(recentCount n: Int) -> Double {
        if n >= 5 { return 0.8 }
        if n >= 2 { return 0.5 }
        return 0.3
    }

    private func maybeBlend(
        base: ForecastResult,
        baseFracPerSec: Double,
        patternFracPerSec: Double?,
        usedFraction: Double,
        remainingSeconds: Double,
        recentCount: Int,
        now: Date
    ) -> ForecastResult {
        guard let p = patternFracPerSec, baseFracPerSec > 0 else { return base }
        let alpha = freshnessAlpha(recentCount: recentCount)
        let blended = alpha * baseFracPerSec + (1.0 - alpha) * p
        return projectFraction(
            usedFraction: usedFraction,
            fractionPerSecond: blended,
            remainingSeconds: remainingSeconds,
            basis: .blend,
            confidence: base.confidence,
            now: now
        )
    }

    private func projectFraction(
        usedFraction: Double,
        fractionPerSecond: Double,
        remainingSeconds: Double,
        basis: ForecastResult.Basis,
        confidence: ForecastResult.Confidence,
        now: Date
    ) -> ForecastResult {
        guard fractionPerSecond > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: basis)
        }
        let secondsToHit = (1.0 - usedFraction) / fractionPerSecond
        let hits = secondsToHit > 0 && secondsToHit <= remainingSeconds
        return ForecastResult(
            willHit: hits,
            hitAt: hits ? now.addingTimeInterval(secondsToHit) : nil,
            confidence: confidence,
            basis: basis
        )
    }

    private func linearFractionPerSecond(usedFraction: Double, elapsedSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        return usedFraction / elapsedSeconds
    }

    private func ewmaFractionPerSecond(usedFraction: Double, buckets: [CostBucket]) -> Double {
        guard !buckets.isEmpty else { return 0 }
        let alpha = 0.4
        var ewmaCost = buckets[0].costUSD
        for b in buckets.dropFirst() {
            ewmaCost = alpha * b.costUSD + (1 - alpha) * ewmaCost
        }
        let bucketSize = buckets[0].end.timeIntervalSince(buckets[0].start)
        let sumCost = buckets.reduce(0) { $0 + $1.costUSD }
        guard bucketSize > 0, sumCost > 0 else { return 0 }
        return (ewmaCost * (usedFraction / sumCost)) / bucketSize
    }

    /// EWMA over per-bucket cost (oldest → newest). α = 0.4.
    /// Smooths the recent burn rate and projects forward to predict hit time.
    private func ewmaForecast(
        usedFraction: Double,
        elapsedSeconds: Double,
        remainingSeconds: Double,
        buckets: [CostBucket]
    ) -> ForecastResult {
        let alpha = 0.4
        var ewmaCost = buckets[0].costUSD
        for bucket in buckets.dropFirst() {
            ewmaCost = alpha * bucket.costUSD + (1 - alpha) * ewmaCost
        }
        let bucketSize = buckets[0].end.timeIntervalSince(buckets[0].start)
        guard bucketSize > 0, elapsedSeconds > 0, usedFraction > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .ewma)
        }

        // ewmaCost = smoothed cost-per-bucket (dollars). The user's plan-tier $/budget
        // is implicit. We translate cost-per-bucket → fraction-per-second by anchoring
        // on the realized rate over the elapsed window:
        //     historicalFractionPerCost = usedFraction / sumCost   (fraction per $1)
        //     smoothedFractionPerSecond = ewmaCost * historicalFractionPerCost / bucketSize
        let sumCost = buckets.reduce(0) { $0 + $1.costUSD }
        guard sumCost > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .ewma)
        }
        let smoothedFractionPerSecond = (ewmaCost * (usedFraction / sumCost)) / bucketSize

        guard smoothedFractionPerSecond > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .ewma)
        }
        let secondsToHit = (1.0 - usedFraction) / smoothedFractionPerSecond
        let hits = secondsToHit > 0 && secondsToHit <= remainingSeconds

        return ForecastResult(
            willHit: hits,
            hitAt: hits ? Date().addingTimeInterval(secondsToHit) : nil,
            confidence: confidenceFor(bucketCount: buckets.count),
            basis: .ewma
        )
    }

    private func confidenceFor(bucketCount n: Int) -> ForecastResult.Confidence {
        if n >= 10 { return .high }
        if n >= 5  { return .medium }
        return .low
    }

    private func linearForecast(
        usedFraction: Double,
        elapsedSeconds: Double,
        remainingSeconds: Double
    ) -> ForecastResult {
        guard elapsedSeconds > 0, remainingSeconds > 0, usedFraction > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .linear)
        }
        let ratePerSecond = usedFraction / elapsedSeconds      // fraction/sec
        let secondsToHit  = (1.0 - usedFraction) / ratePerSecond
        if secondsToHit <= remainingSeconds {
            return ForecastResult(
                willHit: true,
                hitAt: Date().addingTimeInterval(secondsToHit),
                confidence: .low,
                basis: .linear
            )
        }
        return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .linear)
    }

    static func mondayUTC(of date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }
}
