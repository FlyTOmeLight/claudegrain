# claudegrain v0.2 — Design Spec

**Date:** 2026-05-05
**Status:** approved (brainstorm) → pending implementation plan
**Target version:** 0.2.0 (from 0.1.2)

## 1. Scope

Ten subitems shipped under `0.2.0`, grouped into five sequentially-merged branches.

### Subitems
- **A1** — Per-model attribution (Opus / Sonnet / Haiku %/$)
- **A3** — Burn-rate forecast (5h block + weekly hit-time prediction)
- **B2** — Usage export (CSV / JSON, four dimensions)
- **B3** — Week-over-week delta card
- **C1** — Per-repo soft budgets (replaces global single threshold)
- **C2** — Quiet hours (notification suppression window)
- **C3** — Pause-ingest toggle
- **C4** — Self-commitment notification (actionable, log-only)
- **D**  — WidgetKit desktop widgets (small / medium / large)
- **E**  — First-run onboarding, empty-state copy, expanded keyboard shortcuts, log-reveal entry

### Explicitly out of scope
- A2 (cache savings $ breakdown) — pushed to backlog
- B1 (month/quarter trend view) — popover is not a BI tool; ADR-0002 90-day retention also constrains it
- Live activity / Apple Watch / Slack / webhook — D narrowed to WidgetKit only
- Killing Claude Code from the app (C4 is log-only)

## 2. Branch & rollout plan

```
main
 ├─ feat/v0.2/core-data        # A1, A3, B3
 ├─ feat/v0.2/surfaces         # B2 + popover rewire (consumes core-data)
 ├─ feat/v0.2/control          # C1, C2, C3, C4
 ├─ feat/v0.2/widget           # D (introduces .xcodeproj)
 └─ feat/v0.2/polish           # E + CHANGELOG + VERSION bump
```

Merges in order. Each merge is releasable as a `0.1.x-rc` prerelease; final cut to `0.2.0` after polish.

| PR | Tag |
|----|-----|
| core-data | 0.1.3-rc1 |
| surfaces  | 0.1.4-rc2 |
| control   | 0.1.5-rc3 |
| widget    | 0.2.0-beta |
| polish    | 0.2.0 |

## 3. Module changes

```
ClaudegrainCore/
  Forecast/         (new)         — A3
    Forecaster.swift
  Budget/           (new)         — C1
    BudgetStore.swift
  ExportLayer/      (new)         — B2
    EventsExporter.swift
  Snapshot/         (new)         — D
    WidgetSnapshot.swift
    AppGroupStore.swift
  Model/UsageEvent.swift           — extend with ModelFamily
  Store/EventsDatabase.swift       — new queries

ClaudegrainApp/
  Settings/         (new dir; split out of monolithic Preferences view)
    GeneralTab.swift
    NotificationsTab.swift
    BudgetsTab.swift              — C1
    QuietHoursTab.swift           — C2
    AboutTab.swift
  Onboarding/       (new)         — E
    FirstRunController.swift
    OnboardingPanel.swift
  EmptyStates.swift (new)         — E
  Commitment/       (new)         — C4
    CommitmentLog.swift
  IngestPauseController.swift     — C3
  ReceiptComponents/               — extended, see §6

ClaudegrainWidget/  (new SwiftPM target, registered via .xcodeproj — see §8)
  ClaudegrainWidget.swift
  Provider.swift
  Entry.swift
  Views/
    SmallView.swift
    MediumView.swift
    LargeView.swift
    Common/{RingMeter,BarMeter,Sparkline}.swift
  Resources/
    JetBrainsMono-Regular.otf     — copied; widget cannot reach app bundle
```

## 4. Feature designs

### 4.1 A1 — Per-model attribution

`UsageEvent.model` already exists. No schema migration. Family grouping happens in Swift, not SQL.

```swift
enum ModelFamily: String, Codable {
    case opus, sonnet, haiku, unknown
    static func parse(_ id: String) -> ModelFamily   // string match against id prefixes
}

extension UsageEvent { var modelFamily: ModelFamily }
```

New `EventsDatabase` queries:

```swift
func costPerModel(since: Date, until: Date) -> [ModelFamily: Double]
func tokensPerModel(since: Date, until: Date) -> [ModelFamily: TokenBreakdown]
```

