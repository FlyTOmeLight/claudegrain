# ADR-0015 — Tool attribution v2 (per-block proportional split)

Status: accepted (2026-05-10)
Supersedes: ADR-0003 (`primaryTool` simplification stays available
in `--legacy-attribution` mode for audit comparison).
Touches: ADR-0001, ADR-0002.

## Context

ADR-0003 attributed 100% of a turn's tokens to its **first**
`tool_use` block, with the explicit caveat that the UI must
label this "by primary tool" — not precise per-tool billing.
Cost: a turn that opens with a no-op `Bash echo` and then runs a
`Read` returning 100KB credits the entire turn to `Bash`. Power
users have flagged this since v0.1.

v0.3 ships a documented split. This ADR records the algorithm.

## Decision

**Block-count proportional** with **dedup by tool name**.

Given a turn with `tool_use` blocks `[A, B, A, C]`:

```
unique counts = {A: 2, B: 1, C: 1}
total blocks  = 4
shares        = {A: 0.5, B: 0.25, C: 0.25}
```

Each tool's attributed cost = `share × turn_total_cost`.
Each tool's attributed tokens = `share × turn_total_tokens`
(same denominator across input / output / cache classes).

Input tokens are split the same way — they were the prompt that
caused the entire turn, so any block that appeared in the
response can be said to have shared in causing them. Equal
treatment to output tokens keeps the math consistent and the
implementation single-pass.

## Why not byte-weighted

Considered: weight each block by `len(tool_input) +
len(tool_output)`. Rejected because:

- Bytes ≠ tokens. JSON tool inputs are whitespace-sensitive, and
  truncating large outputs (Read on a 1MB file) produces
  byte-vs-token ratios that swing 100×.
- Test fixtures would need to encode every JSON-quirk case.
- Block-count is deterministic across re-renderings of the same
  log line; byte-weight is not.

We document the limitation: a single-byte `Bash` block and a
100KB `Read` block get equal credit. That is incorrect in the
literal billing sense but stable, predictable, and a strict
improvement over "first wins". Users who want to dig into the
actual byte distribution can use the legacy mode plus their own
post-processing.

## Algorithm

```swift
extension UsageEvent {
    var toolShares: [String: Double]? {
        guard !tools.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for t in tools { counts[t, default: 0] += 1 }
        let n = Double(tools.count)
        return counts.mapValues { Double($0) / n }
    }
}
```

For aggregation:

```swift
for event in eventsInWindow {
    guard let shares = event.toolShares else { continue }
    let totalCost = event.costUSD
    let totalTokens = event.totalTokens
    for (tool, share) in shares {
        bucketCost[tool, default: 0] += totalCost * share
        bucketTokens[tool, default: 0] += Int(Double(totalTokens) * share)
    }
}
```

`primary_tool` remains a column on the events table (`tools.first`)
for backwards compatibility with v1 audit queries. New queries
read `toolShares` instead.

## Migration

ADR-0002 says SQLite is a materialized view of JSONL. Schema bump
on first v0.3 launch:

1. Add column `tools_json TEXT` to `events`.
2. Existing rows: leave NULL. Aggregation falls back to
   "first tool wins" for legacy rows (computed on the fly from
   `primary_tool`).
3. Optionally trigger a full rebuild from JSONL via
   `IngestActor.bootstrap` to backfill `tools_json` for the
   90-day window. Surfaced as a "Rebuilding stats…" banner
   (P5-T05's `model.isReindexing` flag).

The legacy path stays valid forever — a tool with shares == nil
just contributes 100% to its primary_tool. So the new aggregator
can run over a mixed-version table without crashing.

## --legacy-attribution flag

Settings → Advanced → "Audit attribution" toggle re-runs the
aggregation pipeline with v1 semantics: ignore `tools_json` /
`toolShares`, use only `primary_tool`. Lets users diff old vs.
new numbers and decide whether the change matches their intuition.
Plumbing only; no separate UI flow.

## Consequences

### Positive

- Per-tool numbers reflect what actually consumed the tokens, not
  arbitrary turn-ordering.
- Documented and stable; deterministic across log replays.
- Migration is non-destructive (legacy rows keep working).

### Negative

- Numbers visibly change for existing users. CHANGELOG must call
  this out loudly. Audit toggle softens the surprise.
- One block of `Bash` running `echo hi` gets the same share as
  one block of `Read` returning 100KB. Documented limitation.
- `tools_json` column adds ~50–200 bytes per event — for 100k
  events that's ~10MB. Acceptable for the materialized view per
  ADR-0002.

## Out of scope

- Changing what counts as a "tool" (still the JSONL `name` field,
  no normalization of MCP-prefixed names).
- Per-tool subtotals by repo (additive, but a separate query;
  defer to v0.4).
- Real per-tool billing using upstream API metadata. Anthropic's
  message API does not expose per-block token attribution; we
  cannot do better than this without an upstream change.
