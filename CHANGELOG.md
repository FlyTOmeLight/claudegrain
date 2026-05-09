# Changelog

All notable changes to **claudegrain** are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6-rc9] — 2026-05-10

CI fix only — bumps runner from `macos-14` to `macos-15` so the
xcodegen-generated project (`objectVersion = 77`) can be read by
CI's Xcode. No source changes.

## [0.1.6-rc8] — 2026-05-10

CI fix only — re-tags rc7 with the missing `brew install xcodegen`
step in `.github/workflows/release.yml`. Without it, the CI build
fails before invoking `xcodebuild`. No source changes.

## [0.1.6-rc7] — 2026-05-10

Phase 4 of v0.2 — desktop widget. Adds a WidgetKit extension
(small / medium / large) backed by a single JSON snapshot the host
app writes into an App Group container. Restructures the build
system to support the embedded `.appex`.

### Added
- `Sources/ClaudegrainCore/Widget/WidgetSnapshot.swift` —
  `Codable` cross-process contract: hero metrics + 7-day spend
  array + top-3 repos + cache hit. Schema versioned; readers
  drop snapshots from a higher version (rollback-safe).
- `WidgetSnapshotIO` — atomic writer/reader resolving the App
  Group container `group.dev.claudegrain.shared`. Falls back to
  Application Support for SwiftPM-only dev runs.