UI: popover gains a `Models: opus 64% · sonnet 31% · haiku 5%` row. Color tokens from existing `Theme` (opus = purple, sonnet = cyan, haiku = grey).

ADR: `0006-model-family-grouping.md` — group in Swift, not SQL, so price-table changes don't require schema migrations.

### 4.2 A3 — Forecast

Two independent predictions, same algorithm:

1. **5h session block hit-time** — given current pct used `X`, time elapsed in block, and recent burn rate `r`, predict whether `1 - X` will be consumed before the block resets.
2. **Weekly hit-time** — same, against the weekly window.

Algorithm (ADR-0005):
- Buckets: 5-minute over the last 60 minutes of cost data (12 buckets max)
- Smoothing: EWMA with α = 0.4
- Degrades to linear (used / elapsed) if fewer than 3 buckets exist
- Result includes confidence (`.low` <3 buckets, `.medium`, `.high` ≥10) and basis (`.ewma | .linear | .insufficient`)

```swift
struct ForecastResult {
    let willHit: Bool
    let hitAt: Date?               // nil if !willHit
    let confidence: Confidence
    let basis: Basis
}

actor Forecaster {
    func forecastSessionBlock(block: SessionBlockSnapshot, recent: [CostBucket]) -> ForecastResult
    func forecastWeekly(weekly: WeeklyUsageSnapshot, recent: [CostBucket]) -> ForecastResult
}
```

`EventsDatabase` adds:
```swift
func costPerBucket(start: Date, span: TimeInterval, bucketSize: TimeInterval) -> [CostBucket]
```

`AppCoordinator` runs the forecaster on every refresh tick and publishes `AppModel.forecast: ForecastSnapshot`.

The existing burn-rate notification (>2× linear pace) is **replaced** by the forecaster's prediction. Notifications fire only when `willHit == true` AND `confidence >= .medium`; below that threshold the notification is held back to avoid false positives during cold-start or sparse activity. The old `>2× linear pace` rule is removed — `Forecaster`'s `.linear` basis already covers the same case with explicit confidence reporting.

UI: hero-row subtitle `⏱ block hits in ~1h12m · medium` or `✓ won't hit`.

### 4.3 B3 — Week-over-week delta

```swift
// EventsDatabase
func costInWindow(start: Date, end: Date) -> Double
func cacheHitRateInWindow(start: Date, end: Date) -> Double
```

```swift
struct WeekDelta {
    let thisWeekCost: Double
    let lastWeekCost: Double
    var pctChange: Double? { lastWeekCost > 0 ? (thisWeekCost - lastWeekCost) / lastWeekCost : nil }
    let cacheHitDelta: Double      // pp (percentage points)
}
```

Window boundary: Monday 00:00 UTC, matching `WeeklyUsageSnapshot` reset (ADR-0001).
First-week fallback: `pctChange == nil` → UI shows `first week`.

UI: popover row `Δ vs last week  +12% · cache +3pp` between hero and 7d chart.

### 4.4 B2 — Export

Entry points:
- Menubar dropdown `Export Usage…`
- Popover keyboard `e`

Both open the same panel:

```
Range:     today | last 7d | last 30d | this week | last week | custom
Dimension: per-repo daily | per-tool daily | per-model daily | raw events
Format:    CSV | JSON
→ NSSavePanel → write file → reveal in Finder
```

```swift
enum ExportDimension { case perRepoDaily, perToolDaily, perModelDaily, rawEvents }
enum ExportFormat    { case csv, json }

struct EventsExporter {
    init(db: EventsDatabase)
    func export(range: DateInterval,
                dimension: ExportDimension,
                format: ExportFormat,
                to url: URL) async throws
}
```

**Mandatory header** (defends against reimbursement disputes — ADR-0007):

```csv
# claudegrain export — primaryTool attribution, public price-table cost estimate.
# Not the Anthropic billing source of truth. Generated 2026-05-05 14:32:11.
# Range: 2026-04-29 → 2026-05-05  Dimension: per-repo daily
date,repo,events,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd
...
```

JSON exports carry the same disclaimer in a top-level `_meta` object.

### 4.5 C1 — Per-repo soft budgets

