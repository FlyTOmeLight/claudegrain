# Quiet hours: suppress, do not queue

## Status

accepted (v0.2 first version; "missed inbox" is a deferred follow-up)

## Context

C2 introduces a quiet-hours window during which notifications should
not interrupt the user. Two designs:

1. **Suppress**: drop notifications fired during the window.
2. **Queue**: hold notifications and deliver at window end.

## Decision

v0.2 ships **suppress only**. Notifications fired while
`QuietHours.contains(now)` returns true are dropped. The menu bar and
popover continue updating in real time, so the user can pull state
on demand.

## Considered options

- **Queue with redelivery at end**: requires an in-app inbox UI, retry
  logic for cooldown rules (we don't want to fire 5 stacked
  threshold-90% notifications at 9:01am), and edge cases for
  app-restart-during-window. Significant scope.
- **Per-kind toggles**: e.g. allow burn-rate during quiet hours but
  suppress threshold. Adds knobs without clear user value yet.

## Consequences

- A user who keeps the app running through the quiet window with no
  active session sees no notifications about state changes. They must
  open the popover.
- Cooldown logic remains correct because suppression happens at
  `fire(...)` time, not `evaluate(...)` — `repoOverspendFired` /
  `burnRateFiredFor` etc. are still updated by the evaluation pass.
  (Drift to "first day after quiet hours: skipped today's
  notification" is acceptable for v0.2.)
- Future "Missed during quiet hours" inbox can layer on without
  changing the suppression contract — just intercept at the same
  `shouldDeliver` gate.
