# ADR-0012 — Widget snapshot contract

Status: accepted (2026-05-10)
Supersedes: none
Touches: ADR-0001, ADR-0002, ADR-0011

## Context

The widget extension runs in its own sandboxed process. It cannot
read `cache.db` (Application Support), `commitments.json`, or any
other state the host owns. It needs a tightly bounded, versioned
snapshot of just the values it renders. WidgetKit also imposes a
~30 MB memory ceiling and a ~40-reload/day budget per widget, so
the snapshot must stay small and write-throttled.

## Decision

Single flat JSON file `widget-snapshot.json` written to the App
Group container at
`~/Library/Group Containers/group.dev.claudegrain.shared/`.
Atomic write (`Data.write(to:options: .atomic)`).

### Schema (v1)

Defined in `Sources/ClaudegrainCore/Widget/WidgetSnapshot.swift`.
Both host and extension link Core; no duplication.

```
WidgetSnapshot {
    schemaVersion: Int           // currently 1
    generatedAt: Date
    language: String             // "en" | "zh"
    primaryMetric: String        // "spend" | "tokens" | etc.
    dataSourceStatus: String     // "oauthLive" | "jsonlOnly" | …

    sessionBlockPercent: Double?
    sessionBlockResetAt: Date?
    weeklyPercent: Double?
    todayCostUSD: Double
    todayTokens: Int

    weekSpend: [Double]          // 7 entries oldest → newest

    topRepos: [Repo]             // up to 3
    cacheHitRate: Double
}
Repo {
    name: String
    costUSD: Double
    percentOfDay: Double         // 0..1
}
```

Target file size: <8 KB. The 3-repo cap, no per-tool list, and no
model mix keep the JSON small.

### Schema versioning

`schemaVersion` is incremented when fields are renamed or removed.
Adding optional fields does not bump the version (extensions
ignore unknown keys via `JSONDecoder` defaults).

`WidgetSnapshotIO.read()` returns `nil` when
`snapshot.schemaVersion > WidgetSnapshot.currentSchemaVersion`. The
extension treats this as "no snapshot" and renders its placeholder
state, never crashes. This guards against rollback scenarios where
the widget extension is older than the host.

### Write throttle (host side)

`AppCoordinator.writeWidgetSnapshotIfDue()` runs after every
`refreshDerivedNow()` but enforces a 5-minute floor between disk
writes via `lastWidgetWriteAt`. WidgetKit's daily reload budget
(~40) would be drained in minutes by JSONL-driven ingest bursts.
Five minutes balances staleness against budget; the extension's
own timeline policy (`.after(15min)`) re-reads the file even
without a host kick.

After a successful write, the host calls
`WidgetCenter.shared.reloadAllTimelines()` — also throttled by the
same 5-min gate, since the call happens immediately after the
write.

### Read path (extension side)

`WidgetSnapshotIO.appGroupContainer()` resolves the container.
Returns `nil` if the host is not entitled (dev / unsigned). The
extension's `WidgetSnapshotProvider.currentEntry()` returns a
placeholder entry in that case.

A snapshot is "stale" if `Date().timeIntervalSince(generatedAt) >
30min`. Stale entries render at 0.6 opacity to signal age without
disappearing.

## Consequences

### Positive

- Widget extension binary stays tiny — no GRDB, no SQLite, no
  ingest pipeline. Just `Codable` decoding.
- Schema versioning lets host + extension ship at different
  cadences without crashing each other.
- 5-minute write throttle keeps WidgetKit budget healthy.

### Negative

- Effective freshness floor is 5 minutes. Acceptable for a
  budget/quota dashboard; would not be acceptable for a stopwatch.
- If the host app is never run, the widget shows whatever
  snapshot existed at last quit. Documented in the user-facing
  copy via the relative-time label ("4h ago", dimmed when stale).
- App Group requires real codesigning. Ad-hoc / dev builds
  cannot read the shared container. Documented in
  `scripts/build-dmg.sh` warnings.

## Alternatives considered

- **SQLite shared between host and extension.** GRDB inside the
  extension would blow past the 30 MB memory ceiling. Also adds
  multi-process write contention to a database that ADR-0002
  explicitly chose to keep single-writer.
- **XPC service the extension calls into the host for data.**
  Requires the host to be running for the widget to render
  current data. Forces interactive activation. Out of scope for
  v0.2's "set it and forget" widget posture.
- **Multiple JSON files (one per widget family).** No clear win;
  the single file is already <8 KB and re-encoding is cheap.
