# ADR-0017 — Fixed-mode popover with ScrollView cap

Status: accepted (2026-05-10)
Touches: ADR-0011 (widget packaging is unaffected, but the host
popover sizing logic interacts with the same StatusItemController
that the widget snapshot pipeline reads from).

## Context

`Preferences.LayoutMode` has two values:

- `.scroll` — popover always 720pt tall, content wrapped in a
  `ScrollView` regardless of natural height.
- `.fixed` — popover sized to content's natural height, no
  scroll. The user-facing reason to use this is that scroll mode
  always feels under-filled on a half-empty receipt.

The fixed mode has been a recurring source of bugs since v0.3:

| Symptom | Root cause |
|---|---|
| popover top clipped behind menu bar (v0.3) | natural height > visibleFrame, NSPopover positioning gives no top margin |
| popover horizontally drifted off the menu-bar icon (v0.3 → v1.0.2) | NSPopover translates oversized content laterally to fit on-screen, using stale source-rect anchor |
| `--snapshot` looks fine, real popover clips top (v1.0.2) | offscreen NSWindow render bypasses NSPopover's visibleFrame clamp; snapshot is not a substitute for opening the real popover |
| every milestone re-introduces the bug after adding a new section | each new ReceiptBody section incrementally pushes natural height past visibleFrame on a 14" MBP |

Past fixes have all been *gates*: section X is only rendered when
`layoutMode == .scroll`, so fixed mode stays compact. This kept
recurring because each milestone added a new section without a
manual real-popover test (Memory: `feedback_popover_offset.md`,
`feedback_popover_anchor_drift.md`,
`feedback_local_test_before_release.md`).

The structural problem: gates put the burden on every contributor
to remember the policy. Even *I* re-broke it three times in v1.0.x.

## Decision

Two layered changes:

### 1. ScrollView wrap with `maxHeight: visibleFrame - 60` in fixed mode

`DetailPanel.ReceiptScroll.content` now uses a `ScrollView` for
**both** modes. Fixed mode adds a `.frame(maxHeight: maxH)` cap
where `maxH = max(400, NSScreen.main.visibleFrame.height - 60)`
plus `.fixedSize(horizontal: false, vertical: true)` so the frame
collapses to natural height when content fits.

This removes the entire class of "popover overflows visibleFrame
→ AppKit translates → anchor drifts" bugs structurally. The
popover frame is mathematically guaranteed never to exceed
visibleFrame, so AppKit never has to relocate it.

Trade-off: when content does exceed `maxH`, the popover scrolls
internally without the user explicitly choosing scroll mode. The
user can still tell the modes apart visually because fixed mode
sizes the frame to natural content (looks short for a sparse
receipt), while scroll mode is locked at 720pt.

### 2. Per-section opt-in in Settings

Five optional sections now ship in `Preferences.fixedSections`
(`Set<FixedSection>`, persisted as JSON in UserDefaults under
`fixedSections.v1`). Default: empty — fixed mode renders only
the always-on base sections (header, hero, vital limits, 7-day
chart, top repos, footer + barcode).

Toggles live in `Settings → General → 定屏模式 · 显示项`,
visible only when `layoutMode == .fixed`. A one-line warning above
the toggles explains that piling them on can clip the popover on
a small display — followed by the no-foot-gun safety net of (1).

`AppModel.showsSection(_:)` is the single read-side hook that the
DetailPanel uses; the layout-mode + opt-in logic lives in one
place.

## Why not...

**Force scroll mode always.** Considered. User feedback after the
v1.0.0 → v1.0.1 reset was explicit: "现在定频怎么少了那么多功能
啊?" — the receipt aesthetic gets lost when content always fills
a fixed 720pt frame with mid-receipt scrollbars. Fixed-natural is
the visually distinct mode users want.

**Compute natural height in Swift, then clamp.** Considered.
SwiftUI doesn't expose a synchronous "how tall would this be at
infinite width" measurement that respects the SwiftUI layout
engine's `.fixedSize` semantics. We'd have to build a parallel
measurement view tree and hope it stays in sync.

**Use `.frame(idealHeight:)`.** Doesn't compose well with
`ScrollView` — SwiftUI's ScrollView wants its content to claim
ideal height, not the wrapper.

**Add a third mode "auto" that switches based on content.**
Considered. Postponed — adding a mode just because we can't pick
one is admitting defeat. Two modes + the cap covers every screen
size from a notched 14" MBP up to a 6K Pro Display XDR.

## Consequences

- New sections in ReceiptBody can be added without gating, as
  long as they obey the existing layout primitives (no
  `.fixedSize` rebellion against ScrollView). The visibleFrame
  cap absorbs growth.
- The fixed mode 'looks like fixed' until the user opts into
  enough sections that the popover would have grown past the
  cap; from then on it's a same-frame ScrollView. That
  transition should be communicated in the Settings warning.
- StatusItemController no longer needs the manual KVO/clamp on
  `popover.contentSize`. NSHostingController's `.preferredContentSize`
  + the ScrollView cap is the entire pipeline. Removed in v1.0.3
  (commit 9793564).
- `--snapshot` mode (offscreen render) still bypasses the
  NSPopover constraints — this is *intentional* for promo image
  generation (we want full-receipt screenshots). The
  `feedback_local_test_before_release.md` rule covers the gap:
  every release that touches DetailPanel must be opened in the
  real menu-bar popover before tag.

## References

- v1.0.3 commit 9793564: ScrollView cap + section toggles + memory
- `Sources/ClaudegrainApp/DetailPanel.swift` — ReceiptScroll.content
- `Sources/ClaudegrainApp/Preferences.swift` — `FixedSection` enum,
  `fixedSections` accessor
- Memory: `feedback_popover_offset.md`,
  `feedback_popover_anchor_drift.md`,
  `feedback_local_test_before_release.md`
