# Changelog

All notable changes to **claudegrain** are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
