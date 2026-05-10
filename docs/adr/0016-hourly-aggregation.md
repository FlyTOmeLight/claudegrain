# ADR-0016 — Hourly bucket aggregation for cycle-aware forecast

Status: accepted (2026-05-10)
Touches: ADR-0001 (data sources), ADR-0002 (cache schema),
ADR-0005 (forecaster).

## Context

The v0.1 `Forecaster` projects future cost by extrapolating the
current 5-minute burn rate uniformly forward. Real users have
strong time-of-day patterns: heavy mornings, light evenings,
weekend lulls. A 5pm extrapolation over a 5h session block
multiplies a non-representative slice across remaining hours
where the user typically slows down — the forecast over-shoots,
the v0.2 commitment alerts (ADR-0010) misfire.

Theme D wants two artefacts:

1. **24-hour heatmap** in the popover (7 weekday rows × 24 hour
   columns) so users can see *where in the day they spend most*.
2. **Cycle-aware forecast** that blends current burn with the
   historical hourly average for the remaining hours.

Both need the same primitive: a per-(weekday, hour) summary of
recent spend. This ADR records the storage choice.

## Decision

Pre-aggregated table `hourly_buckets(weekday INT, hour INT,
cost_usd REAL, tokens INT, last_event_at REAL, sample_count
REAL, PRIMARY KEY(weekday, hour))`. Updated incrementally on
every event commit by `IngestActor`. Decayed via 7-day
half-life EWMA so the table tracks *recent* patterns rather
than all-time averages.

168 rows total (7 × 24). Updates are O(1) per event (single
indexed UPSERT). Reads for the heatmap are O(168) — sub-ms.
The forecaster reads a slice (typically 5–10 hours for a
session block) — also sub-ms.

### Update rule

On each event with cost `c` and timestamp `ts`:

```
weekday = Calendar.current.component(.weekday, from: ts)  # 1=Sun … 7=Sat
hour    = Calendar.current.component(.hour, from: ts)     # 0…23

elapsed_days = (now - last_event_at) / 86400
decay        = 0.5 ^ (elapsed_days / 7)        # 7-day half-life

new_cost   = old_cost   * decay + c
new_tokens = old_tokens * decay + event_tokens
new_count  = old_count  * decay + 1
last_event_at = now
```

`sample_count` decays alongside cost so the forecaster can floor
on **effective** sample size — an hour that hasn't seen activity
in 6 weeks decays to ~0.025× weight and stops dominating the
projection.

### Sample-count floor

The forecaster ignores buckets with `sample_count < 1.0`. With
a 7-day half-life, this corresponds to roughly "1 event in the
last 7 days" — strong enough to be a real pattern, weak enough
to surface most users' habits.

### Weekday encoding

Stored as raw `Calendar.current.component(.weekday, ...)` (1=Sun
… 7=Sat per Apple's convention) to avoid locale-dependent
firstWeekday math at write time. UI re-orders for display.

## Considered & rejected

**(β) On-demand aggregation via `costPerBucket`.** Reuses
existing infrastructure (no schema bump). Rejected because:

- Heatmap reads scan all events in window each time popover
  opens (~hundreds of rows for a typical day, but 90-day
  retention means up to 50k rows for the cycle-aware
  forecaster). Multi-second response would block the popover.
- The 168-row table is so small that keeping it incremental is
  trivial. The complexity tax of an extra UPSERT per event is
  low; the savings on every read are real.

**(γ) Time-series database (DuckDB / TimescaleDB-like).**
Rejected — adds a heavyweight dependency for one tiny summary
table. GRDB-only baseline (per CLAUDE.md "Don't add deps")
holds.

## Migration

v5 schema bump in `EventsDatabase.migrate`. New rows are
populated incrementally from the time of migration. The first
~7 days will have thin sample counts; the forecaster falls back
to the v0.1 burn-rate path during that warm-up via the
sample-count floor. No backfill, no rebuild.

## Out of scope

- Hourly buckets per repo / per tool. Aggregate only — keeps the
  table to 168 rows and stops the heatmap from becoming a
  dashboard.
- Variable EWMA half-life. 7 days is short enough to track new
  habits, long enough to ignore single-day spikes.
- Timezone changes during the window. We use `Calendar.current`
  at write and read; users who travel will see slight smear in
  affected hours but the sample floor + decay heal it within a
  week.
