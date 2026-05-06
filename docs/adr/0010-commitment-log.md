# Commitment log: separate JSON file, actionable UN buttons

## Status

accepted

## Context

C4 turns repo-overspend notifications into actionable prompts: the
user clicks `Mark as paused` or `Ignore`. The app records the
response. This is a self-honesty marker; the app does not actually
signal Claude Code or any other process — pausing is purely the user's
commitment to themselves.

## Decision

- Notifications carry `categoryIdentifier = "REPO_OVERSPEND"` with two
  `UNNotificationAction`s: `MARK_PAUSED` (foreground), `IGNORE`.
- A `UNUserNotificationCenterDelegate` (`NotificationActionRelay`)
  receives the response and records a `Commitment` in `CommitmentLog`.
- Storage: separate JSON file at
  `~/Library/Application Support/claudegrain/commitments.json`. Not
  mixed into `cache.db` (different lifecycle, different access pattern,
  not subject to 90-day retention).
- The popover footer surfaces a `Recent commitments [N]` link that
  opens a sheet listing time / repo / status.

## Considered options

- **Persist in `cache.db`**: ties commitment lifetime to the event-log
  retention policy (90 days). Commitments deserve longer history —
  they're the user's own record, not derivable from JSONL.
- **Persist in UserDefaults**: lists in defaults grow unbounded and
  are not the right primitive. JSON file is more flexible for future
  filtering / export.
- **Actually pause Claude Code**: out of scope and would require
  process control we deliberately don't have. The marker is the
  feature.

## Consequences

- Commitments survive cache.db rebuilds.
- The `MARK_PAUSED` action does not trigger `IngestPauseController` —
  those are independent. (A future enhancement could chain them, but
  they have different semantics: ingest pause = stop reading jsonl;
  commitment = "I told myself I'd stop using Claude in this repo today".)
- The relay class is held strongly by `AppCoordinator` to keep the UN
  delegate alive across app lifetime.