- `Sources/ClaudegrainWidget/` — new `.appex` target.
  - `ClaudegrainWidgetBundle` (@main) + `ClaudegrainSpendWidget`.
  - `WidgetSnapshotProvider` (`TimelineProvider`) reads the host
    file, returns `.after(15min)` policy, dims stale entries.
  - `ClaudegrainEntryView` switching on `widgetFamily`. Three
    layouts: hero %, hero + sparkline, hero + sparkline + top
    repos + cache. EN/ZH inline localization (extension cannot
    import host's `L`).
- `AppCoordinator.writeWidgetSnapshotIfDue` — runs after every
  `refreshDerivedNow()`, throttled to one disk write per 5 min,
  followed by `WidgetCenter.shared.reloadAllTimelines()`.
- `Claudegrain.xcodeproj` (committed, generated from
  `project.yml` via `xcodegen`). Two targets: ClaudegrainApp
  (host) + ClaudegrainWidget (.appex). Both link the SwiftPM
  `ClaudegrainCore` library.
- App Group entitlement on both targets.
- ADR-0011 (widget packaging — Xcode project alongside SwiftPM)
  + ADR-0012 (widget snapshot contract).

### Changed
- `scripts/build-dmg.sh` now builds via `xcodebuild` (regenerates
  the project with `xcodegen` first). `--deep` codesign handles
  the embedded `.appex`. New `DEVELOPMENT_TEAM` env required for
  the App Group entitlement to validate at runtime.
- `Package.swift` — `ClaudegrainApp` excludes `Info.plist` +
  `Claudegrain.entitlements` and links `WidgetKit` so
  `swift build` continues to work.

### Verification
- `swift build` clean
- `swift test` 99/99 green (6 new `WidgetSnapshotTests`)
- `xcodebuild Claudegrain` (Release): BUILD SUCCEEDED for both
  targets

## [0.1.6-rc6] — 2026-05-10

Phase 5 of v0.2 (polish — partial). Settings UI cleanup + popover
keyboard shortcuts + accessibility + OAuth-degraded surfacing.

### Added
- Real keyboard shortcuts on the popover footer: `F2` (Settings),
  `F5` / `⌘R` (Refresh), `E` (Export), `P` (Pause/Resume),
  `F10` (Quit). `⌘,` aliases Settings. Tooltips on every footer
  button show the key hint.
- `WeekChartPlaceholder` for the 7-day chart cold-start state —
  replaces the previous synthesized ramp that misled users into
  thinking they were looking at real data.
- Cold-start empty state for `TopCostsList`
  ("watching ~/.claude/projects…").
- `OAuthDegradedBanner` surfaces ADR-0004's `oauthAuthError` /
  `oauthDeprecated` states with a dismiss button — ends silent
  fallback to JSONL estimates.
- "as of HH:MM" stale-subtitle in the header strip whenever the
  display has dropped off `oauthLive`.
- Live 1 Hz clock in header (was previously frozen between events).
- VoiceOver labels on `VitalRow` (`<label>: N percent` + reset
  countdown) and `HeroSpend` (`$X.XX, today/all-time`). Decorative
  dividers + ASCII bars are now `accessibilityHidden`.
- `LiveDot` pulse and other looping animations now respect
  `accessibilityReduceMotion`.
- Animation tokens (`Animation.cgFast` / `cgMedium` / `cgSlow` /
  `cgSpin` / `cgPulse`) in `Motion.swift`. Source of truth for all
  view animation timings.
- `KeyEquivalent.fnF2` / `.fnF5` / `.fnF10` helper extension.
- Empty-state hint copy on `CommitmentsSheet` and `BudgetsTab`.

### Changed
- `BudgetsTab` row UX: configured rows now visually distinct from
  default-inheriting rows (accent dot + filled vs. prompt-only
  TextField). Drops misleading `0.00` weekly placeholder for `—`.
  Bindings switched to `Optional<Double>` so prompts render the
  global default. Add section reorganized; Add button disabled
  until repo path is non-empty.
- `QuietHoursTab` adopts `Section` grouping + `.formStyle(.grouped)`
  for parity with `BudgetsTab`.
- `PauseBanner`, `ForecastBadge`, `OAuthDegradedBanner` now
  insert/remove with `.opacity` + `.move(edge: .top)` transitions
  at `cgMedium`.
- `HeroSpend` mode-switch (TOTAL ↔ TODAY) cross-fades sub-label +
  `ModelStackBar` in lockstep with the numeric cost transition.
- `StatusItemController.updateButton` memoizes the visible
  `(metric, valueText, severity-bucket)` signature; menu bar redraw
  count drops sharply on busy `AppModel` publish streams.

### Docs
- `docs/plans/v0.2-phase4-widget.md` — WidgetKit extension via
  Xcode project restructure plan (14 TDD tasks, ADR draft).
- `docs/plans/v0.2-phase5-polish.md` — full polish audit with
  P0/P1/P2 priority matrix and 19 task breakdown.

## [0.1.6-rc5] — 2026-05-05

Phase 3 of v0.2 — control. Adds proactive notification + ingestion
controls.

### Added
- Per-repo soft budgets (`BudgetStore`). Replaces the single
  `repoOverspendThresholdUSD` value (auto-migrated). New `Budgets`
  settings tab. (ADR-0008)
- Quiet Hours window suppresses all notifications during a configurable
  daily slice (cross-midnight supported). New `Quiet Hours` settings
  tab. (ADR-0009)
- Pause Ingest toggle — halts FSEvents + OAuth polling; resume runs
  catch-up via existing cursor logic. Right-click menu item, `p`
  footer button, popover banner.
- Repo-overspend notifications now carry actionable buttons
  (`Mark as paused` / `Ignore`). Responses are logged to
  `CommitmentLog` (separate JSON file). New `Recent commitments` sheet.
  (ADR-0010)
- Localization: ~30 new EN/ZH strings.

### Changed
- `NotificationManager` consults `BudgetStore.resolve(repo:)` instead
  of a single global threshold.
- `NotificationManager.fire(...)` gated on `QuietHours.contains(now)`.

### Docs
- ADR-0008 budget-storage
- ADR-0009 quiet-hours-suppress-only
- ADR-0010 commitment-log

## [0.1.0] — 2026-05-05

Initial public release.

### Added
- macOS menu bar app for real-time Claude Code usage tracking
- **Per-repo / per-tool / per-MCP / cache-hit attribution** — first tracker to
  break out usage by these dimensions
- Three-tier data source with automatic fallback:
  1. **OAuth path** — reads Claude Code token from macOS Keychain, calls the
     undocumented `api.anthropic.com/api/oauth/usage` endpoint
  2. **JSONL path** — parses `~/.claude/projects/**/*.jsonl` directly,
     drives all detail attribution and serves as fallback for rate limits via
     P90 estimation (`LimitEstimator`)
  3. **CLI path** — `claude /usage` shell-out as final safety net
- Local SQLite cache (`~/Library/Application Support/claudegrain/cache.db`)
  with 90-day retention; cursor-based incremental ingest via FSEvents
- V18 Phosphor Receipt UI — narrative single-paper layout with neon-green
  hero, ASCII dividers, 7d line chart, top-cost rows with per-row sparklines,
  cache savings breakdown, kbd-styled keyboard hints, paper-edge zigzag
- Phosphor (dark) + Thermal (light) theme switching via system color scheme
- Bundled fonts (no Google Fonts dependency): JetBrains Mono Regular/Bold,
  Space Mono Regular/Bold (both OFL-1.1)
- Settings panel with three tabs: General (login item, primary metric),
  Notifications (threshold/burn-rate/block-reset/repo-overspend toggles +
  sound picker), About
- UNUserNotificationCenter threshold alerts (session 70/90%, weekly 85%)
  with cooldown
- Login item toggle via SMAppService (off by default — explicit opt-in)
- 38 unit tests covering JSONL parsing, cost calculation, cursor robustness,
  SQLite repository, OAuth keychain/decoder, P90 estimator, ingestion
- DMG packaging script + GitHub Actions release workflow
- Custom `.icns` app icon (phosphor `$` glyph)

### Verified
- End-to-end spike against real local data: 27,259 events, 40 repos, 692
  jsonl cursors, OAuth endpoint returning 200 with live 5h + weekly figures
- Tests pass on macOS 14+ with Xcode-shipped Swift 6.3 toolchain

### Known limitations
- v0.1 OAuth `oauth/usage` endpoint is undocumented and may break without
  notice; the app degrades gracefully to JSONL path
- Per-tool attribution uses **primaryTool** strategy (first tool_use of each
  turn); see `docs/adr/0003-primary-tool-attribution.md`
- Per-row 7d sparkline data is currently mocked client-side; live wiring to
  `EventsDatabase.tokensSince` ships in 0.2

## [0.1.5-rc4] — 2026-05-05

### Fixed
- Boot stuck on "启动中" / blank session-block + weekly until manual F5.
  `AppCoordinator.start()` now kicks an immediate `ingest.refreshNow()`
  + `dataSource.refreshNow()` after stream wiring so the popover lands
  on real values without the user having to refresh once.

## [0.1.5-rc3] — 2026-05-05

### Fixed
- Fixed-mode popover overflow regression: WeekDeltaRow + ModelMixRow
  added in rc2 ran in both layout modes, blowing past the HD-screen
  height budget that `.fixed` mode protects. Now gated on `.scroll`
  mode (parity with SubtotalsBlock); ForecastBadge stays in both
  modes since it's hero-adjacent and tiny.

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
- "Export Usage…" right-click menu item + `e` keyboard shortcut.
- Localization for all new UI strings (EN + ZH).

### Changed
- `EventsDatabase` adds `perRepoDaily` / `perToolDaily` /
  `perModelDaily` / `rawEventsInRange` aggregations for export.
- Status bar item now responds to right-click with a context menu
  (Export Usage… / Quit). Left-click still opens the popover.

### Docs
- ADR-0007 — export disclaimer.

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
  `willHit` + confidence ≥ medium. The legacy `>2× linear pace` rule
  is removed (ADR-0005).

### Docs
- ADR-0005 — forecast EWMA decision
- ADR-0006 — model family grouped in Swift, not SQL

## [0.1.3] — 2026-05-05

### Added
- **TOTAL / TODAY hero tabs** — clickable toggle in the popover header
  switches the headline figure between all-time spend and today's spend.
  Backed by new `EventsDatabase.allTimeTotals()` SQL aggregation; published
  through `IngestActor.Snapshot.allTime` to `AppModel.allTimeTotals`.
- **F5 refresh spinner** — rotating ↻ glyph bound to `model.isRefreshing`
  with a 600ms minimum visible duration so the user perceives a real
  refresh pulse even when the snapshot returns instantly.
- **Internationalization (English / 中文)** — full `Localization.swift`
  string table covers every visible label, section header, button, status
  and Settings field. Language picker added to Settings → General;
  preference persists in UserDefaults; live re-render on switch.
- **Fixed (non-scroll) layout mode** — Settings → General → Layout toggle.
  Fixed mode drops the SubtotalsBlock so the receipt fits an HD screen
  without scrolling; popover height clamps to `NSScreen.visibleFrame`
  height as a safety net.
- `NSHostingController.sizingOptions = .preferredContentSize` + KVO so
  the popover height tracks the SwiftUI intrinsic content size in fixed
  mode (no manual NSSize math).
- `AppModel` forwards `Preferences.objectWillChange` so Settings changes
  propagate to the popover and menu bar label without restart.

### Fixed
- F2 settings re-open on `LSUIElement` apps — `sendAction(showSettingsWindow:)`
  alone failed to re-key the window after the user closed it once. Now
  walks `NSApp.windows` after the selector fires and brings the settings
  window forward explicitly.

## [0.1.2] — 2026-05-05

### Added
- Real per-repo 7d sparkline trend in top-cost rows (was mocked client-side)
- Real 7d weekly spend chart driven by `EventsDatabase.costPerDay`
- Burn-rate notification (toggle b): fires when current 5h block usage is at
  ≥2× linear pace expected for the elapsed time
- Repo-overspend notification (toggle d): fires per-repo per-day when today's
  cost crosses the configured threshold (default $10)
- F5 refresh action wired through `IngestActor.refreshNow` +
  `DataSourceCoordinator.refreshNow`
- LiteLLM-backed price catalog with disk cache + background refresh
  (`PriceTableLoader`); built-in defaults still cover cold-start
- Cross-file event dedup via `(message.id, requestId)` key — fixes double
  counting when an assistant turn appears in both parent transcript and a
  forked sidechain jsonl

### Performance
- Bootstrap pre-filters files whose persisted cursor matches on-disk size, so
  warm boots skip unchanged jsonl entirely (was full re-scan every launch)
- Bootstrap reads up to 6 files concurrently via `withThrowingTaskGroup`
- Initial cold scan still ~2.5 min for ~2k files; second launch is now near-
  instant

### Fixed
- v0.1.1 already fixed: `Bundle.module` blew up inside `.app` because SwiftPM's
  generated accessor didn't check `Contents/Resources/`. Resolved manually
  with FileManager existence checks across all candidate paths.
