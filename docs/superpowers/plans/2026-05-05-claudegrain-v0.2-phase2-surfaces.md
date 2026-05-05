# claudegrain v0.2 Phase 2 — Surfaces (Export + Popover Rewire)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Spec:** `docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md` §4.4 (B2), §4.1 UI integration (A1), §4.2 UI badge (A3), §4.3 Δ row (B3)

**Goal:** Land Phase 2 of v0.2 — wire Phase 1's data into the popover and ship CSV/JSON export. Released as `0.1.5-rc2`.

**Architecture:** Two parallel concerns. (1) `EventsExporter` (in `ClaudegrainCore`) reads `EventsDatabase` and writes CSV/JSON files via `NSSavePanel`. CSV/JSON headers carry a mandatory disclaimer (ADR-0007). (2) New SwiftUI components — `ForecastBadge`, `WeekDeltaRow`, `ModelMixRow` — rendered inside the existing V18 Phosphor Receipt layout in `DetailPanel.swift`. Localization extended for new strings. New keyboard shortcut `e` opens export sheet.

**Tech Stack:** Swift 5.9, SwiftPM, GRDB (existing), SwiftUI, Foundation `FileManager` for atomic writes, AppKit `NSSavePanel`.

**Branch:** `feat/v0.2/surfaces` (cut from `main` after Phase 1 merge).

**Predecessor commits to verify:** `60837a2 release: v0.1.4-rc1` on `main`.

---

## Pre-flight

### Task 0: Branch + baseline

**Files:** none modified

- [ ] **Step 1: Confirm branch + baseline tests**

```bash
git rev-parse --abbrev-ref HEAD                     # expect feat/v0.2/surfaces
git log --oneline -1                                # expect 60837a2 release: v0.1.4-rc1
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | tail -3
```

Expected: `Executed 66 tests, with 0 failures`. If not on `feat/v0.2/surfaces`, STOP.

---

## Section A: EventsExporter (B2)

### Task 1: ExportDimension + ExportFormat enums + EventsExporter scaffold

**Files:**
- Create: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Create: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore

final class EventsExporterTests: XCTestCase {
    func testEnumRawValues() {
        XCTAssertEqual(ExportDimension.perRepoDaily.rawValue,  "per-repo daily")
        XCTAssertEqual(ExportDimension.perToolDaily.rawValue,  "per-tool daily")
        XCTAssertEqual(ExportDimension.perModelDaily.rawValue, "per-model daily")
        XCTAssertEqual(ExportDimension.rawEvents.rawValue,     "raw events")
        XCTAssertEqual(ExportFormat.csv.rawValue,  "csv")
        XCTAssertEqual(ExportFormat.json.rawValue, "json")
    }

    func testExporterInit() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        _ = EventsExporter(db: db)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsExporterTests 2>&1 | tail -10
```

Expected: cannot find `ExportDimension`, `ExportFormat`, `EventsExporter`.

- [ ] **Step 3: Implement scaffold**

Create `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`:

```swift
import Foundation

public enum ExportDimension: String, CaseIterable, Sendable {
    case perRepoDaily   = "per-repo daily"
    case perToolDaily   = "per-tool daily"
    case perModelDaily  = "per-model daily"
    case rawEvents      = "raw events"
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case csv  = "csv"
    case json = "json"
}

/// Writes aggregated or raw events to disk. ADR-0007: every export carries
/// a disclaimer header noting primaryTool attribution + price-table estimate.
public struct EventsExporter: Sendable {
    private let db: EventsDatabase

    public init(db: EventsDatabase) {
        self.db = db
    }

    /// Writes the export to `url`. Range is half-open `[range.start, range.end)`.
    public func export(
        range: DateInterval,
        dimension: ExportDimension,
        format: ExportFormat,
        to url: URL
    ) async throws {
        let payload: String
        switch format {
        case .csv:  payload = try await csvPayload(range: range, dimension: dimension)
        case .json: payload = try await jsonPayload(range: range, dimension: dimension)
        }
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CSV

    private func csvPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        var out = csvHeader(range: range, dimension: dimension)
        // Filled in subsequent tasks per dimension.
        switch dimension {
        case .perRepoDaily, .perToolDaily, .perModelDaily, .rawEvents:
            out += "" // placeholder; per-dimension implementations land in Tasks 2-5
        }
        return out
    }

    private func csvHeader(range: DateInterval, dimension: ExportDimension) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return """
            # claudegrain export — primaryTool attribution, public price-table cost estimate.
            # Not the Anthropic billing source of truth. Generated \(Self.timestampNow()).
            # Range: \(formatter.string(from: range.start)) → \(formatter.string(from: range.end))  Dimension: \(dimension.rawValue)

            """
    }

    // MARK: - JSON

    private func jsonPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        // Filled in Task 6.
        return "{}"
    }

    static func timestampNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsExporterTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift Tests/ClaudegrainCoreTests/EventsExporterTests.swift