```swift
struct RepoBudget: Codable {
    let repo: String                // path key (UsageEvent.cwd)
    let dailyUSD: Double?
    let weeklyUSD: Double?
}

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [String: RepoBudget]
    var globalDefaultDailyUSD: Double   // replaces old repoOverspendThresholdUSD
    func setBudget(repo: String, daily: Double?, weekly: Double?)
    func resolve(repo: String) -> RepoBudget   // per-repo overrides global
}
```

Storage: UserDefaults key `budgets.v2` (JSON map). Migration: read old `repoOverspendThresholdUSD` once into `globalDefaultDailyUSD`, then drop the old key (no fallback retained).

`NotificationManager` switches from a single threshold to `BudgetStore.resolve(repo:)`. Existing per-repo per-day cooldown remains.

UI: new Settings tab `Budgets`, with the global default row plus a list of recently-active repos (from `EventsDatabase.distinctRepos(since:)`, last 7d). Inline `⌥-click` on a popover top-repo row also opens a small sheet for that repo.

ADR: `0008-budget-storage.md` — UserDefaults JSON map, not SQLite.

### 4.6 C2 — Quiet hours

```swift
struct QuietHours: Codable {
    var enabled: Bool
    var startHour: Int           // 0–23, device local
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    // wraps midnight legitimately (e.g. 22:00 → 09:00)
}
```

Storage: UserDefaults `quietHours.v1`. Default `enabled = false`.

Scope: suppresses **all** notification kinds (threshold, burn-rate, block-reset, repo-overspend, C4 commitment). The menu bar icon and popover continue updating.

`NotificationManager.shouldDeliver(now:)` short-circuits on `quietHours.contains(now)`.

**v0.2 explicit non-feature**: missed notifications during quiet hours are **dropped**, not queued. A future "missed-notifications inbox" is a follow-up — ADR-0009.

UI: new Settings tab `Quiet Hours` with enable toggle, start/end pickers, time-zone label.

### 4.7 C3 — Pause-ingest

```swift
@MainActor
final class IngestPauseController: ObservableObject {
    @Published var isPaused: Bool          // persisted to UserDefaults
    func pause(); func resume(); func toggle()
}
```

Effects when paused:
- `FileWatcher` stopped, `IngestActor` quiesced. Resume runs a catch-up scan via existing cursor logic — no event loss.
- `DataSourceCoordinator` receives the existing `user toggle off` transition from ADR-0004 (moves it to `jsonlOnly`, OAuth polling halted). On resume the coordinator re-enters `oauthChecking`.
- The next `AppGroupStore.write()` tags the snapshot with `dataSource = "paused"` (consumed by widget for the `⏸` corner marker).
- `MenuBarLabel` status dot changes to `⏸`.
- Popover gains a top banner `Paused — last updated 12 min ago [Resume]`.

Entry points: menubar dropdown `Pause Ingest`, popover key `p`.

### 4.8 C4 — Self-commitment notification

When C1 fires a repo-overspend notification, the `UNNotification` carries actionable buttons:
- `MARK_PAUSED` (default)
- `IGNORE`

Tap (no button) opens the popover but does not change state.

```swift
struct Commitment: Codable {
    let id: UUID
    let repo: String
    let triggeredAt: Date
    let dailyOverspendUSD: Double
    var status: Status              // .open | .markedPaused | .ignored
}

@MainActor
final class CommitmentLog: ObservableObject {
    @Published private(set) var entries: [Commitment]
    func record(_ c: Commitment)
    func update(id: UUID, status: Commitment.Status)
}
```

Storage: `~/Library/Application Support/claudegrain/commitments.json` (separate file; not mixed into `cache.db`).

UI: popover footer mini link `Recent commitments [3]` opens a sheet listing time / repo / status.

The app does **not** kill or signal Claude Code. The commitment is purely a self-honesty marker.

ADR: `0010-commitment-log.md`.

### 4.9 D — Widget

#### Target wiring (ADR-0011)

WidgetExtension targets aren't expressible in `Package.swift`. Adding a top-level `.xcodeproj` (Xcode-hybrid model) is the chosen path:

- `Package.swift` continues to be the source of truth for `ClaudegrainApp` and `ClaudegrainCore`.
- `.xcodeproj` references the Swift package and adds a single `ClaudegrainWidget` extension target.
- `swift build` / `swift test` continue to work for everything except the widget.
- `scripts/build-dmg.sh` and `release.yml` switch to `xcodebuild -workspace -scheme Release` for DMG production.

#### App Group

