import Foundation

public struct WeekDelta: Equatable, Sendable {
    public let thisWeekCost: Double
    public let lastWeekCost: Double
    public let cacheHitDelta: Double      // percentage points (this - last)

    public var pctChange: Double? {
        lastWeekCost > 0 ? (thisWeekCost - lastWeekCost) / lastWeekCost : nil
    }

    public init(thisWeekCost: Double, lastWeekCost: Double, cacheHitDelta: Double) {
        self.thisWeekCost  = thisWeekCost
        self.lastWeekCost  = lastWeekCost
        self.cacheHitDelta = cacheHitDelta
    }

    /// Compute against `db` using Monday-UTC week boundaries (matches WeeklyUsageSnapshot).
    public static func compute(db: EventsDatabase, now: Date = Date()) async -> WeekDelta {
        let thisStart = mondayUTC(of: now)
        let lastStart = thisStart.addingTimeInterval(-7 * 86_400)

        let thisCost = (try? await db.costInWindow(start: thisStart, end: now)) ?? 0
        let lastEnd  = lastStart.addingTimeInterval(7 * 86_400)
        let lastCost = (try? await db.costInWindow(start: lastStart, end: lastEnd)) ?? 0

        let thisHit = (try? await db.cacheHitRateInWindow(start: thisStart, end: now)) ?? 0
        let lastHit = (try? await db.cacheHitRateInWindow(start: lastStart, end: lastEnd)) ?? 0

        return WeekDelta(
            thisWeekCost: thisCost,
            lastWeekCost: lastCost,
            cacheHitDelta: thisHit - lastHit
        )
    }

    public static func mondayUTC(of date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }
}