git commit -m "feat(core): EventsExporter scaffold + ExportDimension/Format enums"
```

---

### Task 2: per-repo-daily CSV export

**Files:**
- Modify: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift` (new aggregation if needed)
- Modify: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EventsExporterTests`:

```swift
    func testPerRepoDailyCSVHasDisclaimerHeaderAndRows() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        // Two events on same day in repo /a, one in repo /b
        let events = [
            UsageEvent(timestamp: now,                          sessionId: "s1", cwd: "/a",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 1_000_000, outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now.addingTimeInterval(60),   sessionId: "s2", cwd: "/a",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 500_000,   outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now,                          sessionId: "s3", cwd: "/b",
                       gitBranch: nil, model: "claude-opus-4-7", tools: [],
                       inputTokens: 200_000,   outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0),
        ]
        try await db.insertEvents(events, from: "/test.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).csv")
        let range = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600))

        try await exporter.export(range: range, dimension: .perRepoDaily, format: .csv, to: outURL)

        let csv = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("# claudegrain export"),                "missing disclaimer line")
        XCTAssertTrue(csv.contains("Not the Anthropic billing source"),    "missing accuracy disclaimer")
        XCTAssertTrue(csv.contains("Dimension: per-repo daily"),           "missing dimension annotation")
        XCTAssertTrue(csv.contains("date,repo,events,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd"),
                      "missing column header")
        // Repo /a should appear with sum of 2 events (1.5M input), repo /b with 1 event (200k input)
        XCTAssertTrue(csv.contains(",/a,2,1500000,"))
        XCTAssertTrue(csv.contains(",/b,1,200000,"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsExporterTests/testPerRepoDailyCSV 2>&1 | tail -10
```

Expected: assertion failures (placeholder body emits no rows).

- [ ] **Step 3: Implement per-repo-daily CSV**

In `EventsDatabase.swift`, add a new aggregation method (place near `costPerModel`):

```swift
    /// Per-(day, repo) aggregation over `[since, until)`. Day boundary is UTC midnight.
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
        return rows.map { r in
            (date: r["d"] ?? "",
             repo: r["repo"] ?? "",
             events: Int(r["n"] as Int64? ?? 0),
             input:  r["in_t"]  ?? 0,
             output: r["out_t"] ?? 0,
             cacheRead:     r["cr_t"] ?? 0,
             cacheCreation: r["cc_t"] ?? 0,
             cost: r["cost"]  ?? 0)
        }
    }
```

In `EventsExporter.swift`, replace the `csvPayload(range:dimension:)` per-repo branch:

```swift
    private func csvPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        var out = csvHeader(range: range, dimension: dimension)
        switch dimension {
        case .perRepoDaily:
            out += "date,repo,events,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd\n"
            let rows = try await db.perRepoDaily(since: range.start, until: range.end)
            for r in rows {
                out += "\(r.date),\(csvEscape(r.repo)),\(r.events),\(r.input),\(r.output),\(r.cacheRead),\(r.cacheCreation),\(String(format: "%.4f", r.cost))\n"
            }
        case .perToolDaily, .perModelDaily, .rawEvents:
            out += "" // landed in Tasks 3, 4, 5
        }
        return out
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsExporterTests 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsExporterTests.swift
git commit -m "feat(core): per-repo-daily CSV export"
```

---

### Task 3: per-tool-daily CSV export

**Files:**
- Modify: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write the failing test**

Append:

```swift
    func testPerToolDailyCSVGroupsByTool() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            UsageEvent(timestamp: now, sessionId: "s", cwd: "/a", gitBranch: nil,
                       model: "claude-opus-4-7", tools: ["Bash"],
                       inputTokens: 100, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now, sessionId: "s", cwd: "/a", gitBranch: nil,
                       model: "claude-opus-4-7", tools: ["Edit"],
                       inputTokens: 200, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
        ]
        try await db.insertEvents(events, from: "/test.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).csv")
        try await exporter.export(
            range: DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600)),
            dimension: .perToolDaily, format: .csv, to: outURL
        )

        let csv = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("Dimension: per-tool daily"))
        XCTAssertTrue(csv.contains("date,tool,events,input_tokens,output_tokens,cost_usd"))
        XCTAssertTrue(csv.contains(",Bash,1,100,"))
        XCTAssertTrue(csv.contains(",Edit,1,200,"))
    }
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter EventsExporterTests/testPerToolDailyCSV 2>&1 | tail -5
```

- [ ] **Step 3: Implement**

Append to `EventsDatabase.swift` (near `perRepoDaily`):

```swift
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
        return rows.map { r in
            (date: r["d"] ?? "",
             tool: r["tool"] ?? "",
             events: Int(r["n"] as Int64? ?? 0),
             input:  r["in_t"]  ?? 0,
             output: r["out_t"] ?? 0,
             cost: r["cost"]   ?? 0)
        }
    }
```

In `EventsExporter.swift`, extend the `case .perToolDaily` branch:

```swift
        case .perToolDaily:
            out += "date,tool,events,input_tokens,output_tokens,cost_usd\n"
            let rows = try await db.perToolDaily(since: range.start, until: range.end)
            for r in rows {
                out += "\(r.date),\(csvEscape(r.tool)),\(r.events),\(r.input),\(r.output),\(String(format: "%.4f", r.cost))\n"
            }
```

- [ ] **Step 4: Run — expect pass**

```bash
swift test --filter EventsExporterTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsExporterTests.swift
git commit -m "feat(core): per-tool-daily CSV export"
```

---

### Task 4: per-model-daily CSV export

**Files:**
- Modify: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
    func testPerModelDailyCSV() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let events = [
            UsageEvent(timestamp: now, sessionId: "s", cwd: "/a", gitBranch: nil,
                       model: "claude-opus-4-7", tools: [],
                       inputTokens: 100, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            UsageEvent(timestamp: now, sessionId: "s", cwd: "/a", gitBranch: nil,
                       model: "claude-sonnet-4-6", tools: [],
                       inputTokens: 500, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
        ]
        try await db.insertEvents(events, from: "/test.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).csv")
        try await exporter.export(
            range: DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600)),
            dimension: .perModelDaily, format: .csv, to: outURL
        )

        let csv = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("Dimension: per-model daily"))
        XCTAssertTrue(csv.contains("date,model_family,model_id,events,input_tokens,output_tokens,cost_usd"))
        XCTAssertTrue(csv.contains(",opus,claude-opus-4-7,1,100,"))
        XCTAssertTrue(csv.contains(",sonnet,claude-sonnet-4-6,1,500,"))
    }
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

In `EventsDatabase.swift`:

```swift
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
        return rows.map { r in
            (date: r["d"] ?? "",
             modelId: r["m"] ?? "",
             events: Int(r["n"] as Int64? ?? 0),
             input:  r["in_t"] ?? 0,
             output: r["out_t"] ?? 0,
             cost: r["cost"] ?? 0)
        }
    }
