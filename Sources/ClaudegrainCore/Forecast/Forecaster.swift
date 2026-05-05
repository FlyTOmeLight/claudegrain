import Foundation

public struct ForecastResult: Equatable, Sendable {
    public enum Confidence: String, Sendable { case low, medium, high }
    public enum Basis:      String, Sendable { case ewma, linear, insufficient }

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
    public func forecastSessionBlock(
        block: SessionBlockSnapshot,
        recent: [CostBucket]
    ) -> ForecastResult {
        return forecast(
            usedFraction: block.usedFraction,
            elapsedSeconds: -block.startedAt.timeIntervalSinceNow,
            remainingSeconds: max(block.resetsAt.timeIntervalSinceNow, 0),
            recent: recent
        )
    }

    /// Predict whether the current weekly window will hit 100% before reset.
    public func forecastWeekly(
        weekly: WeeklyUsageSnapshot,
        recent: [CostBucket]
    ) -> ForecastResult {
        // Weekly snapshot lacks startedAt; assume Monday-UTC start of current week.
        let start = Self.mondayUTC(of: Date())
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(weekly.resetsAt.timeIntervalSinceNow, 0)
        return forecast(
            usedFraction: weekly.usedFraction,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            recent: recent
        )
    }

    // MARK: - Core algorithm

    private func forecast(
        usedFraction: Double,
        elapsedSeconds: Double,
        remainingSeconds: Double,
        recent: [CostBucket]
    ) -> ForecastResult {
        if recent.isEmpty {
            return .insufficient
        }
        if recent.count < 3 {
            return linearForecast(
                usedFraction: usedFraction,
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remainingSeconds
            )
        }
        // EWMA branch — Task 8.
        return linearForecast(
            usedFraction: usedFraction,
            elapsedSeconds: elapsedSeconds,
            remainingSeconds: remainingSeconds
        )
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