Entitlement `group.dev.claudegrain.menubar` added to both targets.

ADR-0012: shared SQLite was rejected (cross-process WAL contention vs. low widget read frequency not worth it). Instead the widget reads a JSON snapshot:

```
shared container/
  snapshot.json
  snapshot.lock           // NSFileCoordinator
```

#### Snapshot

```swift
struct WidgetSnapshot: Codable {
    let version: Int                    // bump on schema change
    let generatedAt: Date
    let dataSource: String              // "oauth" | "jsonl" | "cli" | "paused"
    let sessionBlock: SessionBlockMini  // pct, resetAt
    let weekly: WeeklyMini              // pct, resetAt
    let todayUSD: Double
    let cacheHitRate: Double
    let topRepos: [RepoMini]            // up to 3
    let modelMix: [String: Double]      // family -> ratio
    let forecast: ForecastMini?
}

final class AppGroupStore {
    static let groupID = "group.dev.claudegrain.menubar"
    func write(_ snapshot: WidgetSnapshot) throws    // atomic, NSFileCoordinator
    func read() throws -> WidgetSnapshot?
}
```

`AppCoordinator` writes a snapshot 30 seconds (debounced) after each `AppModel` publish, and calls `WidgetCenter.shared.reloadAllTimelines()` to push it.

#### TimelineProvider

```swift
struct ClaudegrainProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry          // empty $0 stub
    func getSnapshot(in context: Context, completion: ...)  // reads latest snapshot
    func getTimeline(in context: Context, completion: ...)  // 5 entries × 15min
}
```

Snapshot fresh-window: <60s old → use directly; otherwise `placeholder`.

#### Sizes

- **Small**: 5h block ring + pct, reset countdown, today $.
- **Medium**: 5h ring + weekly bar + today $ + forecast subtitle.
- **Large**: medium + top-3 repos with sparklines + model-mix row.

Widget views use a self-contained Phosphor-style render pipeline. They do **not** import `ClaudegrainApp/ReceiptComponents` (private fonts, monolithic layout). Widget bundle copies `JetBrainsMono-Regular.otf`.

#### State markers
- `dataSource == "paused"` → corner `⏸`, last values dimmed.
- `generatedAt` >5min old → `⚠ stale` corner.
- No snapshot file → `Open Claudegrain to start` placeholder.

### 4.10 E — Polish

#### E1 — First-run onboarding

Trigger: `UserDefaults.bool("onboardingCompleted.v0_2") == false`. Flag is **versioned** (ADR-0013) so future minor versions can force a re-walk.

Form: in-popover 4-step card (not a full-screen modal):

1. *"Hi — claudegrain tracks your Claude Code usage locally."* Highlight hero metric.
2. Pick the menu-bar primary metric (live preview as user clicks).
3. Set a daily budget? Skip / $10 default / custom.
4. Add the desktop widget? Open Widget Gallery / Maybe later.

Each step has a `Skip onboarding` link in the lower-left that writes the flag and exits.

```swift
@MainActor
final class FirstRunController: ObservableObject {
    @Published var step: Step?            // nil = done
    func startIfNeeded()
    func advance()
    func skip()
}
```

#### E2 — Empty states

| Scenario | Banner / message |
|---|---|
| First install, no jsonl, OAuth fails | `No Claude Code activity yet. Run claude once and come back.` |
| OAuth keychain miss | Top banner: `Estimated values · log into Claude Code for live limits` |
| 5h block dormant (no activity in last 5h) | `No active session block. Next request starts a new one.` |
| Pause active | (covered in C3) |
| jsonl parse errors > 5% of files | Top banner: `Some files couldn't parse — see Logs` |

```swift
enum EmptyState {
    case noActivity, noOAuth, noSessionBlock, parseErrors(count: Int)
    var headline: String; var detail: String?; var action: Action?
}

struct EmptyStateBanner: View { ... }
```

#### E3 — Keyboard shortcuts

Popover hint row extended:

```
r  refresh           (existing)
o  open Settings     (existing)
e  Export…           (B2)
p  Pause / Resume    (C3)
b  Budgets tab       (C1)
q  Quiet hours       (C2)
?  Show all keys
```

`?` expands a sheet listing all bindings.

#### E4 — Logs

Settings → About → `Reveal logs in Finder`. Logs path: `~/Library/Logs/claudegrain/claudegrain.log`. Uses `os.Logger` rotation (no in-app viewer in v0.2).

