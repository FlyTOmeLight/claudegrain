import Foundation
import GRDB

public actor EventsDatabase {
    public static let defaultDirectory: URL = {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("claudegrain", isDirectory: true)
    }()

    public static var defaultURL: URL {
        defaultDirectory.appendingPathComponent("cache.db")
    }

    private let pool: DatabasePool

    /// Opens (or creates) the events database at `url`. Ensures parent dir exists.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.label = "claudegrain.events"
        self.pool = try DatabasePool(path: url.path, configuration: config)
        try Self.migrate(pool: pool)
    }

    public static func migrate(pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ts", .datetime).notNull()
                t.column("session_id", .text).notNull()
                t.column("cwd", .text)
                t.column("git_branch", .text)
                t.column("model", .text).notNull()
                t.column("primary_tool", .text)
                t.column("mcp_server", .text)
                t.column("in_tok", .integer).notNull()
                t.column("out_tok", .integer).notNull()
                t.column("cache_create_tok", .integer).notNull()
                t.column("cache_read_tok", .integer).notNull()
                t.column("cost_usd", .double).notNull()
                t.column("source_file", .text).notNull()
                t.column("source_offset", .integer).notNull()
            }
            try db.create(index: "idx_events_ts", on: "events", columns: ["ts"])
            try db.create(index: "idx_events_cwd_ts", on: "events", columns: ["cwd", "ts"])
            try db.create(index: "idx_events_tool_ts", on: "events", columns: ["primary_tool", "ts"])
            try db.create(
                index: "uq_events_source",
                on: "events",
                columns: ["source_file", "source_offset"],
                options: [.unique]
            )

            try db.create(table: "cursors") { t in
                t.column("file_path", .text).primaryKey()
                t.column("inode", .integer).notNull()
                t.column("device_id", .integer).notNull()
                t.column("offset", .integer).notNull()
                t.column("size_at_last_read", .integer).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }
        // v2: cross-file dedup. Same assistant turn appears in parent transcript +
        // any forked sidechain jsonl, so the v1 (source_file, source_offset) unique
        // index let duplicates through. dedup_key = "<message.id>|<requestId>".
        // Partial unique index — NULL keys (legacy events) stay tolerated.
        migrator.registerMigration("v2-dedup-key") { db in
            try db.execute(sql: "ALTER TABLE events ADD COLUMN dedup_key TEXT")
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_events_dedup
                ON events(dedup_key) WHERE dedup_key IS NOT NULL
            """)
        }
        // v3: collapse rows already double-counted under v1. Keep min(id) per dedup key.
        migrator.registerMigration("v3-purge-duplicates") { db in
            try db.execute(sql: """
                DELETE FROM events
                WHERE dedup_key IS NOT NULL
                  AND id NOT IN (
                    SELECT MIN(id) FROM events WHERE dedup_key IS NOT NULL GROUP BY dedup_key
                  )
            """)
        }
        try migrator.migrate(pool)
    }

    // MARK: - Writes (per ADR-0002: cursor + insert in same transaction)

    public func insertEvents(
        _ events: [UsageEvent],
        from sourceFile: String,
        startingAt offset: UInt64,
        cursor: JSONLReader.Cursor
    ) throws {
        try pool.write { db in
            var runningOffset = offset
            for event in events {
                let cost = CostCalculator.cost(for: event)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO events
                    (ts, session_id, cwd, git_branch, model, primary_tool, mcp_server,
                     in_tok, out_tok, cache_create_tok, cache_read_tok, cost_usd,
                     source_file, source_offset, dedup_key)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        event.timestamp,
                        event.sessionId,
                        event.cwd,
                        event.gitBranch,
                        event.model,
                        event.primaryTool,
                        event.primaryMcpServer,
                        event.inputTokens,
                        event.outputTokens,
                        event.cacheCreationTokens,
                        event.cacheReadTokens,
                        cost,
                        sourceFile,
                        Int64(runningOffset),
                        event.dedupKey,
                    ]
                )
                runningOffset += 1
            }
            try db.execute(
                sql: """
                INSERT INTO cursors (file_path, inode, device_id, offset, size_at_last_read, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(file_path) DO UPDATE SET
                  inode = excluded.inode,
                  device_id = excluded.device_id,
                  offset = excluded.offset,
                  size_at_last_read = excluded.size_at_last_read,
                  updated_at = excluded.updated_at
                """,
                arguments: [
                    sourceFile,
                    Int64(cursor.inode),
                    Int64(cursor.deviceId),
                    Int64(cursor.offset),
                    Int64(cursor.sizeAtLastRead),
                    Date(),
                ]
            )
        }
    }

    public func cursor(for file: String) throws -> JSONLReader.Cursor {
        try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT inode, device_id, offset, size_at_last_read FROM cursors WHERE file_path = ?",
                arguments: [file]
            )
            guard let row else { return .init() }
            let offset: Int64 = row["offset"]
            let inode: Int64 = row["inode"]
            let deviceId: Int64 = row["device_id"]
            let size: Int64 = row["size_at_last_read"]
            return JSONLReader.Cursor(
                offset: UInt64(offset),
                inode: UInt64(inode),
                deviceId: UInt64(deviceId),
                sizeAtLastRead: UInt64(size)
            )
        }
    }

    // MARK: - Aggregations

    public func dailyTotals(on day: Date, calendar: Calendar = .current) throws -> DailyTotals {
        let (start, end) = Self.dayBounds(day, calendar: calendar)
        return try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                  COALESCE(SUM(cost_usd), 0) AS cost,
                  COALESCE(SUM(in_tok + out_tok + cache_create_tok + cache_read_tok), 0) AS toks
                FROM events
                WHERE ts >= ? AND ts < ?
                """,
                arguments: [start, end]
            )
            let cost = row?["cost"] as? Double ?? 0
            let toks = Int(row?["toks"] as? Int64 ?? 0)

            var byModel: [String: Int] = [:]
            let modelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT model, SUM(in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY model
                """,
                arguments: [start, end]
            )
            for row in modelRows {
                let m: String = row["model"]
                byModel[m] = Int(row["toks"] as Int64? ?? 0)
            }
            return DailyTotals(costUSD: cost, totalTokens: toks, byModel: byModel)
        }
    }

    /// All-time totals across the entire events table. Wired to the HeroSpend
    /// "TOTAL" tab so users can see lifetime spend vs today.
    public func allTimeTotals() throws -> DailyTotals {
        return try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                  COALESCE(SUM(cost_usd), 0) AS cost,
                  COALESCE(SUM(in_tok + out_tok + cache_create_tok + cache_read_tok), 0) AS toks
                FROM events
                """
            )
            let cost = row?["cost"] as? Double ?? 0
            let toks = Int(row?["toks"] as? Int64 ?? 0)

            var byModel: [String: Int] = [:]
            let modelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT model, SUM(in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                GROUP BY model
                """
            )
            for row in modelRows {
                let m: String = row["model"]
                byModel[m] = Int(row["toks"] as Int64? ?? 0)
            }
            return DailyTotals(costUSD: cost, totalTokens: toks, byModel: byModel)
        }
    }

    public func topRepos(on day: Date, limit: Int = 5, calendar: Calendar = .current) throws -> [RepoBreakdown] {
        let (start, end) = Self.dayBounds(day, calendar: calendar)
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT cwd,
                       SUM(cost_usd) AS cost,
                       SUM(in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                WHERE ts >= ? AND ts < ? AND cwd IS NOT NULL
                GROUP BY cwd
                ORDER BY cost DESC
                LIMIT ?
                """,
                arguments: [start, end, limit]
            ).map { row in
                let cwd: String = row["cwd"]
                return RepoBreakdown(
                    repo: shortRepoName(cwd),
                    fullCwd: cwd,
                    costUSD: row["cost"],
                    totalTokens: Int(row["toks"] as Int64? ?? 0)
                )
            }
        }
    }

    public func topTools(on day: Date, limit: Int = 5, calendar: Calendar = .current) throws -> [ToolBreakdown] {
        let (start, end) = Self.dayBounds(day, calendar: calendar)
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT primary_tool, mcp_server,
                       SUM(cost_usd) AS cost,
                       SUM(in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                WHERE ts >= ? AND ts < ? AND primary_tool IS NOT NULL
                GROUP BY primary_tool
                ORDER BY cost DESC
                LIMIT ?
                """,
                arguments: [start, end, limit]
            ).map { row in
                ToolBreakdown(
                    toolName: row["primary_tool"],
                    mcpServer: row["mcp_server"],
                    costUSD: row["cost"],
                    totalTokens: Int(row["toks"] as Int64? ?? 0)
                )
            }
        }
    }

    public func cacheHitRate(on day: Date, calendar: Calendar = .current) throws -> Double {
        let (start, end) = Self.dayBounds(day, calendar: calendar)
        return try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                  COALESCE(SUM(cache_read_tok), 0) AS cr,
                  COALESCE(SUM(in_tok + cache_create_tok + cache_read_tok), 0) AS denom
                FROM events
                WHERE ts >= ? AND ts < ?
                """,
                arguments: [start, end]
            )
            guard let row else { return 0 }
            let cr = Double(row["cr"] as Int64? ?? 0)
            let denom = Double(row["denom"] as Int64? ?? 0)
            return denom > 0 ? cr / denom : 0
        }
    }

    /// Per-event timestamps and total tokens since `cutoff`, ordered by ts asc.
    /// Used by LimitEstimator for P90 fallback.
    public func tokensSince(_ cutoff: Date) throws -> [(ts: Date, tokens: Int)] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT ts, (in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                WHERE ts >= ?
                ORDER BY ts ASC
                """,
                arguments: [cutoff]
            ).map { row in
                (ts: row["ts"] as Date, tokens: Int(row["toks"] as Int64? ?? 0))
            }
        }
    }

    public func purgeOlderThan(_ cutoff: Date) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM events WHERE ts < ?", arguments: [cutoff])
        }
    }

    /// Sum cost grouped by `ModelFamily` over the half-open interval [since, until).
    /// Family grouping happens in Swift (ADR-0006); SQL just sums per raw model id.
    public func costPerModel(since: Date, until: Date) throws -> [ModelFamily: Double] {
        let rows: [(model: String, cost: Double)] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT model, COALESCE(SUM(cost_usd), 0) AS s
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY model
                """, arguments: [since, until])
                .map { (model: $0["model"] ?? "", cost: $0["s"] ?? 0.0) }
        }

        var out: [ModelFamily: Double] = [:]
        for r in rows {
            out[ModelFamily.parse(r.model), default: 0] += r.cost
        }
        return out
    }

    /// 7-day daily spend totals (USD) ending at `now`. Returns 7 values, oldest → newest.
    public func costPerDay(days: Int = 7, now: Date = .now, calendar: Calendar = .current) throws -> [Double] {
        var result = [Double](repeating: 0, count: days)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT date(ts, 'localtime') AS d, COALESCE(SUM(cost_usd), 0) AS cost
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY d
                """,
                arguments: [start, endOfToday]
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            for row in rows {
                guard let day: String = row["d"], let date = formatter.date(from: day) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                let idx = calendar.dateComponents([.day], from: start, to: dayStart).day ?? 0
                if idx >= 0 && idx < days {
                    result[idx] = row["cost"] as? Double ?? 0
                }
            }
        }
        return result
    }

    /// Per-repo daily spend totals (USD) for last `days` days. Returns map of cwd → 7 values.
    /// Filtered to a candidate set of repos so the result fits a UI list (top 5 etc.).
    public func costPerDayByRepo(days: Int = 7, repos: [String], now: Date = .now, calendar: Calendar = .current) throws -> [String: [Double]] {
        guard !repos.isEmpty else { return [:] }
        var output: [String: [Double]] = Dictionary(uniqueKeysWithValues: repos.map { ($0, [Double](repeating: 0, count: days)) })
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!

        try pool.read { db in
            let placeholders = repos.map { _ in "?" }.joined(separator: ",")
            let sql = """
            SELECT cwd, date(ts, 'localtime') AS d, COALESCE(SUM(cost_usd), 0) AS cost
            FROM events
            WHERE ts >= ? AND ts < ? AND cwd IN (\(placeholders))
            GROUP BY cwd, d
            """
            var args: [DatabaseValueConvertible] = [start, endOfToday]
            args.append(contentsOf: repos.map { $0 as DatabaseValueConvertible })
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            for row in rows {
                guard let cwd: String = row["cwd"],
                      let day: String = row["d"],
                      let date = formatter.date(from: day) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                let idx = calendar.dateComponents([.day], from: start, to: dayStart).day ?? 0
                if idx >= 0 && idx < days {
                    output[cwd]?[idx] = row["cost"] as? Double ?? 0
                }
            }
        }
        return output
    }

    // MARK: - Helpers

    static func dayBounds(_ day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}

private func shortRepoName(_ cwd: String) -> String {
    let url = URL(fileURLWithPath: cwd)
    let parts = url.pathComponents.suffix(2)
    return parts.joined(separator: "/")
}
