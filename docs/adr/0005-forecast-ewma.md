# Forecaster: EWMA over 5-min cost buckets

## Status

accepted

## Context

v0.2 needs a forecast of when the current 5h block / weekly window will
hit 100% used. Two forecasting failure modes to avoid:

- **Linear pace** (used / elapsed): too jittery — a single burst spikes
  the projection, then it stays high while the user goes silent.
- **Naive average over the whole window**: too slow — doesn't react
  when the user shifts pace mid-block.

We also can't easily import a heavyweight forecasting library: we run in
a sandboxed menu bar app, GRDB is the only existing dep, the prediction
runs every refresh tick, and signal quality is bounded by 5-min
granularity anyway.

## Decision

EWMA (exponentially-weighted moving average) over **5-minute cost
buckets** drawn from the last **60 minutes**, with **α = 0.4**.

The smoothed fraction-per-second is derived from the snapshot's
`usedFraction` (which already encodes plan-tier budget) by:

```
historicalFractionPerCost = usedFraction / sumCost     # fraction per $1 over elapsed window
smoothedFractionPerSecond = ewmaCost * historicalFractionPerCost / bucketSize
```

For uniform buckets this collapses to the same rate as a linear
projection (`usedFraction / elapsedSeconds`); for accelerating /
decelerating buckets, EWMA(α=0.4) heavily weights the latest bucket
(40%) while geometrically decaying older ones.

- Bucket count `n` drives confidence: 0 = `.insufficient/.low` (returns
  flat false), 1–2 = `.linear` (degrades to linear projection), 3–4 =
  `.ewma/.low`, 5–9 = `.ewma/.medium`, ≥10 = `.ewma/.high`.
- The legacy `>2× linear pace` burn-rate rule is **removed**, not run
  in parallel. `Forecaster` already handles the sparse case via its
  linear-degradation branch.
- Notifications only fire when `willHit == true` AND confidence ≥
  `.medium` — avoiding cold-start false alarms.

## Considered options

- **Linear extrapolation only** — fragile to bursts, easy to game with
  silence. Used as fallback only (`<3` buckets).
- **Holt-Winters / ARIMA** — overkill for 12 5-min buckets; harder to
  test deterministically.
- **Token-bucket-style decay over fixed wall clock** — equivalent to
  EWMA but harder to reason about α-tuning.

## Consequences

- α is hardcoded at 0.4 in v0.2. If the post-burst cooldown overshoot
  proves user-visible (issue feedback), revisit by extracting α to a
  named constant.
- The implementation derives a per-bucket fraction by attributing the
  snapshot's `usedFraction` proportionally across buckets — folds plan
  tier into the rate without us hardcoding plan budgets. This is the
  load-bearing simplification: we never need to know whether the user
  is on Pro / Max5 / Max20.
- All new logic is in `ClaudegrainCore/Forecast/` and is fully unit
  tested. No SQL schema change.