#### E5 — Bumps

- `VERSION` → `0.2.0`
- New `CHANGELOG.md` section `[0.2.0]` enumerating A1 / A3 / B2 / B3 / C1 / C2 / C3 / C4 / D / E
- `README.md` widget screenshot

## 5. Domain language additions

Adding to `CONTEXT.md`:

- **Model Family** — Opus / Sonnet / Haiku / unknown. Derived in Swift from `UsageEvent.model`.
- **Forecast** — EWMA-based prediction of when current 5h block / weekly window will hit 100%.
- **Budget** — per-repo daily/weekly soft cap. Triggers a notification when crossed; does not block requests.
- **Quiet Hours** — local-time window during which all notifications are suppressed (not queued).
- **Commitment** — log entry recording that the user marked a repo as paused after a budget breach. App-side honesty marker, not a process-level pause.
- **Snapshot** — JSON file in the App Group container; the widget's read-only view of the main app's state.

## 6. Data flow (consolidated)

```
~/.claude/projects/**.jsonl
       │ FSEvents
       ▼
  FileWatcher ─────── pause toggle ─── IngestPauseController (C3)
       │
       ▼
  IngestActor (JSONLReader → JSONLParser → CostCalculator)
       │
       ▼
  EventsDatabase  (~/Library/Application Support/claudegrain/cache.db)
    queries:
      costPerDay / tokensSince        (existing)
      costPerModel                    (A1)
      costPerBucket(5min)             (A3)
      costInWindow(start, end)        (B3)
      distinctRepos(since:)           (C1)
       │
       ▼
  AppCoordinator (every refresh tick)
    ├─ Forecaster.run()                  (A3)
    ├─ WeekDelta.compute()               (B3)
    ├─ ModelMix.compute()                (A1)
    ├─ BudgetStore.check()               (C1)
    ├─ NotificationManager.evaluate()
    │     ├─ QuietHours.gate()           (C2)
    │     └─ CommitmentLog.record()      (C4)
    └─ AppGroupStore.write(snapshot)     (D, debounced 30s)
       │
       ├──► AppModel (Combine) ──► popover / menu bar / Settings
       │
       ▼
  shared container/snapshot.json
       │
       ▼
  ClaudegrainWidget (TimelineProvider, 15-min reloads)
       └─ Small / Medium / Large views

EventsExporter (B2): on-demand, reads EventsDatabase, writes via NSSavePanel.
DataSourceCoordinator (existing): publishes SessionBlock / Weekly snapshots into AppModel,
  consumed by Forecaster and WeekDelta. Unchanged from 0.1.
```

## 7. Error handling matrix

| Failure | Behavior | User-visible |
|---|---|---|
| OAuth 401/403 | ADR-0004 state machine → `oauthAuthError` → `jsonlOnly` | Banner: `Estimated · sign in for live limits` |
| OAuth 429 / 5xx | `oauthBackoff`, UI holds last good snapshot | No banner; numbers freeze |
| jsonl single-file parse failure | Skip file, increment counter | Banner above 5% failure rate |
| `EventsDatabase` write failure | Log + 3 retries → in-memory fallback | Banner: `Cache write failed — see Logs` |
| `Forecaster` insufficient data | Fall back to linear; if still insufficient, `willHit = false` | Forecast badge hidden |
| `AppGroupStore` write failure | Log; do not throw out of refresh | Widget shows stale snapshot |
| Widget snapshot file missing | Placeholder copy | Widget reads `Open Claudegrain to start` |
| Pause active during widget reload | Snapshot written with `dataSource = "paused"` | Widget `⏸` corner |
| `BudgetStore` migration failure | Read of old key fails → `globalDefaultDailyUSD = 10.0` | Silent |
| `QuietHours` cross-midnight | Normalize: end < start → spans next day | Silent |
| `FirstRunController` step exception | `skip()` is called, flag set, main UI unblocked | Silent |
| Export disk-full | NSSavePanel write throws → alert | Modal: `Couldn't write — disk full?` |

Global rule (already established in ADR-0004): the UI always has data. When sources are unavailable we fall back to estimates plus a banner; we never spinner-stuck.

## 8. Testing strategy

