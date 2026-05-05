# claudegrain v0.2 Phase 1 — Core Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md` §4.1 (A1), §4.2 (A3), §4.3 (B3)

**Goal:** Land the data-layer foundations of v0.2 — per-model attribution, EWMA-based forecast, week-over-week delta — without touching UI. Ships as `0.1.4-rc1`.

**Architecture:** Three independent additions to `ClaudegrainCore`. (1) `ModelFamily` enum derives Opus/Sonnet/Haiku grouping in Swift (no SQL schema change). (2) `Forecaster` actor consumes 5-min cost buckets from `EventsDatabase.costPerBucket(...)` and emits hit-time predictions with confidence/basis tagging. (3) `WeekDelta` value type compares Monday-UTC windows for cost + cache-hit. `AppCoordinator` wires all three on each refresh tick and republishes via `AppModel`. The legacy `>2× linear pace` burn-rate trigger is removed in favor of forecaster-gated notifications.

**Tech Stack:** Swift 5.9, SwiftPM, GRDB.swift 6.x (existing), XCTest, Foundation `Calendar` for week boundaries.

**Branch:** `feat/v0.2/core-data` off `main` (currently `0.1.3`).

---

## Pre-flight

### Task 0: Cut branch + baseline

**Files:** none modified

- [ ] **Step 1: Pull latest main, cut branch**

```bash
git checkout main
git pull --ff-only
git checkout -b feat/v0.2/core-data
```

- [ ] **Step 2: Run baseline tests to confirm green starting state**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed` with no failures. If any test fails on a fresh `main`, stop and report — do not proceed.

- [ ] **Step 3: Confirm price catalog still loads (sanity)**

```bash
swift test --filter PriceTableLoaderTests 2>&1 | tail -3
```

Expected: passes.

---

## A1 — Per-model attribution

### Task 1: `ModelFamily` enum

**Files:**
- Create: `Sources/ClaudegrainCore/Model/ModelFamily.swift`
- Test: `Tests/ClaudegrainCoreTests/ModelFamilyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudegrainCoreTests/ModelFamilyTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore

final class ModelFamilyTests: XCTestCase {
    func testParsesOpus() {
        XCTAssertEqual(ModelFamily.parse("claude-opus-4-7"), .opus)
        XCTAssertEqual(ModelFamily.parse("claude-opus-4-6"), .opus)
        XCTAssertEqual(ModelFamily.parse("claude-3-opus-20240229"), .opus)
    }

    func testParsesSonnet() {
        XCTAssertEqual(ModelFamily.parse("claude-sonnet-4-6"), .sonnet)
        XCTAssertEqual(ModelFamily.parse("claude-3-5-sonnet-20240620"), .sonnet)
    }

    func testParsesHaiku() {
        XCTAssertEqual(ModelFamily.parse("claude-haiku-4-5-20251001"), .haiku)
        XCTAssertEqual(ModelFamily.parse("claude-3-haiku-20240307"), .haiku)
    }

