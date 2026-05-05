# Model family grouping in Swift, not SQL

## Status

accepted

## Context

A1 wants per-family attribution (Opus / Sonnet / Haiku). Two storage
options:

1. Persist a `model_family` column in `events` and migrate.
2. Keep the raw `model` id in SQL and group in Swift.

## Decision

Option 2. `ModelFamily.parse(_:)` is a pure stdlib substring match in
`Sources/ClaudegrainCore/Model/ModelFamily.swift`. `EventsDatabase`
queries (`costPerModel`, `tokensPerModel`) return `[ModelFamily: ...]`
by aggregating `[String: ...]` rows in Swift.

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
- `ModelFamily` is `Hashable, Sendable` (no `Codable`/raw-string
  conformance) — Phase 2 may add `: String` if a UI rendering site
  needs a stable display string, but Phase 1 doesn't.