| Module | New tests | Branch |
|---|---|---|
| `ModelFamily.parse` | 8 model-id parse cases | core-data |
| `EventsDatabase` (4 new queries) | 12 cases (4 queries × 3 fixtures) | core-data |
| `Forecaster` | 5 scenarios (empty / low / steady / accelerating / decelerating) | core-data |
| `WeekDelta` | window boundary + first-week nil | core-data |
| `EventsExporter` | 8 byte-equal fixtures (4 dim × 2 fmt) | surfaces |
| `BudgetStore` | migration + resolve precedence + persistence | control |
| `QuietHours` | cross-midnight, time-zone, edge boundaries | control |
| `IngestPauseController` | resume catch-up, persistence | control |
| `CommitmentLog` | round-trip + status transitions | control |
| `NotificationManager` (extended) | quiet-hours suppression, budget resolve hookup | control |
| `WidgetSnapshot` | round-trip + version-key tolerance | widget |
| `AppGroupStore` | concurrent read/write, corrupted-file recovery | widget |
| `FirstRunController` | startIfNeeded idempotent + version-key isolation | polish |
| `EmptyState` | trigger conditions per state | polish |

Target test count: ~95 (from 38 in v0.1.2).

Manual / integration:
- 6 widget screenshots (3 sizes × 2 themes) per release smoke check
- Onboarding 4-step walkthrough at each branch merge
- Pause/resume across 60s with concurrent jsonl writes (verify catch-up integrity)

CI changes:
- `release.yml` switches DMG build step to `xcodebuild` (widget needs it)
- Add `test.yml` (new) running `swift test` on every PR

## 9. Risk register

1. **OAuth `oauth/usage` endpoint deprecated** — pre-existing risk in 0.1; the forecaster degrades to JSONL estimates, not blocking.
2. **WidgetKit on macOS 14.0** — older minor versions of macOS 14 lack `AppIntent`-based widget interaction. We deliberately ship lowest-common-denominator (display-only) and keep `LSMinimumSystemVersion = 14.0`.
3. **App Group entitlement on ad-hoc signing** — App Groups work under ad-hoc signing on a local Mac (verified in path A); Path B (Developer ID) re-issues identifiers, already noted in `docs/RELEASE.md`.
4. **`xcodebuild` cold-build time on `macos-14` runner** — first build may exceed 10 min. Cache `DerivedData` in CI; further optimization is deferred until measured.
5. **Onboarding flag versioning** — flag carries the version (`onboardingCompleted.v0_2`). 0.3 will use `v0_3` if it adds new concepts. This is intentional.
6. **EWMA forecaster post-burst cooldown overshoot** — after a burst, the EWMA decays slowly toward zero. Acceptable in v0.2; α tuning or freshness gating deferred to follow-ups based on issue feedback.

## 10. ADRs to add under this spec

- `0005-forecast-ewma.md` — α = 0.4, 5-min buckets, degradation strategy
- `0006-model-family-grouping.md` — group in Swift, not SQL
- `0007-export-disclaimer.md` — mandatory CSV/JSON header
- `0008-budget-storage.md` — UserDefaults JSON map, not SQLite
- `0009-quiet-hours-suppress-only.md` — drop, don't queue
- `0010-commitment-log.md` — separate JSON file, actionable UN buttons
- `0011-widget-target-via-xcodeproj.md` — Xcode-hybrid model
- `0012-snapshot-json-not-sqlite.md` — App Group file vs cross-process db
- `0013-onboarding-versioned-flag.md` — version-suffixed `onboardingCompleted.v_N` keys

## 11. Acceptance criteria

`0.2.0` ships when, on a clean Mac running macOS 14+:

- [ ] All ten subitems are functional from a fresh install (widget surfaces in the macOS Widget Gallery; onboarding step 4 prompts the user to add it)
- [ ] `swift test` is green; new test count meets §8 targets
- [ ] DMG build via `xcodebuild` completes in under 15 min on `macos-14` runner
- [ ] Three widget sizes render correctly in both Phosphor and Thermal themes
- [ ] Onboarding completes in ≤4 steps and the flag persists across launches
- [ ] Pausing for ≥60s and resuming reproduces no data loss vs. control run
- [ ] Exported CSV opens cleanly in Numbers and contains the disclaimer header
- [ ] All nine new ADRs landed and cross-linked from the spec
- [ ] CHANGELOG `[0.2.0]` enumerates every shipped subitem