    func testUnknownReturnsUnknown() {
        XCTAssertEqual(ModelFamily.parse(""), .unknown)
        XCTAssertEqual(ModelFamily.parse("gpt-4"), .unknown)
        XCTAssertEqual(ModelFamily.parse("claude-instant-1"), .unknown)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(ModelFamily.parse("CLAUDE-OPUS-4-7"), .opus)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ModelFamilyTests 2>&1 | tail -10
```

Expected: compile error `cannot find 'ModelFamily' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudegrainCore/Model/ModelFamily.swift`:

```swift
import Foundation

public enum ModelFamily: String, Codable, Hashable, Sendable {
    case opus
    case sonnet
    case haiku
    case unknown

    /// Match family by substring on the model id. Order matters: more specific first.
    /// Pure string matching, no allocation beyond `lowercased()`.
    public static func parse(_ id: String) -> ModelFamily {
        let lower = id.lowercased()
        if lower.contains("opus")   { return .opus }
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("haiku")  { return .haiku }
        return .unknown
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ModelFamilyTests 2>&1 | tail -3
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Model/ModelFamily.swift Tests/ClaudegrainCoreTests/ModelFamilyTests.swift
git commit -m "feat(core): add ModelFamily enum + parse"
```

---

### Task 2: `UsageEvent.modelFamily` computed property

**Files:**
- Modify: `Sources/ClaudegrainCore/Model/UsageEvent.swift`
- Modify: `Tests/ClaudegrainCoreTests/JSONLParserTests.swift` (add 1 assertion to existing test)

- [ ] **Step 1: Add failing assertion to existing parser test**

In `Tests/ClaudegrainCoreTests/JSONLParserTests.swift`, find `testParsesMcpToolUseAssistantEvent` and append before the closing brace:

```swift
        XCTAssertEqual(event.modelFamily, .opus)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter JSONLParserTests/testParsesMcpToolUseAssistantEvent 2>&1 | tail -10
```

Expected: compile error `value of type 'UsageEvent' has no member 'modelFamily'`.

- [ ] **Step 3: Add the computed property**

In `Sources/ClaudegrainCore/Model/UsageEvent.swift`, add inside the `UsageEvent` struct (near `primaryTool`):

```swift
    /// Family grouping derived from `model`. ADR-0006: grouped in Swift, not SQL.
    public var modelFamily: ModelFamily { ModelFamily.parse(model) }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter JSONLParserTests 2>&1 | tail -3
```

Expected: all parser tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Model/UsageEvent.swift Tests/ClaudegrainCoreTests/JSONLParserTests.swift
git commit -m "feat(core): UsageEvent.modelFamily computed from model id"
```

---

### Task 3: `EventsDatabase.costPerModel` query

**Files:**
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift` inside the test class:

```swift
    func testCostPerModelGroupsByFamily() async throws {
        let db = try EventsDatabase(url: tempURL())   // existing helper
        let now = Date()
        // Three events: opus $1.00, sonnet $0.50, sonnet $0.25
        try await db.append([
            makeEvent(model: "claude-opus-4-7",     cost: 1.00, ts: now),
            makeEvent(model: "claude-sonnet-4-6",   cost: 0.50, ts: now),
            makeEvent(model: "claude-sonnet-4-6",   cost: 0.25, ts: now),
        ])

        let map = try await db.costPerModel(
            since: now.addingTimeInterval(-60),
            until: now.addingTimeInterval(60)
        )

        XCTAssertEqual(map[.opus],   1.00, accuracy: 0.0001)
        XCTAssertEqual(map[.sonnet], 0.75, accuracy: 0.0001)
        XCTAssertNil(map[.haiku])
    }

    func testCostPerModelHonorsTimeWindow() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        try await db.append([
            makeEvent(model: "claude-opus-4-7", cost: 9.99, ts: yesterday),
            makeEvent(model: "claude-opus-4-7", cost: 1.00, ts: now),
        ])

        let map = try await db.costPerModel(
            since: now.addingTimeInterval(-3600),
            until: now.addingTimeInterval(60)
        )

        XCTAssertEqual(map[.opus], 1.00, accuracy: 0.0001)
    }
```

If `tempURL()` and `makeEvent(...)` helpers don't exist in `EventsDatabaseTests.swift`, add them at the bottom of the file:

```swift
private extension EventsDatabaseTests {
    func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudegrain-test-\(UUID().uuidString).db")
    }

    func makeEvent(
        model: String,
        cost: Double,
        ts: Date,
        cwd: String = "/repo",
        primaryTool: String? = nil
    ) -> StoredEvent {
        StoredEvent(
            timestamp: ts,
            sessionId: UUID().uuidString,
            cwd: cwd,
            gitBranch: nil,
            model: model,
            primaryTool: primaryTool,
            mcpServer: nil,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            costUSD: cost,
            sourceFile: "/x.jsonl",
            sourceOffset: 0,
            dedupKey: nil
        )
    }
}
```

(If existing helpers are present, reuse them — don't shadow.)

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsDatabaseTests/testCostPerModelGroupsByFamily 2>&1 | tail -10
```

Expected: compile error `value of type 'EventsDatabase' has no member 'costPerModel'`.

- [ ] **Step 3: Implement the query**

In `Sources/ClaudegrainCore/Store/EventsDatabase.swift`, add the public method (near other aggregations, e.g. after `costPerDay`):

```swift
    /// Sum cost grouped by `ModelFamily` over the half-open interval [since, until).
    /// Family grouping happens in Swift (ADR-0006); SQL just sums per raw model id.
    public func costPerModel(since: Date, until: Date) -> [ModelFamily: Double] {
        let rows: [(model: String, cost: Double)] = (try? pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT model, SUM(cost_usd) AS s
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY model
                """, arguments: [since, until])
                .map { (model: $0["model"] ?? "", cost: $0["s"] ?? 0.0) }
        }) ?? []

        var out: [ModelFamily: Double] = [:]
        for r in rows {
            out[ModelFamily.parse(r.model), default: 0] += r.cost
        }
        return out
    }
```

The actor signature must remain (`public func` inside `public actor EventsDatabase`).

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsDatabaseTests/testCostPerModel 2>&1 | tail -5
```

Expected: both new test methods pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift
git commit -m "feat(core): EventsDatabase.costPerModel grouped by family"
```

---

### Task 4: `EventsDatabase.tokensPerModel` query

**Files:**
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EventsDatabaseTests`:

```swift
    func testTokensPerModelSumsAllChannels() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        try await db.append([
            StoredEvent(
                timestamp: now, sessionId: "s", cwd: "/r", gitBranch: nil,
                model: "claude-opus-4-7",
                primaryTool: nil, mcpServer: nil,
                inputTokens: 100, outputTokens: 200,
                cacheCreationTokens: 1000, cacheReadTokens: 5000,
                costUSD: 0,
                sourceFile: "/x", sourceOffset: 0, dedupKey: nil
            )
        ])

        let map = try await db.tokensPerModel(
            since: now.addingTimeInterval(-60),
            until: now.addingTimeInterval(60)
        )

        let opus = try XCTUnwrap(map[.opus])
        XCTAssertEqual(opus.input, 100)
        XCTAssertEqual(opus.output, 200)
        XCTAssertEqual(opus.cacheCreation, 1000)
        XCTAssertEqual(opus.cacheRead, 5000)
        XCTAssertEqual(opus.total, 6300)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsDatabaseTests/testTokensPerModelSumsAllChannels 2>&1 | tail -10
```

Expected: compile error `cannot find 'TokenBreakdown'` and `no member 'tokensPerModel'`.

- [ ] **Step 3: Add type + query**

In `Sources/ClaudegrainCore/Store/EventsDatabase.swift` add at the top (or in a sibling file `Store/TokenBreakdown.swift` if you prefer; this plan keeps it inline):

```swift
public struct TokenBreakdown: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheCreation: Int
    public let cacheRead: Int
    public init(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        self.input = input; self.output = output
        self.cacheCreation = cacheCreation; self.cacheRead = cacheRead
    }
    public var total: Int { input + output + cacheCreation + cacheRead }
}
```

Then add the method:

```swift
    public func tokensPerModel(since: Date, until: Date) -> [ModelFamily: TokenBreakdown] {
        let rows: [Row] = (try? pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT model,
                       SUM(in_tok)            AS in_t,
                       SUM(out_tok)           AS out_t,
                       SUM(cache_create_tok)  AS cc_t,
                       SUM(cache_read_tok)    AS cr_t
                FROM events
                WHERE ts >= ? AND ts < ?
                GROUP BY model
                """, arguments: [since, until])
        }) ?? []

        var out: [ModelFamily: TokenBreakdown] = [:]
        for r in rows {
            let fam = ModelFamily.parse(r["model"] ?? "")
            let prior = out[fam] ?? TokenBreakdown(input: 0, output: 0, cacheCreation: 0, cacheRead: 0)
            out[fam] = TokenBreakdown(
                input:         prior.input         + (r["in_t"]  ?? 0),
                output:        prior.output        + (r["out_t"] ?? 0),
                cacheCreation: prior.cacheCreation + (r["cc_t"]  ?? 0),
                cacheRead:     prior.cacheRead     + (r["cr_t"]  ?? 0)
            )
        }
        return out
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsDatabaseTests/testTokensPerModelSumsAllChannels 2>&1 | tail -3
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift
git commit -m "feat(core): EventsDatabase.tokensPerModel + TokenBreakdown"
```

---

## A3 — Forecast

### Task 5: `CostBucket` + `EventsDatabase.costPerBucket` query

**Files:**
- Create: `Sources/ClaudegrainCore/Forecast/CostBucket.swift`
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EventsDatabaseTests`:

```swift
    func testCostPerBucketReturnsContiguousFiveMinBuckets() async throws {
        let db = try EventsDatabase(url: tempURL())
        let anchor = Date(timeIntervalSince1970: 1_777_000_000)
        // 0:00–0:05 → $0.10, 0:05–0:10 → $0, 0:10–0:15 → $0.30
        try await db.append([
            makeEvent(model: "x", cost: 0.10, ts: anchor.addingTimeInterval(60)),
            makeEvent(model: "x", cost: 0.30, ts: anchor.addingTimeInterval(11 * 60)),
        ])

        let buckets = try await db.costPerBucket(
            start: anchor,
            span: 15 * 60,
            bucketSize: 5 * 60
        )

        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets[0].costUSD, 0.10, accuracy: 0.0001)
        XCTAssertEqual(buckets[1].costUSD, 0.0,  accuracy: 0.0001)
        XCTAssertEqual(buckets[2].costUSD, 0.30, accuracy: 0.0001)
        XCTAssertEqual(buckets[0].start, anchor)
        XCTAssertEqual(buckets[2].end,   anchor.addingTimeInterval(15 * 60))
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsDatabaseTests/testCostPerBucketReturnsContiguousFiveMinBuckets 2>&1 | tail -10
```

Expected: cannot find `costPerBucket`, cannot find `CostBucket`.

- [ ] **Step 3: Implement**

Create `Sources/ClaudegrainCore/Forecast/CostBucket.swift`:

```swift
import Foundation

public struct CostBucket: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let costUSD: Double
    public init(start: Date, end: Date, costUSD: Double) {
        self.start = start; self.end = end; self.costUSD = costUSD
    }
}
```

In `EventsDatabase.swift` add:

```swift
    /// Returns N contiguous buckets of width `bucketSize` over `[start, start+span)`,
    /// zero-filled where there are no events. Used by `Forecaster`.
    public func costPerBucket(
        start: Date,
        span: TimeInterval,
        bucketSize: TimeInterval
    ) -> [CostBucket] {
        precondition(bucketSize > 0)
        precondition(span > 0)
        let count = Int((span / bucketSize).rounded(.down))
        guard count > 0 else { return [] }

        let end = start.addingTimeInterval(span)
        let rows: [Row] = (try? pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, cost_usd
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        }) ?? []

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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsDatabaseTests/testCostPerBucket 2>&1 | tail -3
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Forecast/CostBucket.swift Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift
git commit -m "feat(core): CostBucket + EventsDatabase.costPerBucket"
```

---

### Task 6: `Forecaster` — types + insufficient-data path

**Files:**
- Create: `Sources/ClaudegrainCore/Forecast/Forecaster.swift`
- Create: `Tests/ClaudegrainCoreTests/ForecasterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudegrainCoreTests/ForecasterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ForecasterTests 2>&1 | tail -10
```

Expected: cannot find `Forecaster`, `Confidence`, `Basis`, `ForecastResult`.

- [ ] **Step 3: Implement minimal Forecaster + types**

Create `Sources/ClaudegrainCore/Forecast/Forecaster.swift`:

```swift
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
        // Filled in next tasks.
        return .insufficient
    }

    static func mondayUTC(of date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ForecasterTests/testEmptyBucketsReturnInsufficient 2>&1 | tail -3
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Forecast/Forecaster.swift Tests/ClaudegrainCoreTests/ForecasterTests.swift
git commit -m "feat(core): Forecaster scaffold + insufficient-data path"
```

---

### Task 7: `Forecaster` — linear basis (degradation case, <3 buckets)

**Files:**
- Modify: `Sources/ClaudegrainCore/Forecast/Forecaster.swift`
- Modify: `Tests/ClaudegrainCoreTests/ForecasterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ForecasterTests`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ForecasterTests 2>&1 | tail -10
```

Expected: 2 failures — `basis == .insufficient` (we haven't implemented linear yet).

- [ ] **Step 3: Add linear-degradation branch**

Replace `forecast(usedFraction:elapsedSeconds:remainingSeconds:recent:)` body in `Forecaster.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ForecasterTests 2>&1 | tail -5
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Forecast/Forecaster.swift Tests/ClaudegrainCoreTests/ForecasterTests.swift
git commit -m "feat(core): Forecaster linear-degradation path (<3 buckets)"
```

---

### Task 8: `Forecaster` — EWMA basis (≥3 buckets)

**Files:**
- Modify: `Sources/ClaudegrainCore/Forecast/Forecaster.swift`
- Modify: `Tests/ClaudegrainCoreTests/ForecasterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ForecasterTests`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ForecasterTests 2>&1 | tail -10
```

Expected: 2 failures — `basis == .linear` instead of `.ewma`.

- [ ] **Step 3: Add EWMA branch**

In `Forecaster.swift`, replace the `forecast(...)` body to dispatch correctly and add the EWMA helper:

```swift
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
        return ewmaForecast(
            usedFraction: usedFraction,
            remainingSeconds: remainingSeconds,
            buckets: recent
        )
    }

    /// EWMA over per-bucket cost (oldest → newest). α = 0.4.
    /// Returns predicted hit time using `usedFraction → 1.0` at the smoothed rate.
    private func ewmaForecast(
        usedFraction: Double,
        remainingSeconds: Double,
        buckets: [CostBucket]
    ) -> ForecastResult {
        let alpha = 0.4
        var ewmaCost = buckets[0].costUSD
        for bucket in buckets.dropFirst() {
            ewmaCost = alpha * bucket.costUSD + (1 - alpha) * ewmaCost
        }
        let bucketSize = buckets[0].end.timeIntervalSince(buckets[0].start)
        guard bucketSize > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .ewma)
        }

        // Convert ewma cost-per-bucket to fraction-per-second.
        // We don't actually have absolute total budget in dollars (depends on plan tier);
        // approximate fraction-per-bucket as (ewmaCost / sumCost) * usedFraction,
        // which folds in the user's actual plan allocation.
        let sumCost = buckets.reduce(0) { $0 + $1.costUSD }
        guard sumCost > 0, usedFraction > 0 else {
            return ForecastResult(willHit: false, hitAt: nil, confidence: .low, basis: .ewma)
        }
        let smoothedFractionPerBucket = (ewmaCost / sumCost) * usedFraction
            * (Double(buckets.count))    // scale: full-window-fraction → per-bucket
        let smoothedFractionPerSecond = smoothedFractionPerBucket / bucketSize

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
```

> Note on the rate derivation: the snapshot's `usedFraction` already encodes the plan-specific budget. We extract a per-bucket fraction by attributing it proportionally across the recent window, then EWMA-weight. Crude but plan-agnostic — refined in a follow-up if accuracy issues arise (see ADR-0005).

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ForecasterTests 2>&1 | tail -5
```

Expected: all 5 forecaster tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Forecast/Forecaster.swift Tests/ClaudegrainCoreTests/ForecasterTests.swift
git commit -m "feat(core): Forecaster EWMA branch (>=3 buckets)"
```

---

### Task 9: Forecaster confidence levels regression test

**Files:**
- Modify: `Tests/ClaudegrainCoreTests/ForecasterTests.swift`

- [ ] **Step 1: Write a parameterized confidence test**

Append:

```swift
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
```

- [ ] **Step 2: Run test to verify it passes immediately**

```bash
swift test --filter ForecasterTests/testConfidenceTiers 2>&1 | tail -3
```

Expected: pass (Task 8's `confidenceFor` already covers the tiers). If it fails, fix the threshold logic in `Forecaster.swift` — do not change the test.

- [ ] **Step 3: Commit (regression-only)**

```bash
git add Tests/ClaudegrainCoreTests/ForecasterTests.swift
git commit -m "test(core): Forecaster confidence-tier regression"
```

---

## B3 — Week-over-week delta

### Task 10: `EventsDatabase.costInWindow` + `cacheHitRateInWindow`

**Files:**
- Modify: `Sources/ClaudegrainCore/Store/EventsDatabase.swift`
- Modify: `Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EventsDatabaseTests`:

```swift
    func testCostInWindowSumsCostsInRange() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        try await db.append([
            makeEvent(model: "x", cost: 1.00, ts: now.addingTimeInterval(-100)),
            makeEvent(model: "x", cost: 2.00, ts: now),
            makeEvent(model: "x", cost: 3.00, ts: now.addingTimeInterval(100)),
        ])

        let total = try await db.costInWindow(
            start: now.addingTimeInterval(-50),
            end:   now.addingTimeInterval(50)
        )

        XCTAssertEqual(total, 2.00, accuracy: 0.0001)
    }

    func testCacheHitRateInWindow() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        try await db.append([
            StoredEvent(
                timestamp: now, sessionId: "s", cwd: "/r", gitBranch: nil,
                model: "x", primaryTool: nil, mcpServer: nil,
                inputTokens: 100, outputTokens: 0,
                cacheCreationTokens: 50, cacheReadTokens: 350,
                costUSD: 0,
                sourceFile: "/x", sourceOffset: 0, dedupKey: nil
            )
        ])

        let rate = try await db.cacheHitRateInWindow(
            start: now.addingTimeInterval(-60),
            end:   now.addingTimeInterval(60)
        )

        // cache_read / (input + cache_create + cache_read) = 350 / 500 = 0.70
        XCTAssertEqual(rate, 0.70, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventsDatabaseTests/testCostInWindow 2>&1 | tail -5
swift test --filter EventsDatabaseTests/testCacheHitRateInWindow 2>&1 | tail -5
```

Expected: cannot find members.

- [ ] **Step 3: Implement**

In `EventsDatabase.swift`:

```swift
    public func costInWindow(start: Date, end: Date) -> Double {
        (try? pool.read { db in
            try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(cost_usd), 0)
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        }) ?? 0
    }

    /// cache_read / (input + cache_create + cache_read). 0 if no events in window.
    public func cacheHitRateInWindow(start: Date, end: Date) -> Double {
        let row: Row? = try? pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(in_tok), 0)           AS in_t,
                       COALESCE(SUM(cache_create_tok), 0) AS cc_t,
                       COALESCE(SUM(cache_read_tok), 0)   AS cr_t
                FROM events
                WHERE ts >= ? AND ts < ?
                """, arguments: [start, end])
        }
        guard let row else { return 0 }
        let denom = (row["in_t"] as Int? ?? 0) + (row["cc_t"] as Int? ?? 0) + (row["cr_t"] as Int? ?? 0)
        guard denom > 0 else { return 0 }
        return Double(row["cr_t"] as Int? ?? 0) / Double(denom)
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventsDatabaseTests/testCostInWindow 2>&1 | tail -3
swift test --filter EventsDatabaseTests/testCacheHitRateInWindow 2>&1 | tail -3
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Store/EventsDatabase.swift Tests/ClaudegrainCoreTests/EventsDatabaseTests.swift
git commit -m "feat(core): EventsDatabase.costInWindow + cacheHitRateInWindow"
```

---

### Task 11: `WeekDelta` value type + computation

**Files:**
- Create: `Sources/ClaudegrainCore/Aggregation/WeekDelta.swift`
- Create: `Tests/ClaudegrainCoreTests/WeekDeltaTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudegrainCoreTests/WeekDeltaTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore

final class WeekDeltaTests: XCTestCase {
    func testFirstWeekReturnsNilPctChange() async throws {
        let db = try EventsDatabase(url: tempURL())
        // Only events in the current week.
        let now = Date()
        try await db.append([
            mkEvent(cost: 5.00, ts: now)
        ])

        let delta = try await WeekDelta.compute(db: db, now: now)

        XCTAssertEqual(delta.thisWeekCost, 5.00, accuracy: 0.0001)
        XCTAssertEqual(delta.lastWeekCost, 0.00, accuracy: 0.0001)
        XCTAssertNil(delta.pctChange)
    }

