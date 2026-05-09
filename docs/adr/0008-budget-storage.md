# Per-repo budgets stored in UserDefaults JSON

## Status

accepted

## Context

C1 ships per-repo soft budgets. Storage options:

1. New SQLite table inside `cache.db`.
2. Separate plist / JSON file in Application Support.
3. UserDefaults JSON-encoded map.

Budgets are sparse (most users will configure ≤10 repos), small (one
struct per repo), and must persist across app upgrades. They are not
queried by SQL operations and are not tied to the event log.

## Decision

UserDefaults key `budgets.v2`, value is a JSON-encoded
`[String: RepoBudget]` map (repo path → budget). Global default lives
under a separate key (`globalDefaultDailyUSD`).

`BudgetStore.migrateLegacyKeyIfNeeded()` reads 0.1.x's single
`repoOverspendThresholdUSD` value into `globalDefaultDailyUSD` once,
then removes the legacy key.

## Considered options

- **SQLite table**: keeps everything in one file but ties budget schema
  changes to the materialized-view rebuild cycle (ADR-0002). Overkill
  for a flat key-value preference.
- **Separate JSON file**: clean but introduces a third persistence
  surface (alongside `cache.db` and `commitments.json`). Not worth it
  for sparse data.

## Consequences

- Migration is one-shot and idempotent. Re-installs with a fresh
  defaults domain start with `globalDefaultDailyUSD = 10.0`.
- `BudgetStore` is `@MainActor` because it publishes change events to
  SwiftUI. Notifications consult it from the main actor too.
- The map's value type (`RepoBudget`) is `Codable`. Adding fields is
  forward-compatible if the new fields are optional.
