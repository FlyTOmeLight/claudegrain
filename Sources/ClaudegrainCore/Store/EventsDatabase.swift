import Foundation
import GRDB

public struct TokenBreakdown: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheCreation: Int
    public let cacheRead: Int
    public init(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }
    public var total: Int { input + output + cacheCreation + cacheRead }
}

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
        // v4: tool attribution v2 (ADR-0015). Persist full per-turn tools array as
        // JSON. Legacy rows stay NULL → aggregation path falls back to primary_tool.
        migrator.registerMigration("v4-tools-json") { db in
            try db.execute(sql: "ALTER TABLE events ADD COLUMN tools_json TEXT")
        }
        // v5: hourly_buckets — 168-row weekday × hour summary with 7-day EWMA decay.
        // Powers the time-of-day heatmap and the cycle-aware forecaster (ADR-0016).
        migrator.registerMigration("v5-hourly-buckets") { db in
            try db.execute(sql: """
                CREATE TABLE hourly_buckets (
                    weekday        INTEGER NOT NULL,
                    hour           INTEGER NOT NULL,
                    cost_usd       REAL    NOT NULL DEFAULT 0,
                    tokens         REAL    NOT NULL DEFAULT 0,
                    last_event_at  REAL    NOT NULL DEFAULT 0,
                    sample_count   REAL    NOT NULL DEFAULT 0,
                    PRIMARY KEY (weekday, hour)
                )
            """)
        }
        // v6: drop legacy events that lack a dedup_key. Pre-v2 ingest accepted
        // rows even when message.id / requestId were absent (e.g. type=last-prompt
        // header lines that an earlier parser tolerated), and the partial unique
        // index leaves them un-deduped, so every JSONL re-read multiplies them.
        // Sampling on a real db showed 6,118 of 6,449 5-04 rows were these
        // ghosts — inflating Monday by an order of magnitude. SQLite is a
        // materialized view per ADR-0002, the cursor + JSONL backfill rebuilds
        // them on next launch.
        migrator.registerMigration("v6-purge-null-dedup") { db in
            try db.execute(sql: "DELETE FROM events WHERE dedup_key IS NULL")
            // Reset cursors so the JSONL backfill replays from offset 0 on
            // next ingest tick. Without this, the (source_file, source_offset)
            // unique index keeps the deleted rows from being re-inserted.
            try db.execute(sql: "DELETE FROM cursors")
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
                let toolsJson: String? = event.tools.isEmpty
                    ? nil
                    : (try? JSONEncoder().encode(event.tools)).flatMap { String(data: $0, encoding: .utf8) }
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO events
                    (ts, session_id, cwd, git_branch, model, primary_tool, mcp_server,
                     in_tok, out_tok, cache_create_tok, cache_read_tok, cost_usd,
                     source_file, source_offset, dedup_key, tools_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        toolsJson,
                    ]
                )
                runningOffset += 1
                Self.upsertHourlyBucket(db: db, event: event, cost: cost)
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

    /// Top N tools by cost over `day`. ADR-0015 attribution: when `tools_json` is
    /// present, each turn's cost/tokens are split across its tools by block-count
    /// shares (deduped by name). Legacy rows (tools_json NULL) fall back to 100% on
    /// `primary_tool`. Fan-out happens in Swift because SQLite can't fan json_each
    /// into a covered aggregate in one pass; row count per window is small.
    public func topTools(on day: Date, limit: Int = 5, calendar: Calendar = .current) throws -> [ToolBreakdown] {
        let (start, end) = Self.dayBounds(day, calendar: calendar)
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT primary_tool, tools_json, cost_usd,
                       (in_tok + out_tok + cache_create_tok + cache_read_tok) AS toks
                FROM events
                WHERE ts >= ? AND ts < ?
                  AND (primary_tool IS NOT NULL OR tools_json IS NOT NULL)
                """,
                arguments: [start, end]
            )
        }

        var costs: [String: Double] = [:]
        var tokens: [String: Double] = [:]
        let decoder = JSONDecoder()

        for row in rows {
            let cost: Double = row["cost_usd"] ?? 0
            let toks: Double = Double(row["toks"] as Int64? ?? 0)
            let primary: String? = row["primary_tool"]
            let toolsJsonRaw: String? = row["tools_json"]

            let shares: [String: Double]
            if let toolsJsonRaw,
               let data = toolsJsonRaw.data(using: .utf8),
               let arr = try? decoder.decode([String].self, from: data),
               !arr.isEmpty {
                var counts: [String: Int] = [:]
                for t in arr { counts[t, default: 0] += 1 }
                let n = Double(arr.count)
                shares = counts.mapValues { Double($0) / n }
            } else if let primary {
                shares = [primary: 1.0]
            } else {
                continue
            }

            for (tool, share) in shares {
                costs[tool, default: 0] += cost * share
                tokens[tool, default: 0] += toks * share
            }
        }

        return costs.sorted { $0.value > $1.value }.prefix(limit).map { entry in
            ToolBreakdown(
                toolName: entry.key,
                mcpServer: entry.key.mcpComponents()?.server,
                costUSD: entry.value,
                totalTokens: Int((tokens[entry.key] ?? 0).rounded())
            )
        }
    }

    /// Sum `cost_usd` over the half-open interval `[start, end)`. 0 if no events.
    public func costInWindow(start: Date, end: Date) throws -> Double {
        try pool.read { db in
            try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(cost_usd), 0)
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        } ?? 0
    }

    /// `cache_read / (input + cache_create + cache_read)` over `[start, end)`.
    /// Returns 0 if no qualifying tokens in window.
    public func cacheHitRateInWindow(start: Date, end: Date) throws -> Double {
        let row: Row? = try pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(in_tok), 0)           AS in_t,
                       COALESCE(SUM(cache_create_tok), 0) AS cc_t,
                       COALESCE(SUM(cache_read_tok), 0)   AS cr_t
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        }
        guard let row else { return 0 }
        let input: Int64         = row["in_t"] ?? 0
        let cacheCreation: Int64 = row["cc_t"] ?? 0
        let cacheRead: Int64     = row["cr_t"] ?? 0
        let denom = input + cacheCreation + cacheRead
        guard denom > 0 else { return 0 }
        return Double(cacheRead) / Double(denom)
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

    public func perRepoDaily(since: Date, until: Date) throws -> [(date: String, repo: String, events: Int, input: Int64, output: Int64, cacheRead: Int64, cacheCreation: Int64, cost: Double)] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT
                  strftime('%Y-%m-%d', ts) AS d,
                  COALESCE(cwd, '')        AS repo,
                  COUNT(*)                 AS n,
                  SUM(in_tok)              AS in_t,
                  SUM(out_tok)             AS out_t,
                  SUM(cache_read_tok)      AS cr_t,
                  SUM(cache_create_tok)    AS cc_t,
                  SUM(cost_usd)            AS cost
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY d, repo
                ORDER BY d ASC, repo ASC
                """, arguments: [since, until])
        }
        return rows.map { r -> (date: String, repo: String, events: Int, input: Int64, output: Int64, cacheRead: Int64, cacheCreation: Int64, cost: Double) in
            let d: String = r["d"] ?? ""
            let repo: String = r["repo"] ?? ""
            let n: Int64 = r["n"] ?? 0
            let inT: Int64 = r["in_t"] ?? 0
            let outT: Int64 = r["out_t"] ?? 0
            let crT: Int64 = r["cr_t"] ?? 0
            let ccT: Int64 = r["cc_t"] ?? 0
            let cost: Double = r["cost"] ?? 0
            return (date: d, repo: repo, events: Int(n), input: inT, output: outT, cacheRead: crT, cacheCreation: ccT, cost: cost)
        }
    }

    public func perToolDaily(since: Date, until: Date) throws -> [(date: String, tool: String, events: Int, input: Int64, output: Int64, cost: Double)] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT
                  strftime('%Y-%m-%d', ts)         AS d,
                  COALESCE(primary_tool, '(none)') AS tool,
                  COUNT(*)                         AS n,
                  SUM(in_tok)                      AS in_t,
                  SUM(out_tok)                     AS out_t,
                  SUM(cost_usd)                    AS cost
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY d, tool
                ORDER BY d ASC, tool ASC
                """, arguments: [since, until])
        }
        return rows.map { (r: Row) -> (date: String, tool: String, events: Int, input: Int64, output: Int64, cost: Double) in
            let d: String      = r["d"] ?? ""
            let tool: String   = r["tool"] ?? ""
            let n: Int64       = r["n"] ?? 0
            let inTok: Int64   = r["in_t"] ?? 0
            let outTok: Int64  = r["out_t"] ?? 0
            let cost: Double   = r["cost"] ?? 0
            return (d, tool, Int(n), inTok, outTok, cost)
        }
    }

    public func perModelDaily(since: Date, until: Date) throws -> [(date: String, modelId: String, events: Int, input: Int64, output: Int64, cost: Double)] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT
                  strftime('%Y-%m-%d', ts) AS d,
                  model                    AS m,
                  COUNT(*)                 AS n,
                  SUM(in_tok)              AS in_t,
                  SUM(out_tok)             AS out_t,
                  SUM(cost_usd)            AS cost
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY d, m
                ORDER BY d ASC, m ASC
                """, arguments: [since, until])
        }
        return rows.map { (r: Row) -> (date: String, modelId: String, events: Int, input: Int64, output: Int64, cost: Double) in
            let d: String     = r["d"] ?? ""
            let m: String     = r["m"] ?? ""
            let n: Int64      = r["n"] ?? 0
            let inTok: Int64  = r["in_t"] ?? 0
            let outTok: Int64 = r["out_t"] ?? 0
            let cost: Double  = r["cost"] ?? 0
            return (d, m, Int(n), inTok, outTok, cost)
        }
    }

    public func rawEventsInRange(since: Date, until: Date) throws -> [Row] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, session_id, cwd, git_branch, model, primary_tool,
                       in_tok, out_tok, cache_create_tok, cache_read_tok, cost_usd
                FROM events
                WHERE ts >= ? AND ts < ?
                ORDER BY ts ASC
                """, arguments: [since, until])
        }
    }

    /// Sum tokens grouped by `ModelFamily` over the half-open interval [since, until).
    /// Returns a per-channel `TokenBreakdown` (input/output/cacheCreation/cacheRead).
    /// Family grouping happens in Swift (ADR-0006); SQL just sums per raw model id.
    public func tokensPerModel(since: Date, until: Date) throws -> [ModelFamily: TokenBreakdown] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT model,
                       COALESCE(SUM(in_tok), 0)           AS in_t,
                       COALESCE(SUM(out_tok), 0)          AS out_t,
                       COALESCE(SUM(cache_create_tok), 0) AS cc_t,
                       COALESCE(SUM(cache_read_tok), 0)   AS cr_t
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY model
                """, arguments: [since, until])
        }

        var out: [ModelFamily: TokenBreakdown] = [:]
        for r in rows {
            let fam = ModelFamily.parse(r["model"] ?? "")
            let prior = out[fam] ?? TokenBreakdown(input: 0, output: 0, cacheCreation: 0, cacheRead: 0)
            let inT  = Int(r["in_t"]  as Int64? ?? 0)
            let outT = Int(r["out_t"] as Int64? ?? 0)
            let ccT  = Int(r["cc_t"]  as Int64? ?? 0)
            let crT  = Int(r["cr_t"]  as Int64? ?? 0)
            out[fam] = TokenBreakdown(
                input:         prior.input         + inT,
                output:        prior.output        + outT,
                cacheCreation: prior.cacheCreation + ccT,
                cacheRead:     prior.cacheRead     + crT
            )
        }
        return out
    }

    /// Returns N contiguous buckets of width `bucketSize` over `[start, start+span)`,
    /// zero-filled where there are no events. Used by `Forecaster` (ADR-0005).
    public func costPerBucket(
        start: Date,
        span: TimeInterval,
        bucketSize: TimeInterval
    ) throws -> [CostBucket] {
        precondition(bucketSize > 0)
        precondition(span > 0)
        let count = Int((span / bucketSize).rounded(.down))
        guard count > 0 else { return [] }

        let end = start.addingTimeInterval(span)
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, cost_usd
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        }

        var sums = [Double](repeating: 0, count: count)
        for r in rows {
            guard let ts: Date = r["ts"], let cost: Double = r["cost_usd"] else { continue }
            let idx = Int(ts.timeIntervalSince(start) / bucketSize)
            guard idx >= 0, idx < count else { continue }
            sums[idx] += cost
        }

        return (0..<count).map { i in
            let bs = start.addingTimeInterval(Double(i) * bucketSize)
            return CostBucket(start: bs, end: bs.addingTimeInterval(bucketSize), costUSD: sums[i])
        }
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

    // MARK: - Hourly buckets (ADR-0016)

    /// Returns all 168 (weekday, hour) buckets — weekday 1=Sun…7=Sat × hour 0…23.
    /// Missing rows are zero-filled so callers can render a full grid.
    public func hourlyBuckets() throws -> [HourlyBucket] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT weekday, hour, cost_usd, tokens, sample_count FROM hourly_buckets")
        }
        var byKey: [Int: HourlyBucket] = [:]
        for r in rows {
            let wd: Int    = r["weekday"] ?? 0
            let h:  Int    = r["hour"] ?? 0
            byKey[wd * 24 + h] = HourlyBucket(
                weekday: wd, hour: h,
                costUSD: r["cost_usd"] ?? 0,
                tokens: Int((r["tokens"] as Double? ?? 0).rounded()),
                sampleCount: r["sample_count"] ?? 0
            )
        }
        var out: [HourlyBucket] = []
        out.reserveCapacity(168)
        for wd in 1...7 {
            for h in 0...23 {
                out.append(byKey[wd * 24 + h] ?? HourlyBucket(weekday: wd, hour: h, costUSD: 0, tokens: 0, sampleCount: 0))
            }
        }
        return out
    }

    /// Single bucket for `(weekday, hour)`. Returns a zero bucket when no row exists.
    public func hourlyBucket(weekday: Int, hour: Int) throws -> HourlyBucket {
        let row: Row? = try pool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT cost_usd, tokens, sample_count FROM hourly_buckets WHERE weekday = ? AND hour = ?",
                arguments: [weekday, hour]
            )
        }
        return HourlyBucket(
            weekday: weekday,
            hour: hour,
            costUSD: row?["cost_usd"] ?? 0,
            tokens: Int((row?["tokens"] as Double? ?? 0).rounded()),
            sampleCount: row?["sample_count"] ?? 0
        )
    }

    /// EWMA upsert. 7-day half-life decay applied to old (cost, tokens, sample_count)
    /// before adding the new event's contribution. Called inside the insertEvents
    /// transaction so a failed insert leaves no orphan bucket update.
    fileprivate static func upsertHourlyBucket(db: GRDB.Database, event: UsageEvent, cost: Double) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: event.timestamp)
        let hour = cal.component(.hour, from: event.timestamp)
        let nowTs = event.timestamp.timeIntervalSince1970
        let eventTokens = Double(event.inputTokens + event.outputTokens
                                 + event.cacheCreationTokens + event.cacheReadTokens)

        do {
            let prev = try Row.fetchOne(
                db,
                sql: "SELECT cost_usd, tokens, last_event_at, sample_count FROM hourly_buckets WHERE weekday = ? AND hour = ?",
                arguments: [weekday, hour]
            )
            let prevCost: Double = prev?["cost_usd"] ?? 0
            let prevToks: Double = prev?["tokens"] ?? 0
            let prevLast: Double = prev?["last_event_at"] ?? nowTs
            let prevCount: Double = prev?["sample_count"] ?? 0

            let elapsedDays = max(0, (nowTs - prevLast) / 86400.0)
            let decay = pow(0.5, elapsedDays / 7.0)

            try db.execute(sql: """
                INSERT INTO hourly_buckets (weekday, hour, cost_usd, tokens, last_event_at, sample_count)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(weekday, hour) DO UPDATE SET
                  cost_usd      = excluded.cost_usd,
                  tokens        = excluded.tokens,
                  last_event_at = excluded.last_event_at,
                  sample_count  = excluded.sample_count
                """,
                arguments: [
                    weekday, hour,
                    prevCost * decay + cost,
                    prevToks * decay + eventTokens,
                    nowTs,
                    prevCount * decay + 1.0,
                ]
            )
        } catch {
            // Hourly buckets are an aggregation; failure here must not abort the
            // primary event insert (which already succeeded above). Log via assert
            // in debug; in release the next event will heal the bucket.
            assertionFailure("hourly bucket upsert failed: \(error)")
        }
    }

    // MARK: - Test helpers (ADR-0015)

    /// Test-only: NULL out tools_json on every row matching sourceFile to simulate a
    /// pre-v4 (legacy) row that should fall back to primary_tool for attribution.
    func _eraseToolsJsonForTesting(sourceFile: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE events SET tools_json = NULL WHERE source_file = ?",
                arguments: [sourceFile]
            )
        }
    }

    /// Decoded tools array stored on the row matching (sourceFile, offset). nil when
    /// the column is NULL (legacy v1–v3 row) or no row matches. Internal — used by
    /// migration / roundtrip tests for tools_json.
    func toolsRaw(sourceFile: String, offset: UInt64) throws -> [String]? {
        try pool.read { db in
            let raw: String? = try String.fetchOne(
                db,
                sql: "SELECT tools_json FROM events WHERE source_file = ? AND source_offset = ?",
                arguments: [sourceFile, Int64(offset)]
            )
            guard let raw, let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
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
