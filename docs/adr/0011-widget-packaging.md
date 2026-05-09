# ADR-0011 — Widget packaging via Xcode project alongside SwiftPM

Status: accepted (2026-05-10)
Supersedes: none
Touches: ADR-0001, ADR-0002

## Context

Phase 4 of v0.2 adds a desktop widget. WidgetKit on macOS needs an
embedded `.appex` bundle with its own provisioning, Hardened Runtime
entitlements, and App Group container. SwiftPM cannot produce
`.appex` extensions in any Apple-supported way: every published path
(`swift package generate-xcodeproj`, custom build phases, `extension`
product types) is either removed in 5.7+, undocumented, or breaks
codesign / notarization in subtle ways.

We considered four options:

1. `swift package generate-xcodeproj` — removed in Swift 5.7. Dead.
2. Hand-written Xcode project alongside SwiftPM — duplicates target
   definitions; drift inevitable when sources are added.
3. SwiftPM custom build phases producing a `.appex` — not
   Apple-supported. `--deep` codesign + Hardened Runtime
   entitlements per binary fail.
4. **Xcode project committed at repo root, SwiftPM kept for
   library + tests + spike/preview executables.**

## Decision

Option 4. The repo holds **both** `Package.swift` and
`Claudegrain.xcodeproj`. They cooperate:

- `Package.swift` keeps `ClaudegrainCore` (library), the
  `ClaudegrainSpike` / `ClaudegrainPreview` executables, and the
  `ClaudegrainCoreTests` test target. `swift build` and `swift test`
  continue to work for everything but the widget extension.
- `Claudegrain.xcodeproj` (generated from `project.yml` via
  `xcodegen`, both committed) holds the `ClaudegrainApp` executable
  and the `ClaudegrainWidget` `.appex`. Both targets depend on the
  local SwiftPM package's `ClaudegrainCore` library product.
- The `ClaudegrainApp` source files at `Sources/ClaudegrainApp/` are
  consumed by *both* builds: SwiftPM treats them as an
  `executableTarget`, Xcode treats them as the application target.
  Resources (`Sources/ClaudegrainApp/Resources/Fonts/*.ttf`),
  `Info.plist`, and `Claudegrain.entitlements` live alongside the
  Swift source so both build paths see them.

Migration plan when adding files:

- Adding source `.swift`: drops in via filesystem; xcodegen rescans on
  next regenerate, SwiftPM picks it up automatically.
- Adding a new target: edit `project.yml`, regenerate. SwiftPM
  changes only if needed.
- Editing `Info.plist` / entitlements: hand-edit the file at
  `Sources/ClaudegrainApp/{Info.plist,Claudegrain.entitlements}`.
  xcodegen does **not** clobber these as long as `project.yml` does
  not declare `info:` / `entitlements:` blocks (settings build flags
  point at the existing file).

## Consequences

### Positive

- First-class Xcode support for the widget extension. App Group
  entitlements, codesign with `--deep`, and notarization all work
  the way Apple intends.
- SwiftPM stays the source of truth for everything else (library,
  tests, spike, preview). No GRDB inside the widget; the test target
  doesn't need to migrate to Xcode-only.
- `xcodegen` makes the project regeneratable from `project.yml`,
  which keeps the diff reviewable when targets / settings change.

### Negative

- Two build systems. Contributors must remember `swift test` for
  unit tests and `xcodebuild` for the menu-bar app.
- `.xcodeproj/project.pbxproj` is committed and can merge-conflict.
  Mitigated by `xcodegen` regenerating it deterministically — when
  conflicts happen, regenerate from `project.yml` and commit.
- A new contributor needs `brew install xcodegen` to maintain the
  project. Documented in CLAUDE.md.

### Build paths

- `swift build` — library + spike + preview + ClaudegrainApp exec
  (without the widget extension; SwiftPM can't embed `.appex`).
- `swift test` — unit tests, all 99 currently passing.
- `xcodebuild -scheme Claudegrain` — the production app + embedded
  widget extension. Used by `scripts/build-dmg.sh`.
- CI (`.github/workflows/release.yml`) runs `bash scripts/build-dmg.sh`
  which now drives `xcodebuild` under the hood.

## Alternatives considered

- **Tuist** instead of `xcodegen`. Heavier; project size doesn't
  justify it.
- **Move all sources into `App/`, `Widget/`, `Core/` directories
  matching Xcode project hierarchy.** Cleaner Xcode-side, but
  invasive `git mv` churn that would distort `git blame` for every
  file in `Sources/ClaudegrainApp/`. Rejected for v0.2.
- **Open `Package.swift` directly in Xcode and add the widget there.**
  Xcode 11+ does open `Package.swift` natively, but it cannot
  produce a real `.appex` from a SwiftPM-only project — same Apple
  limitation that disqualifies option 3.

## Notes

- App Group identifier: `group.dev.claudegrain.shared`. Both targets
  carry it in entitlements. `WidgetSnapshotIO.appGroupContainer()`
  resolves it; falls back to Application Support for SwiftPM-only
  dev runs.
- Bundle identifiers: host `dev.claudegrain.menubar`, widget
  `dev.claudegrain.menubar.widget`. Same prefix is required for the
  shared App Group entitlement.
- Both `Info.plist` and entitlements files are committed once and
  hand-edited going forward. xcodegen never overwrites them.
