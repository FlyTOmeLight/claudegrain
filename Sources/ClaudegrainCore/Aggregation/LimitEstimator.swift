import Foundation

/// JSONL-only fallback rate-limit estimator (per ADR-0001/0004).
///
/// When OAuth `/oauth/usage` is unavailable, derives plan limits from local
/// jsonl history using P90 of historical session-block / weekly totals.
/// Reference: Maciek-roboblog/Claude-Code-Usage-Monitor.
public actor LimitEstimator {
    private let db: EventsDatabase
    private let blockDuration: TimeInterval = 5 * 3600
    private let weekDuration: TimeInterval = 7 * 86400
    private let historyDays: Int = 30

    public init(db: EventsDatabase) {
        self.db = db
    }

    public func estimateSessionBlock(now: Date = .now) async throws -> SessionBlockSnapshot {
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86400)
        let rows = try await db.tokensSince(cutoff)

        let blocks = Self.buildBlocks(rows: rows, blockDuration: blockDuration, now: now)
        let current = blocks.last(where: { $0.contains(now) })

        let historicalTotals = blocks
            .filter { $0 !== current && $0.endedAt <= now }
            .map(\.totalTokens)

        let limit = Self.p90(historicalTotals) ?? current?.totalTokens ?? 0
        let curBlock = current ?? Block(startedAt: now, endedAt: now.addingTimeInterval(blockDuration), totalTokens: 0)
        let frac = limit > 0 ? Double(curBlock.totalTokens) / Double(limit) : 0

        return SessionBlockSnapshot(
            startedAt: curBlock.startedAt,
            resetsAt: curBlock.startedAt.addingTimeInterval(blockDuration),
            usedFraction: min(max(frac, 0), 1.5),
            totalTokens: curBlock.totalTokens
        )
    }

    public func estimateWeekly(now: Date = .now) async throws -> WeeklyUsageSnapshot {
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86400)
        let rows = try await db.tokensSince(cutoff)

        let totals = Self.rollingWeekTotals(rows: rows, window: weekDuration, now: now)
        let currentWeekStart = now.addingTimeInterval(-weekDuration)
        let currentTokens = rows
            .filter { $0.ts >= currentWeekStart && $0.ts <= now }
            .reduce(0) { $0 + $1.tokens }

        let historical = totals.filter { $0.endedAt <= currentWeekStart }.map(\.tokens)
        let limit = Self.p90(historical) ?? currentTokens
        let frac = limit > 0 ? Double(currentTokens) / Double(limit) : 0

        return WeeklyUsageSnapshot(
            usedFraction: min(max(frac, 0), 1.5),
            resetsAt: now.addingTimeInterval(weekDuration)
        )
    }

    // MARK: - Block construction

    final class Block {
        let startedAt: Date
        var endedAt: Date
        var totalTokens: Int
        init(startedAt: Date, endedAt: Date, totalTokens: Int) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.totalTokens = totalTokens
        }
        func contains(_ ts: Date) -> Bool { ts >= startedAt && ts < endedAt }
    }

    /// Walks rows in ts order. Starts new block on >5h gap or when ts past current block end.
    static func buildBlocks(rows: [(ts: Date, tokens: Int)], blockDuration: TimeInterval, now: Date) -> [Block] {
        var blocks: [Block] = []
        var lastTs: Date?
        for r in rows {
            if let last = blocks.last,
               let prev = lastTs,
               r.ts < last.endedAt,
               r.ts.timeIntervalSince(prev) <= blockDuration {
                last.totalTokens += r.tokens
            } else {
                let b = Block(
                    startedAt: r.ts,
                    endedAt: r.ts.addingTimeInterval(blockDuration),
                    totalTokens: r.tokens
                )
                blocks.append(b)
            }
            lastTs = r.ts
        }
        return blocks
    }

    // MARK: - Rolling weekly buckets

    struct WeekTotal {
        let startedAt: Date
        let endedAt: Date
        let tokens: Int
    }

    /// Sliding 7-day windows aligned to day boundaries, ending at `now`.
    static func rollingWeekTotals(rows: [(ts: Date, tokens: Int)], window: TimeInterval, now: Date) -> [WeekTotal] {
        guard let first = rows.first?.ts else { return [] }
        let cal = Calendar(identifier: .gregorian)
        var dayStart = cal.startOfDay(for: first)
        let endDay = cal.startOfDay(for: now)
        var out: [WeekTotal] = []
        while dayStart <= endDay {
            let winEnd = dayStart.addingTimeInterval(window)
            let total = rows.filter { $0.ts >= dayStart && $0.ts < winEnd }.reduce(0) { $0 + $1.tokens }
            out.append(WeekTotal(startedAt: dayStart, endedAt: winEnd, tokens: total))
            dayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
        }
        return out
    }

    // MARK: - P90

    /// Linear-interpolated 90th percentile. Returns nil for empty input.
    static func p90(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let rank = 0.9 * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = rank - Double(lo)
        return Int(Double(sorted[lo]) + frac * Double(sorted[hi] - sorted[lo]))
    }
}