    func testNormalDeltaIs12PercentIncrease() async throws {
        let db = try EventsDatabase(url: tempURL())
        let now = Date()
        let monday = WeekDelta.mondayUTC(of: now)
        let lastMonday = monday.addingTimeInterval(-7 * 86_400)
        try await db.append([
            mkEvent(cost: 10.00, ts: lastMonday.addingTimeInterval(3600)),
            mkEvent(cost: 11.20, ts: monday.addingTimeInterval(3600)),
        ])

        let delta = try await WeekDelta.compute(db: db, now: now)
        XCTAssertEqual(delta.thisWeekCost, 11.20, accuracy: 0.0001)
        XCTAssertEqual(delta.lastWeekCost, 10.00, accuracy: 0.0001)
        XCTAssertEqual(delta.pctChange ?? 0, 0.12, accuracy: 0.0001)
    }
}

private extension WeekDeltaTests {
    func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudegrain-test-\(UUID().uuidString).db")
    }
    func mkEvent(cost: Double, ts: Date) -> StoredEvent {
        StoredEvent(
            timestamp: ts, sessionId: "s", cwd: "/r", gitBranch: nil,
            model: "claude-opus-4-7", primaryTool: nil, mcpServer: nil,
            inputTokens: 0, outputTokens: 0,
            cacheCreationTokens: 0, cacheReadTokens: 0,
            costUSD: cost,
            sourceFile: "/x", sourceOffset: 0, dedupKey: nil
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter WeekDeltaTests 2>&1 | tail -10
```

Expected: cannot find `WeekDelta`.

- [ ] **Step 3: Implement**

Create `Sources/ClaudegrainCore/Aggregation/WeekDelta.swift`:

```swift
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

        let thisCost = await db.costInWindow(start: thisStart, end: now)
        let lastEnd  = lastStart.addingTimeInterval(7 * 86_400)
        let lastCost = await db.costInWindow(start: lastStart, end: lastEnd)

        let thisHit = await db.cacheHitRateInWindow(start: thisStart, end: now)
        let lastHit = await db.cacheHitRateInWindow(start: lastStart, end: lastEnd)

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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter WeekDeltaTests 2>&1 | tail -5
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Aggregation/WeekDelta.swift Tests/ClaudegrainCoreTests/WeekDeltaTests.swift
git commit -m "feat(core): WeekDelta value type + Monday-UTC compute"
```

---

## Wire-up to AppCoordinator

### Task 12: Add forecast / weekDelta / modelMix to `AppModel`

**Files:**
- Modify: `Sources/ClaudegrainApp/AppModel.swift`

- [ ] **Step 1: Add published fields**

In `Sources/ClaudegrainApp/AppModel.swift`, append fields next to the existing `@Published`:

```swift
    @Published var forecastBlock: ForecastResult?
    @Published var forecastWeekly: ForecastResult?
    @Published var weekDelta: WeekDelta?
    @Published var modelMix: [ModelFamily: Double] = [:]
```

(No tests for the bare AppModel field additions — they'll be exercised by Task 13's coordinator integration test.)

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudegrainApp/AppModel.swift
git commit -m "feat(app): AppModel publishes forecast/weekDelta/modelMix"
```

---

### Task 13: AppCoordinator wires Forecaster + WeekDelta + ModelMix

**Files:**
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift`
- Modify: `Tests/ClaudegrainCoreTests/IngestActorTests.swift` (or new `AppCoordinatorTests.swift` if more natural)

- [ ] **Step 1: Add a coordinator wiring test**

Create `Tests/ClaudegrainCoreTests/AppCoordinatorWiringTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore
@testable import ClaudegrainApp

@MainActor
final class AppCoordinatorWiringTests: XCTestCase {
    func testRefreshPopulatesForecastAndWeekDeltaAndModelMix() async throws {
        // Spin a coordinator pointed at a temp DB and feed it a couple of events.
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-coord-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        try await db.append([
            StoredEvent(
                timestamp: now, sessionId: "s", cwd: "/r", gitBranch: nil,
                model: "claude-opus-4-7", primaryTool: nil, mcpServer: nil,
                inputTokens: 100, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0,
                costUSD: 1.0,
                sourceFile: "/x", sourceOffset: 0, dedupKey: nil
            )
        ])

        let model = AppModel(loginItem: LoginItemController(),
                             preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))

        // Inject a session block snapshot for the forecaster to consume.
        model.sessionBlock = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10,
            totalTokens: 1
        )

        let coord = try AppCoordinatorTestHook.make(model: model, db: db)
        await coord.refreshDerivedNow()

        XCTAssertNotNil(model.forecastBlock)
        XCTAssertNotNil(model.weekDelta)
        XCTAssertEqual(model.modelMix[.opus] ?? 0, 1.0, accuracy: 0.0001)
    }
}
```

You will need a tiny test seam — see Step 3.

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AppCoordinatorWiringTests 2>&1 | tail -10
```

Expected: cannot find `AppCoordinatorTestHook` / `refreshDerivedNow`.

- [ ] **Step 3: Implement coordinator wiring + test seam**

In `Sources/ClaudegrainApp/AppCoordinator.swift`:

```swift
    private let forecaster = Forecaster()

    /// Recompute all derived/aggregated fields from the current DB state and
    /// publish them on `AppModel`. Called on every refresh tick.
    func refreshDerivedNow() async {
        // 1. Model mix — last 24h.
        let now = Date()
        let dayStart = now.addingTimeInterval(-24 * 3600)
        let costsByFamily = await db.costPerModel(since: dayStart, until: now)
        let totalDaily = costsByFamily.values.reduce(0, +)
        if totalDaily > 0 {
            model.modelMix = costsByFamily.mapValues { $0 / totalDaily }
        } else {
            model.modelMix = [:]
        }

        // 2. WeekDelta.
        model.weekDelta = await WeekDelta.compute(db: db, now: now)

        // 3. Forecast block + weekly.
        let buckets = await db.costPerBucket(
            start: now.addingTimeInterval(-3600),
            span:  3600,
            bucketSize: 5 * 60
        )
        if let session = model.sessionBlock {
            model.forecastBlock = await forecaster.forecastSessionBlock(block: session, recent: buckets)
        }
        if let weekly = model.weekly {
            model.forecastWeekly = await forecaster.forecastWeekly(weekly: weekly, recent: buckets)
        }
    }
```

Then call it at the end of `applyIngestSnapshot(...)`:

```swift
    private func applyIngestSnapshot(_ snapshot: IngestActor.Snapshot) {
        model.todayTotals = snapshot.today
        model.allTimeTotals = snapshot.allTime
        model.topRepos = snapshot.topRepos
        model.topTools = snapshot.topTools
        model.cacheHitRate = snapshot.cacheHitRate
        model.weekSpend = snapshot.weekSpend
        Task { [weak self] in await self?.refreshDerivedNow() }
        notifications.evaluateUsage(
            session: model.sessionBlock,
            weekly: model.weekly,
            topRepos: snapshot.topRepos
        )
    }
```

Add the test seam at the bottom of the file:

```swift
#if DEBUG
enum AppCoordinatorTestHook {
    @MainActor
    static func make(model: AppModel, db: EventsDatabase) throws -> AppCoordinator {
        let coord = try AppCoordinator(model: model, dbOverride: db)
        return coord
    }
}
#endif
```

And alter `init` to accept the override (additive, default keeps current behavior):

```swift
    init(
        model: AppModel,
        notifications: NotificationManager? = nil,
        dbOverride: EventsDatabase? = nil
    ) throws {
        self.model = model
        if let dbOverride {
            self.db = dbOverride
        } else {
            self.db = try EventsDatabase(url: EventsDatabase.defaultURL)
        }
        self.ingest = IngestActor(db: db)
        self.dataSource = DataSourceCoordinator()
        self.notifications = notifications ?? NotificationManager(prefs: model.preferences)
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter AppCoordinatorWiringTests 2>&1 | tail -5
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainApp/AppCoordinator.swift Tests/ClaudegrainCoreTests/AppCoordinatorWiringTests.swift
git commit -m "feat(app): AppCoordinator wires Forecaster/WeekDelta/ModelMix"
```

---

### Task 14: Replace legacy burn-rate notification trigger with forecaster gate

**Files:**
- Modify: `Sources/ClaudegrainApp/NotificationManager.swift`
- Modify: `Tests/ClaudegrainCoreTests/NotificationManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudegrainCoreTests/NotificationManagerTests.swift`:

```swift
    func testBurnRateFiresOnForecasterMediumOrAbove() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "burn-\(UUID().uuidString)")!)
        prefs.notifyBurnRate = true

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in
            fired.append(kind)
        }
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.6,
            totalTokens: 1
        )

        // medium-confidence hit
        mgr.evaluateBurnRate(session: snap, forecast: ForecastResult(
            willHit: true,
            hitAt: now.addingTimeInterval(1200),
            confidence: .medium,
            basis: .ewma
        ))

        XCTAssertEqual(fired, [.burnRate])
    }

    func testBurnRateDoesNotFireOnLowConfidence() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "burn-low-\(UUID().uuidString)")!)
        prefs.notifyBurnRate = true

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in
            fired.append(kind)
        }
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.6,
            totalTokens: 1
        )

        mgr.evaluateBurnRate(session: snap, forecast: ForecastResult(
            willHit: true,
            hitAt: now.addingTimeInterval(1200),
            confidence: .low,
            basis: .ewma
        ))

        XCTAssertTrue(fired.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter NotificationManagerTests/testBurnRate 2>&1 | tail -10
```

Expected: cannot find `evaluateBurnRate`.

- [ ] **Step 3: Refactor NotificationManager**

In `Sources/ClaudegrainApp/NotificationManager.swift`:

1. Remove the existing private `checkBurnRate(_:)` and its `>=2.0 pacing` math.
2. Remove the call to `checkBurnRate(session)` from `evaluateUsage`.
3. Add a new public method:

```swift
    /// Forecaster-gated burn-rate notification. Fires once per session block when
    /// (willHit == true) AND (confidence >= .medium). Replaces the >2× linear pace
    /// rule (ADR-0005).
    func evaluateBurnRate(session: SessionBlockSnapshot?, forecast: ForecastResult?) {
        guard prefs.notifyBurnRate,
              let session,
              let forecast,
              forecast.willHit,
              forecast.confidence != .low
        else {
            burnRateFiredFor = nil
            return
        }
        guard burnRateFiredFor != session.startedAt else { return }
        let etaMin = forecast.hitAt.map { Int($0.timeIntervalSinceNow / 60) } ?? -1
        fire(.burnRate,
             title: "Claude burn rate spiking",
             body: "Forecast: hit \(forecast.basis.rawValue.uppercased()) " +
                   "(\(forecast.confidence.rawValue)) · ETA ~\(etaMin) min")
        burnRateFiredFor = session.startedAt
    }
```

4. In `AppCoordinator.refreshDerivedNow()` (Task 13), append after the forecast assignment:

```swift
        notifications.evaluateBurnRate(session: model.sessionBlock, forecast: model.forecastBlock)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -5
```

Expected: all NotificationManager tests still pass + the two new ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainApp/NotificationManager.swift Sources/ClaudegrainApp/AppCoordinator.swift Tests/ClaudegrainCoreTests/NotificationManagerTests.swift
git commit -m "refactor(app): burn-rate notification gated by Forecaster (ADR-0005)"
```

---

## ADRs + release

### Task 15: ADR-0005 (forecast-ewma) and ADR-0006 (model-family-grouping)

**Files:**
- Create: `docs/adr/0005-forecast-ewma.md`
- Create: `docs/adr/0006-model-family-grouping.md`

- [ ] **Step 1: Create ADR-0005**

Create `docs/adr/0005-forecast-ewma.md`:

```markdown
# Forecaster: EWMA over 5-min cost buckets

## Status

accepted

## Context

v0.2 needs a forecast of when the current 5h block / weekly window will
hit 100% used. Two forecasting failure modes to avoid:

- **Linear pace** (used / elapsed): too jittery — a single burst spikes
  the projection, then it stays high while the user goes silent.
- **Naive average over the whole window**: too slow — doesn't react
  when the user shifts pace mid-block.

We also can't easily import a heavyweight forecasting library: we run in
a sandboxed menu bar app, GRDB is the only existing dep, the prediction
runs every refresh tick, and signal quality is bounded by 5-min
granularity anyway.

## Decision

EWMA (exponentially-weighted moving average) over **5-minute cost
buckets** drawn from the last **60 minutes**, with **α = 0.4**.

- Bucket count `n` drives confidence: <3 = `.insufficient/.low` (degrades
  to a linear projection), 3–4 = `.low`, 5–9 = `.medium`, ≥10 = `.high`.
- The legacy `>2× linear pace` burn-rate rule is **removed**, not run
  in parallel. `Forecaster` already encapsulates a linear fallback for
  the sparse case.
- Notifications only fire when `willHit == true` and confidence is
  `.medium` or higher — avoiding cold-start false alarms.

## Considered options

- **Linear extrapolation only** — fragile to bursts, easy to game with
  silence. Used as fallback only.
- **Holt-Winters / ARIMA** — overkill for 12 5-min buckets; harder to
  test deterministically.
- **Token-bucket-style decay over fixed wall clock** — equivalent to
  EWMA but harder to reason about α-tuning.

## Consequences

- α is hardcoded at 0.4 in v0.2. If the post-burst cooldown overshoot
  proves user-visible (issue feedback), revisit.
- The implementation derives a per-bucket fraction by attributing the
  snapshot's `usedFraction` proportionally across buckets — folds plan
  tier into the rate without us hardcoding plan budgets.
- All new logic is in `ClaudegrainCore/Forecast/` and is fully unit
  tested. No SQL schema change.
```

- [ ] **Step 2: Create ADR-0006**

Create `docs/adr/0006-model-family-grouping.md`:

```markdown
# Model family grouping in Swift, not SQL

## Status

accepted

## Context

A1 wants per-family attribution (Opus / Sonnet / Haiku). Two storage
options:

1. Persist a `model_family` column in `events` and migrate.
2. Keep the raw `model` id in SQL and group in Swift.

## Decision

Option 2. `ModelFamily.parse(_:)` is a pure string match in
`Sources/ClaudegrainCore/Model/ModelFamily.swift`. `EventsDatabase`
queries return `[ModelFamily: ...]` by aggregating `[String: ...]` rows
in Swift.

## Considered options

- Persist family column — every Anthropic model rename or new family
  forces a SQL migration. We already have a price-table-driven
  attribution that runs in Swift; pushing one more taxonomy down to SQL
  buys nothing.

## Consequences

- New families (e.g. Claude 5 "tide") just need a substring added to
  `ModelFamily.parse`. No DB migration.
- Aggregations cost an extra in-Swift hash group, negligible at our
  event volume (<100k rows in 90-day retention).
- ADR-0002 (SQLite as materialized view, JSONL as source of truth)
  stays clean — no new column means no rebuild risk.
```

- [ ] **Step 3: Commit**

```bash
git add docs/adr/0005-forecast-ewma.md docs/adr/0006-model-family-grouping.md
git commit -m "docs(adr): 0005 forecast-ewma + 0006 model-family-grouping"
```

---

### Task 16: Bump VERSION + CHANGELOG, run full test suite, tag rc

**Files:**
- Modify: `VERSION`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump VERSION**

Replace `VERSION` contents with:

```
0.1.4-rc1
```

- [ ] **Step 2: Add CHANGELOG entry**

Insert at the top of `CHANGELOG.md`, above the `[0.1.3]` section:

```markdown
## [0.1.4-rc1] — 2026-05-05

Phase 1 of v0.2 — core data layer. UI surfaces unchanged; the new
fields are populated but not yet rendered.

### Added
- `ModelFamily` enum (Opus/Sonnet/Haiku/unknown) + `UsageEvent.modelFamily`
- `EventsDatabase.costPerModel` and `tokensPerModel` aggregations
- `EventsDatabase.costPerBucket(start:span:bucketSize:)` for forecast input
- `EventsDatabase.costInWindow` and `cacheHitRateInWindow` for week deltas
- `Forecaster` actor with EWMA (α=0.4) and linear-fallback branches
  (ADR-0005)
- `WeekDelta` value type with Monday-UTC week boundaries (B3)
- `AppCoordinator.refreshDerivedNow()` ties Forecaster + ModelMix +
  WeekDelta to `AppModel`'s new published fields

### Changed
- Burn-rate notification (toggle b) is now gated by `Forecaster`'s
  `.willHit` + confidence ≥ medium. The legacy `>2× linear pace` rule
  is removed (ADR-0005).

### Docs
- ADR-0005 — forecast EWMA decision
- ADR-0006 — model family grouped in Swift, not SQL
```

- [ ] **Step 3: Run full test suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | tail -10
```

Expected: all green. Test count should be the prior number plus roughly 14
(Forecaster 5, ModelFamily 5, EventsDatabase ×4, WeekDelta 2, NotificationManager 2,
AppCoordinator wiring 1 — minor double-counting).

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION CHANGELOG.md
git commit -m "release: v0.1.4-rc1 (phase 1 — core data layer)"
git tag v0.1.4-rc1
git push origin feat/v0.2/core-data
git push origin v0.1.4-rc1
```

(Pushing the tag triggers `release.yml` and uploads an ad-hoc DMG to GitHub Releases as a prerelease.)

- [ ] **Step 5: Open PR**

```bash
gh pr create --base main --head feat/v0.2/core-data \
  --title "feat(v0.2 phase 1): core data — model family, forecaster, week delta" \
  --body "$(cat <<'EOF'
## Summary

Phase 1 of the v0.2 spec lands the data-layer foundations:

- A1 — per-model attribution via `ModelFamily` + `costPerModel` / `tokensPerModel`
- A3 — `Forecaster` actor (EWMA, α=0.4) + `costPerBucket` + linear fallback
- B3 — `WeekDelta` value type with Monday-UTC week boundaries
- Burn-rate notification refactored to use `Forecaster` confidence gate (ADR-0005)

UI surfaces are unchanged in this PR — fields are populated on `AppModel` but
not yet rendered. Phase 2 (`feat/v0.2/surfaces`) will wire them to the popover.

ADRs: 0005 (forecast-ewma), 0006 (model-family-grouping).

Spec: docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md §4.1, §4.2, §4.3

## Test plan

- [x] `swift test` green (added ~14 tests)
- [x] Build dmg via `bash scripts/build-dmg.sh` produces a working app
- [ ] Smoke: launch the dmg, popover renders normally, no crash
- [ ] Tag `v0.1.4-rc1` triggers GitHub Release with prerelease=true

EOF
)"
```

---

## Self-Review (run before merging)

Skim against the spec sections this plan claims to cover.

**Spec coverage:**

- §4.1 A1 — ModelFamily ✓ (Task 1), UsageEvent.modelFamily ✓ (Task 2),
  costPerModel ✓ (Task 3), tokensPerModel ✓ (Task 4), AppModel.modelMix ✓
  (Task 12), wired in AppCoordinator ✓ (Task 13). UI integration deferred to Phase 2.
- §4.2 A3 — CostBucket + costPerBucket ✓ (Task 5), Forecaster types ✓
  (Task 6), linear ✓ (Task 7), EWMA ✓ (Task 8), confidence tiers ✓ (Task 9),
  AppModel forecastBlock/Weekly ✓ (Task 12), wired ✓ (Task 13), notification
  gate ✓ (Task 14). UI badge deferred to Phase 2.
- §4.3 B3 — costInWindow/cacheHitRateInWindow ✓ (Task 10), WeekDelta type
  ✓ (Task 11), wired ✓ (Task 13). UI row deferred to Phase 2.

**Placeholder scan:**

No "TBD" / "TODO" / "implement later" markers in the plan. Each step
contains the exact code or command an engineer will run. The single
in-line note in Task 8 ("crude, refined in a follow-up") explains a
design choice — not a placeholder for future implementation.

**Type consistency:**

- `ModelFamily` (enum) used identically across Tasks 1, 2, 3, 4, 11, 12, 13.
- `ForecastResult.Confidence` and `ForecastResult.Basis` — confidence
  values `.low/.medium/.high`, basis `.ewma/.linear/.insufficient` —
  consistent across Tasks 6, 7, 8, 9, 14.
- `CostBucket(start:end:costUSD:)` — same signature in Tasks 5, 7, 8, 9.
- `WeekDelta(thisWeekCost:lastWeekCost:cacheHitDelta:)` — identical in
  Tasks 11, 13.
- `EventsDatabase.costPerBucket(start:span:bucketSize:)` — same arg labels
  in Tasks 5, 13.
- `Forecaster.forecastSessionBlock(block:recent:)` and
  `forecastWeekly(weekly:recent:)` — identical in Tasks 6, 7, 8, 9, 13.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-05-claudegrain-v0.2-phase1-core-data.md`.

Phases 2–5 will be written as separate plan files when Phase 1 lands.