```

In `EventsExporter.swift`:

```swift
        case .perModelDaily:
            out += "date,model_family,model_id,events,input_tokens,output_tokens,cost_usd\n"
            let rows = try await db.perModelDaily(since: range.start, until: range.end)
            for r in rows {
                let fam = ModelFamily.parse(r.modelId)
                let famStr = String(describing: fam)   // "opus" / "sonnet" / "haiku" / "unknown"
                out += "\(r.date),\(famStr),\(csvEscape(r.modelId)),\(r.events),\(r.input),\(r.output),\(String(format: "%.4f", r.cost))\n"
            }
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(core): per-model-daily CSV export"
```

---

### Task 5: raw-events CSV export

**Files:**
- Modify: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
    func testRawEventsCSV() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let event = UsageEvent(
            timestamp: now, sessionId: "sess-1", cwd: "/a", gitBranch: "main",
            model: "claude-opus-4-7", tools: ["Bash"],
            inputTokens: 100, outputTokens: 200,
            cacheCreationTokens: 1000, cacheReadTokens: 5000
        )
        try await db.insertEvents([event], from: "/x.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).csv")
        try await exporter.export(
            range: DateInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60)),
            dimension: .rawEvents, format: .csv, to: outURL
        )

        let csv = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("Dimension: raw events"))
        XCTAssertTrue(csv.contains("timestamp,session_id,repo,git_branch,model,primary_tool,input_tokens,output_tokens,cache_creation_tokens,cache_read_tokens,cost_usd"))
        XCTAssertTrue(csv.contains(",sess-1,/a,main,claude-opus-4-7,Bash,100,200,1000,5000,"))
    }
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

In `EventsDatabase.swift`:

```swift
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
```

In `EventsExporter.swift`:

```swift
        case .rawEvents:
            out += "timestamp,session_id,repo,git_branch,model,primary_tool,input_tokens,output_tokens,cache_creation_tokens,cache_read_tokens,cost_usd\n"
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let rows = try await db.rawEventsInRange(since: range.start, until: range.end)
            for r in rows {
                let ts: Date = r["ts"] ?? Date()
                out += [
                    iso.string(from: ts),
                    csvEscape(r["session_id"]    ?? ""),
                    csvEscape(r["cwd"]           ?? ""),
                    csvEscape(r["git_branch"]    ?? ""),
                    csvEscape(r["model"]         ?? ""),
                    csvEscape(r["primary_tool"]  ?? ""),
                    String((r["in_tok"]           as Int64?) ?? 0),
                    String((r["out_tok"]          as Int64?) ?? 0),
                    String((r["cache_create_tok"] as Int64?) ?? 0),
                    String((r["cache_read_tok"]   as Int64?) ?? 0),
                    String(format: "%.4f", (r["cost_usd"] as Double?) ?? 0),
                ].joined(separator: ",") + "\n"
            }
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(core): raw-events CSV export"
```

---

### Task 6: JSON export for all 4 dimensions

**Files:**
- Modify: `Sources/ClaudegrainCore/ExportLayer/EventsExporter.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsExporterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
    func testJSONExportEnvelopeAndPerRepoData() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let event = UsageEvent(
            timestamp: now, sessionId: "s", cwd: "/a", gitBranch: nil,
            model: "claude-opus-4-7", tools: [],
            inputTokens: 100, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        try await db.insertEvents([event], from: "/x.jsonl", startingAt: 0, cursor: JSONLReader.Cursor())

        let exporter = EventsExporter(db: db)
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).json")
        try await exporter.export(
            range: DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600)),
            dimension: .perRepoDaily, format: .json, to: outURL
        )

        let data = try Data(contentsOf: outURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let meta = try XCTUnwrap(json["_meta"] as? [String: Any])
        XCTAssertEqual(meta["attribution"]    as? String, "primaryTool")
        XCTAssertEqual(meta["dimension"]      as? String, "per-repo daily")
        XCTAssertEqual(meta["disclaimer"]     as? String, "Public price-table cost estimate. Not the Anthropic billing source of truth.")
        XCTAssertNotNil(meta["generated_at"])
        XCTAssertNotNil(meta["range"])
        let rows = try XCTUnwrap(json["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["repo"] as? String, "/a")
        XCTAssertEqual(rows[0]["events"] as? Int, 1)
    }
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Replace `jsonPayload(...)` in `EventsExporter.swift`:

```swift
    private func jsonPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let meta: [String: Any] = [
            "tool":         "claudegrain",
            "attribution":  "primaryTool",
            "disclaimer":   "Public price-table cost estimate. Not the Anthropic billing source of truth.",
            "generated_at": iso.string(from: Date()),
            "range": [
                "start": iso.string(from: range.start),
                "end":   iso.string(from: range.end),
            ],
            "dimension":    dimension.rawValue,
        ]
        let rows: [[String: Any]] = try await jsonRows(range: range, dimension: dimension)
        let body: [String: Any] = ["_meta": meta, "rows": rows]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonRows(range: DateInterval, dimension: ExportDimension) async throws -> [[String: Any]] {
        switch dimension {
        case .perRepoDaily:
            return try await db.perRepoDaily(since: range.start, until: range.end).map {
                [
                    "date": $0.date, "repo": $0.repo, "events": $0.events,
                    "input_tokens": $0.input, "output_tokens": $0.output,
                    "cache_read_tokens": $0.cacheRead, "cache_creation_tokens": $0.cacheCreation,
                    "cost_usd": $0.cost,
                ]
            }
        case .perToolDaily:
            return try await db.perToolDaily(since: range.start, until: range.end).map {
                [
                    "date": $0.date, "tool": $0.tool, "events": $0.events,
                    "input_tokens": $0.input, "output_tokens": $0.output, "cost_usd": $0.cost,
                ]
            }
        case .perModelDaily:
            return try await db.perModelDaily(since: range.start, until: range.end).map {
                let fam = ModelFamily.parse($0.modelId)
                return [
                    "date": $0.date, "model_family": String(describing: fam),
                    "model_id": $0.modelId, "events": $0.events,
                    "input_tokens": $0.input, "output_tokens": $0.output, "cost_usd": $0.cost,
                ]
            }
        case .rawEvents:
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return try await db.rawEventsInRange(since: range.start, until: range.end).map { (r: Row) -> [String: Any] in
                let ts: Date = r["ts"] ?? Date()
                return [
                    "timestamp":  iso.string(from: ts),
                    "session_id": (r["session_id"]   ?? "") as String,
                    "repo":       (r["cwd"]          ?? "") as String,
                    "git_branch": (r["git_branch"]   ?? "") as String,
                    "model":      (r["model"]        ?? "") as String,
                    "primary_tool": (r["primary_tool"] ?? "") as String,
                    "input_tokens":  (r["in_tok"]            as Int64?) ?? 0,
                    "output_tokens": (r["out_tok"]           as Int64?) ?? 0,
                    "cache_creation_tokens": (r["cache_create_tok"] as Int64?) ?? 0,
                    "cache_read_tokens":     (r["cache_read_tok"]   as Int64?) ?? 0,
                    "cost_usd":   (r["cost_usd"]     as Double?) ?? 0,
                ]
            }
        }
    }
```

- [ ] **Step 4: Run — expect pass**

```bash
swift test --filter EventsExporterTests 2>&1 | tail -5
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(core): JSON export envelope + per-dimension data"
```

---

## Section B: Localization additions

### Task 7: New L keys + EN/ZH translations

**Files:**
- Modify: `Sources/ClaudegrainApp/Localization.swift`

- [ ] **Step 1: Add new keys + translations**

In `Sources/ClaudegrainApp/Localization.swift`, append to the `enum L` (after `case footerEndEvents`):

```swift
    // v0.2 — forecast badge
    case forecastBlockHits        // "block hits %@"
    case forecastBlockSafe        // "block · safe"
    case forecastWeeklyHits       // "weekly hits %@"
    case forecastConfidenceLow    // "low conf"
    case forecastConfidenceMedium // "medium"
    case forecastConfidenceHigh   // "high"
    case forecastBasisEwma        // "ewma"
    case forecastBasisLinear      // "linear"

    // v0.2 — week delta row
    case weekDeltaLabel           // "Δ vs last week"
    case weekDeltaPctUp           // "+%d%% · cache %@"
    case weekDeltaPctDown         // "%d%% · cache %@"  (negative pct)
    case weekDeltaCacheUp         // "+%d pp"
    case weekDeltaCacheDown       // "%d pp"
    case weekDeltaFirstWeek       // "first week"

    // v0.2 — model mix
    case modelMixLabel            // "MODELS"
    case modelMixOpus             // "opus"
    case modelMixSonnet           // "sonnet"
    case modelMixHaiku            // "haiku"
    case modelMixUnknown          // "other"

    // v0.2 — export
    case exportMenuItem           // "Export Usage…"
    case exportSheetTitle         // "Export usage data"
    case exportRangeLabel         // "Range"
    case exportRangeToday
    case exportRangeLast7d
    case exportRangeLast30d
    case exportRangeThisWeek
    case exportRangeLastWeek
    case exportRangeCustom
    case exportDimensionLabel
    case exportDimRepoDaily
    case exportDimToolDaily
    case exportDimModelDaily
    case exportDimRaw
    case exportFormatLabel
    case exportButton             // "Export…"
    case exportCancel             // "Cancel"
    case exportDone               // "Saved to %@"

    // v0.2 — kbd
    case kbExport                 // "export"
```

Then extend the `en` and `zh` dictionaries with corresponding entries. **Read the existing dictionary entries to copy the style** (no trailing periods, casing matches surrounding context). EN entries should use the literal English from comments above; ZH entries use natural Chinese.

EN additions:

```swift
        .forecastBlockHits:        "block hits %@",
        .forecastBlockSafe:        "block · safe",
        .forecastWeeklyHits:       "weekly hits %@",
        .forecastConfidenceLow:    "low conf",
        .forecastConfidenceMedium: "medium",
        .forecastConfidenceHigh:   "high",
        .forecastBasisEwma:        "ewma",
        .forecastBasisLinear:      "linear",
        .weekDeltaLabel:           "Δ vs last week",
        .weekDeltaPctUp:           "+%d%% · cache %@",
        .weekDeltaPctDown:         "%d%% · cache %@",
        .weekDeltaCacheUp:         "+%d pp",
        .weekDeltaCacheDown:       "%d pp",
        .weekDeltaFirstWeek:       "first week",
        .modelMixLabel:            "MODELS",
        .modelMixOpus:             "opus",
        .modelMixSonnet:           "sonnet",
        .modelMixHaiku:            "haiku",
        .modelMixUnknown:          "other",
        .exportMenuItem:           "Export Usage…",
        .exportSheetTitle:         "Export usage data",
        .exportRangeLabel:         "Range",
        .exportRangeToday:         "Today",
        .exportRangeLast7d:        "Last 7 days",
        .exportRangeLast30d:       "Last 30 days",
        .exportRangeThisWeek:      "This week",
        .exportRangeLastWeek:      "Last week",
        .exportRangeCustom:        "Custom…",
        .exportDimensionLabel:     "Dimension",
        .exportDimRepoDaily:       "Per-repo · daily",
        .exportDimToolDaily:       "Per-tool · daily",
        .exportDimModelDaily:      "Per-model · daily",
        .exportDimRaw:             "Raw events",
        .exportFormatLabel:        "Format",
        .exportButton:             "Export…",
        .exportCancel:             "Cancel",
        .exportDone:               "Saved to %@",
        .kbExport:                 "export",
```

ZH additions:

```swift
        .forecastBlockHits:        "块预计 %@ 触顶",
        .forecastBlockSafe:        "块 · 安全",
        .forecastWeeklyHits:       "本周预计 %@ 触顶",
        .forecastConfidenceLow:    "低信心",
        .forecastConfidenceMedium: "中等",
        .forecastConfidenceHigh:   "高信心",
        .forecastBasisEwma:        "EWMA",
        .forecastBasisLinear:      "线性",
        .weekDeltaLabel:           "Δ 对比上周",
        .weekDeltaPctUp:           "+%d%% · 缓存 %@",
        .weekDeltaPctDown:         "%d%% · 缓存 %@",
        .weekDeltaCacheUp:         "+%d pp",
        .weekDeltaCacheDown:       "%d pp",
        .weekDeltaFirstWeek:       "首周",
        .modelMixLabel:            "模型分布",
        .modelMixOpus:             "opus",
        .modelMixSonnet:           "sonnet",
        .modelMixHaiku:            "haiku",
        .modelMixUnknown:          "其他",
        .exportMenuItem:           "导出用量…",
        .exportSheetTitle:         "导出用量数据",
        .exportRangeLabel:         "时间范围",
        .exportRangeToday:         "今日",
        .exportRangeLast7d:        "近 7 天",
        .exportRangeLast30d:       "近 30 天",
        .exportRangeThisWeek:      "本周",
        .exportRangeLastWeek:      "上周",
        .exportRangeCustom:        "自定义…",
        .exportDimensionLabel:     "维度",
        .exportDimRepoDaily:       "按仓库 · 日",
        .exportDimToolDaily:       "按工具 · 日",
        .exportDimModelDaily:      "按模型 · 日",
        .exportDimRaw:             "原始事件",
        .exportFormatLabel:        "格式",
        .exportButton:             "导出…",
        .exportCancel:             "取消",
        .exportDone:               "已保存到 %@",
        .kbExport:                 "导出",
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/Localization.swift
git commit -m "feat(app): localization keys for v0.2 forecast/Δ/mix/export"
```

---

## Section C: New SwiftUI components

### Task 8: ForecastBadge view

**Files:**
- Create: `Sources/ClaudegrainApp/ReceiptComponents/ForecastBadge.swift`
- Modify: `Sources/ClaudegrainApp/ReceiptComponents.swift` (move existing code into the new directory? OR keep monolithic?)

> **Note**: The existing `ReceiptComponents.swift` is 296 lines with multiple components inline. Don't restructure — add the new component as a sibling file. SwiftPM target picks up files automatically.

- [ ] **Step 1: Implement (no test — UI components are smoke-tested manually in Phase 2; the data layer underneath is already covered by Phase 1 ForecasterTests)**

Create `Sources/ClaudegrainApp/ReceiptComponents/ForecastBadge.swift`:

> Wait — `Sources/ClaudegrainApp/ReceiptComponents.swift` is a single file, not a directory. Don't try to introduce a `ReceiptComponents/` subdirectory under `Sources/ClaudegrainApp/` because that would break SwiftPM's discovery of `ReceiptComponents.swift`. Instead create a new sibling file:

Create `Sources/ClaudegrainApp/ForecastBadge.swift`:

```swift
import SwiftUI
import ClaudegrainCore

/// One-line forecast indicator next to the hero number. Shows ETA + basis + confidence.
/// Hidden when forecast is nil or basis == .insufficient.
struct ForecastBadge: View {
    let forecast: ForecastResult?
    let labelKey: L          // .forecastBlockHits or .forecastWeeklyHits
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let f = forecast, f.basis != .insufficient {
            HStack(spacing: 5) {
                Text(f.willHit ? "⏱" : "✓")
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(f.willHit ? 1.0 : 0.5))
                Text(f.willHit ? formattedHitText(f) : safeText(f))
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.85))
                Text("·")
                    .font(.cgMonoXSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.4))
                Text(basisLabel(f) + " · " + confLabel(f))
                    .font(.cgMonoXSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.55))
            }
        } else {
            EmptyView()
        }
    }

    private func formattedHitText(_ f: ForecastResult) -> String {
        guard let hit = f.hitAt else { return "" }
        let mins = Int(hit.timeIntervalSinceNow / 60)
        let suffix: String
        if mins >= 60 { suffix = "\(mins/60)h \(mins%60)m" }
        else          { suffix = "\(max(mins, 0))m" }
        return String(format: model.t(labelKey), suffix)
    }

    private func safeText(_ f: ForecastResult) -> String {
        let key: L = (labelKey == .forecastBlockHits) ? .forecastBlockSafe : .forecastBlockSafe
        return model.t(key)
    }

    private func basisLabel(_ f: ForecastResult) -> String {
        switch f.basis {
        case .ewma:         return model.t(.forecastBasisEwma)
        case .linear:       return model.t(.forecastBasisLinear)
        case .insufficient: return ""
        }
    }

    private func confLabel(_ f: ForecastResult) -> String {
        switch f.confidence {
        case .low:    return model.t(.forecastConfidenceLow)
        case .medium: return model.t(.forecastConfidenceMedium)
        case .high:   return model.t(.forecastConfidenceHigh)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/ForecastBadge.swift
git commit -m "feat(app): ForecastBadge view (A3 UI integration)"
```

---

### Task 9: WeekDeltaRow view

**Files:**
- Create: `Sources/ClaudegrainApp/WeekDeltaRow.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import ClaudegrainCore

/// Single-line "Δ vs last week" mini row. Renders nothing on first week (lastWeekCost == 0).
struct WeekDeltaRow: View {
    let delta: WeekDelta?
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(model.t(.weekDeltaLabel))
                .font(.cgMonoXSmall)
                .tracking(1.4)
                .foregroundStyle(theme.ink.opacity(0.55))
            Spacer()
            Text(deltaText)
                .font(.cgMonoSmall)
                .foregroundStyle(deltaColor)
        }
    }

    private var deltaText: String {
        guard let d = delta else { return "—" }
        guard let pct = d.pctChange else { return model.t(.weekDeltaFirstWeek) }
        let pctInt = Int((pct * 100).rounded())
        let cachePP = Int((d.cacheHitDelta * 100).rounded())
        let cacheStr = cachePP >= 0
            ? String(format: model.t(.weekDeltaCacheUp), cachePP)
            : String(format: model.t(.weekDeltaCacheDown), cachePP)
        if pctInt >= 0 {
            return String(format: model.t(.weekDeltaPctUp), pctInt, cacheStr)
        } else {
            return String(format: model.t(.weekDeltaPctDown), pctInt, cacheStr)
        }
    }

    private var deltaColor: Color {
        guard let pct = delta?.pctChange else { return theme.ink.opacity(0.7) }
        // Up = warmer (more spend = warning), down = cool (saved $).
        return pct > 0 ? theme.warn : theme.inkBold
    }
}
```

- [ ] **Step 2: Verify build**

If the project's `Theme` doesn't expose `.warn`, use `.inkBold` for both branches and document it as a follow-up.

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/WeekDeltaRow.swift
git commit -m "feat(app): WeekDeltaRow view (B3 UI integration)"
```

---

### Task 10: ModelMixRow view

**Files:**
- Create: `Sources/ClaudegrainApp/ModelMixRow.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import ClaudegrainCore

/// Stacked-bar one-liner: "MODELS · opus 64% · sonnet 31% · haiku 5%"
/// Hidden when modelMix is empty.
struct ModelMixRow: View {
    let mix: [ModelFamily: Double]
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !mix.isEmpty {
            HStack(spacing: 8) {
                Text(model.t(.modelMixLabel))
                    .font(.cgMonoXSmall)
                    .tracking(1.6)
                    .foregroundStyle(theme.ink.opacity(0.55))
                Text(mixDescription)
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.85))
                Spacer()
            }
        } else {
            EmptyView()
        }
    }

    private var mixDescription: String {
        let order: [ModelFamily] = [.opus, .sonnet, .haiku, .unknown]
        let parts = order.compactMap { fam -> String? in
            guard let pct = mix[fam], pct > 0.005 else { return nil }
            let pctInt = Int((pct * 100).rounded())
            let label: String
            switch fam {
            case .opus:    label = model.t(.modelMixOpus)
            case .sonnet:  label = model.t(.modelMixSonnet)
            case .haiku:   label = model.t(.modelMixHaiku)
            case .unknown: label = model.t(.modelMixUnknown)
            }
            return "\(label) \(pctInt)%"
        }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Verify build**

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/ModelMixRow.swift
git commit -m "feat(app): ModelMixRow view (A1 UI integration)"
```

---

## Section D: DetailPanel integration

### Task 11: Wire ForecastBadge / WeekDeltaRow / ModelMixRow into ReceiptBody

**Files:**
- Modify: `Sources/ClaudegrainApp/DetailPanel.swift`

- [ ] **Step 1: Insert components into the existing `ReceiptBody.body` VStack**

Read the current `ReceiptBody.body` first to confirm structure (it has HeaderStrip, DoubleDivider, HeroSpend, DashedDivider, USAGE LIMITS section, etc.).

Add to `ReceiptBody.body` per the spec §6 layout:
- ForecastBadge after the HeroSpend (visually grouped with the hero metric)
- WeekDeltaRow between HeroSpend (and its forecast badge) and the USAGE LIMITS DashedDivider
- ModelMixRow between the SectionTopCosts and the DoubleDivider preceding subtotals

Concretely, modify `ReceiptBody.body`:

```swift
            HeroSpend(yesterdayCost: 7.5)
            // NEW: forecast badge for the 5h block (rendered below hero)
            if model.forecastBlock?.basis != .insufficient {
                ForecastBadge(forecast: model.forecastBlock, labelKey: .forecastBlockHits)
                    .padding(.top, 2)
            }

            DashedDivider()

            // NEW: week delta row (B3)
            WeekDeltaRow(delta: model.weekDelta)
            DashedDivider()

            SectionHeader(label: model.t(.sectionUsageLimits))
            // ...existing VitalRow block stays...

            // ...existing 7d chart + Top Costs sections stay...

            SectionHeader(label: model.t(.sectionTopCosts))
            TopCostsList()

            // NEW: model mix row (A1) before the subtotals section
            DashedDivider()
            ModelMixRow(mix: model.modelMix)

            DoubleDivider()
            // ...rest unchanged
```

The exact insertion lines should match the existing `ReceiptBody.body` structure — read it before editing to get the right anchors.

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 3: Smoke-test (manual, can't be unit tested without spinning up the app)**

```bash
swift run claudegrain &
sleep 3
# Click the menu bar item — verify popover renders the new rows + badge
# Then quit:
pkill claudegrain || true
```

This is a smoke check only. Don't insist on perfect smoke output — the test suite verifies data, the human verifies pixels.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudegrainApp/DetailPanel.swift
git commit -m "feat(app): wire ForecastBadge/WeekDeltaRow/ModelMixRow into popover"
```

---

## Section E: Export sheet + menu integration

### Task 12: ExportSheet SwiftUI view

**Files:**
- Create: `Sources/ClaudegrainApp/ExportSheet.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import AppKit
import ClaudegrainCore
import UniformTypeIdentifiers

@MainActor
final class ExportSheetCoordinator: ObservableObject {
    @Published var range: RangePreset = .last7d
    @Published var dimension: ExportDimension = .perRepoDaily
    @Published var format: ExportFormat = .csv
    @Published var status: String?    // last status / error text

    private let exporter: EventsExporter
    init(exporter: EventsExporter) { self.exporter = exporter }

    enum RangePreset: String, CaseIterable, Identifiable {
        case today, last7d, last30d, thisWeek, lastWeek
        var id: String { rawValue }
        func interval(now: Date = Date()) -> DateInterval {
            let cal = Calendar.current
            switch self {
            case .today:    return DateInterval(start: cal.startOfDay(for: now), end: now)
            case .last7d:   return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
            case .last30d:  return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
            case .thisWeek: return DateInterval(start: WeekDelta.mondayUTC(of: now), end: now)
            case .lastWeek:
                let thisStart = WeekDelta.mondayUTC(of: now)
                let lastStart = thisStart.addingTimeInterval(-7 * 86_400)
                return DateInterval(start: lastStart, end: thisStart)
            }
        }
    }

    func runExport() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .csv
            ? [UTType.commaSeparatedText]
            : [UTType.json]
        panel.nameFieldStringValue = "claudegrain-\(suggestedName()).\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await exporter.export(
                range: range.interval(),
                dimension: dimension,
                format: format,
                to: url
            )
            status = "Saved to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func suggestedName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "\(f.string(from: Date()))-\(dimension.rawValue.replacingOccurrences(of: " ", with: "-"))"
    }
}

struct ExportSheet: View {
    @StateObject var coord: ExportSheetCoordinator
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t(.exportSheetTitle))
                .font(.headline)

            HStack {
                Text(model.t(.exportRangeLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.range) {
                    Text(model.t(.exportRangeToday)).tag(ExportSheetCoordinator.RangePreset.today)
                    Text(model.t(.exportRangeLast7d)).tag(ExportSheetCoordinator.RangePreset.last7d)
                    Text(model.t(.exportRangeLast30d)).tag(ExportSheetCoordinator.RangePreset.last30d)
                    Text(model.t(.exportRangeThisWeek)).tag(ExportSheetCoordinator.RangePreset.thisWeek)
                    Text(model.t(.exportRangeLastWeek)).tag(ExportSheetCoordinator.RangePreset.lastWeek)
                }
                .labelsHidden()
            }

            HStack {
                Text(model.t(.exportDimensionLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.dimension) {
                    Text(model.t(.exportDimRepoDaily)).tag(ExportDimension.perRepoDaily)
                    Text(model.t(.exportDimToolDaily)).tag(ExportDimension.perToolDaily)
                    Text(model.t(.exportDimModelDaily)).tag(ExportDimension.perModelDaily)
                    Text(model.t(.exportDimRaw)).tag(ExportDimension.rawEvents)
                }
                .labelsHidden()
            }

            HStack {
                Text(model.t(.exportFormatLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.format) {
                    Text("CSV").tag(ExportFormat.csv)
                    Text("JSON").tag(ExportFormat.json)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            if let status = coord.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(model.t(.exportCancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.t(.exportButton)) {
                    Task { await coord.runExport() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```

If `WeekDelta.mondayUTC` isn't `public`, expose it (one-line fix). It's currently `public static` per Phase 1 — should be fine.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/ExportSheet.swift
git commit -m "feat(app): ExportSheet UI with NSSavePanel"
```

---

### Task 13: Menubar dropdown item + key 'e' export shortcut

**Files:**
- Modify: `Sources/ClaudegrainApp/StatusItemController.swift`
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift` (expose exporter)
- Modify: `Sources/ClaudegrainApp/AppModel.swift` (handle `e` key from popover)

- [ ] **Step 1: Expose exporter on AppCoordinator**

Add to `AppCoordinator.swift`:

```swift
    let exporter: EventsExporter

    // …in init, after `self.db = …`:
    self.exporter = EventsExporter(db: db)
```

- [ ] **Step 2: Wire menu item**

Read `StatusItemController.swift` to find the menu setup. Add a new menu item that opens the export sheet. The exact insertion point is wherever the existing "Settings…" menu item is added. New item label: `model.t(.exportMenuItem)`.

The menu action should call a new `AppCoordinator.openExportSheet()` method that creates a SwiftUI `NSHostingView(rootView: ExportSheet(coord: …))` and shows it in a panel window.

(If the existing menu pattern uses `NSMenu` directly, follow it. Don't restructure.)

- [ ] **Step 3: Wire key handler in DetailPanel**

In `DetailPanel.swift`, find the existing keyboard shortcut wiring. Add a new key:

```swift
                .onKeyPress("e") {
                    // Open export sheet via coordinator
                    return .handled
                }
```

The exact callback path depends on existing infrastructure — read the existing key handler first.

- [ ] **Step 4: Verify build**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(app): export menu item + 'e' keyboard shortcut"
```

---

## Section F: ADR + release

### Task 14: ADR-0007 (export disclaimer)

**Files:**
- Create: `docs/adr/0007-export-disclaimer.md`

- [ ] **Step 1: Write ADR**

```markdown
# Export disclaimer in CSV/JSON output

## Status

accepted

## Context

B2 ships CSV/JSON export so users can take their usage data to
spreadsheets, accountants, internal cost dashboards. The data is:

1. Cost-attributed via the **primaryTool** strategy (ADR-0003): a
   turn's tokens get billed to its first `tool_use` block, not split
   per tool.
2. Cost-priced via a **public LiteLLM-derived price catalog**, not the
   user's actual Anthropic invoice. Discounted enterprise rates,
   credits, and beta pricing are not reflected.

Either of these is enough to make a reimbursement-claim spreadsheet
mismatch the Anthropic billing portal. We've already had test reports
where users paste claudegrain numbers into expense reports and finance
flags the discrepancy.

## Decision

Every export, regardless of dimension or format, MUST carry a
machine-readable disclaimer:

- **CSV**: three `# `-prefixed comment lines as the first lines of the
  file. SQL importers and spreadsheets either skip these (`#` comment
  conventions in `psql`/Excel-import wizards) or expose them as the
  first row of values where the user can see them.
- **JSON**: a top-level `_meta` object containing `attribution`,
  `disclaimer`, `generated_at`, `range`, and `dimension` fields.

The disclaimer text is fixed:

```
claudegrain export — primaryTool attribution, public price-table cost estimate.
Not the Anthropic billing source of truth.
```

## Considered options

- **Show the disclaimer only in the UI sheet** — gets stripped when
  data leaves claudegrain. Defeats the purpose.
- **Watermark each row** — too noisy, breaks pivot tables.
- **Skip the disclaimer for raw events** — raw events are the most
  compelling reimbursement evidence and the most likely to mismatch.
  All dimensions need it.

## Consequences

- A spreadsheet user opening the CSV will see the comment lines as the
  first row of values (Excel, Numbers). That's intentional —
  prominence > strict CSV cleanliness.
- JSON consumers parse `_meta` first; if a tool ignores it, they at
  least had it.
- Future CSV consumers need to know to skip the leading `#` lines. We
  don't add a "skip-line count" field — the convention is broadly
  understood and adding metadata about the metadata is over-engineering.
```

- [ ] **Step 2: Commit**

```bash
git add docs/adr/0007-export-disclaimer.md
git commit -m "docs(adr): 0007 export-disclaimer"
```

---

### Task 15: VERSION + CHANGELOG bump, full test, tag rc2

**Files:**
- Modify: `VERSION`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: VERSION = `0.1.5-rc2`**

- [ ] **Step 2: CHANGELOG entry, inserted above `[0.1.4-rc1]`**

```markdown
## [0.1.5-rc2] — 2026-05-05

Phase 2 of v0.2 — surfaces. Wires Phase 1's data into the popover and
ships CSV/JSON export.

### Added
- CSV/JSON export in 4 dimensions: per-repo daily, per-tool daily,
  per-model daily, raw events. Mandatory disclaimer header (ADR-0007).
- `ForecastBadge` on the popover hero — block / weekly hit-time
  prediction with confidence + basis annotation.
- `WeekDeltaRow` — "Δ vs last week" mini row with cost % change and
  cache-hit percentage-point delta.
- `ModelMixRow` — Opus/Sonnet/Haiku attribution bar.
- "Export Usage…" menu item + `e` keyboard shortcut.
- Localization for all new UI strings (EN + ZH).

### Changed
- `EventsDatabase` adds `perRepoDaily` / `perToolDaily` /
  `perModelDaily` / `rawEventsInRange` aggregations for export.

### Docs
- ADR-0007 — export disclaimer.
```

- [ ] **Step 3: Full test suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | tail -5
```

Expected: ~72 tests pass (Phase 1's 66 + ~6 export tests).

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION CHANGELOG.md
git commit -m "release: v0.1.5-rc2 (phase 2 — surfaces)"
git tag v0.1.5-rc2
```

- [ ] **Step 5: Push + PR**

```bash
git push -u origin feat/v0.2/surfaces
git push origin v0.1.5-rc2
gh pr create --base main --head feat/v0.2/surfaces \
  --title "feat(v0.2 phase 2): surfaces — export + popover rewire" \
  --body "$(cat <<'EOF'
## Summary

Phase 2 wires Phase 1's data into the popover and ships CSV/JSON export.

- **B2** — CSV/JSON export, 4 dimensions, ADR-0007 disclaimer header
- **A3 UI** — ForecastBadge on hero
- **B3 UI** — WeekDeltaRow
- **A1 UI** — ModelMixRow
- New menu item "Export Usage…" + `e` keyboard shortcut
- EN/ZH translations for all new UI strings

ADR: [0007 export-disclaimer](docs/adr/0007-export-disclaimer.md)

Spec: [`docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md`](docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md) §4.4, §4.1/4.2/4.3 UI integration
Plan: [`docs/superpowers/plans/2026-05-05-claudegrain-v0.2-phase2-surfaces.md`](docs/superpowers/plans/2026-05-05-claudegrain-v0.2-phase2-surfaces.md)

## Test plan

- [x] `swift test` green
- [ ] Manual: `swift run claudegrain` shows new rows + badge
- [ ] Manual: menu → Export Usage… → CSV opens cleanly in Numbers
- [ ] Manual: 'e' keyboard shortcut opens export sheet
EOF
)"
```

---

## Self-Review (run before merging)

**Spec coverage:**
- §4.4 B2 export — 4 dimensions × 2 formats ✓ (Tasks 1-6), disclaimer ✓ (Tasks 1, 14)
- §4.1 A1 UI — ModelMixRow ✓ (Task 10) wired ✓ (Task 11)
- §4.2 A3 UI — ForecastBadge ✓ (Task 8) wired ✓ (Task 11)
- §4.3 B3 UI — WeekDeltaRow ✓ (Task 9) wired ✓ (Task 11)
- §6 layout — popover rewire ✓ (Task 11)
- ADR-0007 ✓ (Task 14)
- Localization ✓ (Task 7)
- 'e' kbd shortcut + menu item ✓ (Task 13)

**Placeholder scan:** No "TBD"/"TODO" markers. Each task contains exact code or commands.

**Type consistency:**
- `ExportDimension` / `ExportFormat` — same raw values across all tasks
- `EventsExporter.export(range:dimension:format:to:)` — same signature throughout
- `ForecastResult` / `ForecastResult.Confidence` / `Basis` — re-used from Phase 1 unchanged
- `WeekDelta` / `ModelFamily` — re-used unchanged
- New aggregations on `EventsDatabase`: `perRepoDaily`, `perToolDaily`, `perModelDaily`, `rawEventsInRange` — consistent throws style with Phase 1 neighbors

---

## Execution handoff

Plan saved. Phase 3 (control: C1-C4), Phase 4 (widget: D), Phase 5 (polish: E) plans will be written when Phase 2 lands.
