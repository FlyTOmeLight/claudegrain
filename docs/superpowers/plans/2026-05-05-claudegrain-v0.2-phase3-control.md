# claudegrain v0.2 Phase 3 — Control (Budgets + Quiet Hours + Pause + Commitment)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Spec:** `docs/superpowers/specs/2026-05-05-claudegrain-v0.2-design.md` §4.5 (C1), §4.6 (C2), §4.7 (C3), §4.8 (C4)

**Goal:** Land Phase 3 of v0.2 — give the user proactive control over notifications and ingestion. Released as `0.1.6-rc5`.

**Architecture:** Four independent control surfaces wired into existing `NotificationManager` / `AppCoordinator`. (1) `BudgetStore` replaces the single global `repoOverspendThresholdUSD` with a per-repo daily/weekly map (UserDefaults JSON, ADR-0008). (2) `QuietHours` time-window struct gates `NotificationManager.shouldDeliver` (ADR-0009). (3) `IngestPauseController` halts `FileWatcher` + signals `DataSourceCoordinator` user-toggle-off; resume runs catch-up via existing cursor logic. (4) `CommitmentLog` records actionable-button responses to repo-overspend notifications (ADR-0010, separate JSON file `commitments.json`). New Settings tabs: `Budgets`, `Quiet Hours`. Popover gains pause banner + key `p`.

**Tech Stack:** Swift 5.9, SwiftPM, UserNotifications (UN actionable categories), AppKit, SwiftUI, Foundation `Calendar` for HH:MM windows, GRDB-only external dep (no new deps).

**Branch:** `feat/v0.2/control` (cut from `main` after Phase 2 merge).

**Predecessor commits to verify:** `4428aff fix(app): kick immediate OAuth+ingest refresh on boot` on `main`.

---

## Pre-flight

### Task 0: Branch + baseline

**Files:** none modified

- [ ] **Step 1: Confirm state**

```bash
git rev-parse --abbrev-ref HEAD                     # expect feat/v0.2/control
git log --oneline -1                                # expect 4428aff (or later main HEAD)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

Expected: `Executed 73 tests, with 0 failures`. If not on `feat/v0.2/control`, STOP.

---

## Section A: C1 — per-repo soft budgets

### Task 1: `RepoBudget` struct + `BudgetStore`

**Files:**
- Create: `Sources/ClaudegrainCore/Budget/BudgetStore.swift`
- Create: `Tests/ClaudegrainCoreTests/BudgetStoreTests.swift`

> **Note**: `BudgetStore` lives in `ClaudegrainCore` (not `ClaudegrainApp`) because notification logic in core needs to consult it without depending on UI. Storage backend is `UserDefaults`; the store accepts an injectable `UserDefaults` for testability.

- [ ] **Step 1: Failing test**

Create `Tests/ClaudegrainCoreTests/BudgetStoreTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore

final class BudgetStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "budget-test-\(UUID().uuidString)")!
    }

    func testDefaultsAreEmpty() {
        let store = BudgetStore(defaults: makeDefaults())
        XCTAssertTrue(store.allBudgets.isEmpty)
        XCTAssertEqual(store.globalDefaultDailyUSD, 10.0, accuracy: 0.001)
    }

    func testSetAndResolveBudget() {
        let store = BudgetStore(defaults: makeDefaults())
        store.setBudget(repo: "/a", daily: 5.0, weekly: 30.0)

        let resolved = store.resolve(repo: "/a")
        XCTAssertEqual(resolved.dailyUSD, 5.0)
        XCTAssertEqual(resolved.weeklyUSD, 30.0)
        XCTAssertEqual(resolved.repo, "/a")
    }

    func testResolveFallsBackToGlobalDefault() {
        let store = BudgetStore(defaults: makeDefaults())
        store.globalDefaultDailyUSD = 7.5

        let resolved = store.resolve(repo: "/never-set")
        XCTAssertEqual(resolved.dailyUSD, 7.5)
        XCTAssertNil(resolved.weeklyUSD)
        XCTAssertEqual(resolved.repo, "/never-set")
    }

    func testPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let s1 = BudgetStore(defaults: defaults)
        s1.setBudget(repo: "/x", daily: 12.0, weekly: nil)
        s1.globalDefaultDailyUSD = 4.0

        let s2 = BudgetStore(defaults: defaults)
        XCTAssertEqual(s2.resolve(repo: "/x").dailyUSD, 12.0)
        XCTAssertEqual(s2.globalDefaultDailyUSD, 4.0)
    }

    func testRemoveBudget() {
        let store = BudgetStore(defaults: makeDefaults())
        store.setBudget(repo: "/a", daily: 5.0, weekly: nil)
        store.removeBudget(repo: "/a")
        XCTAssertNil(store.allBudgets["/a"])
        XCTAssertEqual(store.resolve(repo: "/a").dailyUSD, store.globalDefaultDailyUSD)
    }
}
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter BudgetStoreTests 2>&1 | tail -10
```

Expected: cannot find `BudgetStore`, `RepoBudget`.

- [ ] **Step 3: Implement**

Create `Sources/ClaudegrainCore/Budget/BudgetStore.swift`:

```swift
import Foundation

public struct RepoBudget: Codable, Equatable, Sendable {
    public let repo: String
    public let dailyUSD: Double?
    public let weeklyUSD: Double?

    public init(repo: String, dailyUSD: Double?, weeklyUSD: Double?) {
        self.repo = repo
        self.dailyUSD = dailyUSD
        self.weeklyUSD = weeklyUSD
    }
}

/// Per-repo soft budgets (ADR-0008). Replaces the single
/// `repoOverspendThresholdUSD` value used in 0.1.x; migration in
/// `migrateLegacyKeyIfNeeded(...)` (Task 2).
@MainActor
public final class BudgetStore: ObservableObject {
    public static let budgetsKey = "budgets.v2"
    public static let globalDailyKey = "globalDefaultDailyUSD"

    @Published public private(set) var allBudgets: [String: RepoBudget] = [:]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.allBudgets = Self.load(from: defaults)
    }

    public var globalDefaultDailyUSD: Double {
        get {
            // Returns 10.0 if the key isn't present (first-run default).
            if defaults.object(forKey: Self.globalDailyKey) == nil { return 10.0 }
            return defaults.double(forKey: Self.globalDailyKey)
        }
        set {
            defaults.set(newValue, forKey: Self.globalDailyKey)
            objectWillChange.send()
        }
    }

    public func setBudget(repo: String, daily: Double?, weekly: Double?) {
        let budget = RepoBudget(repo: repo, dailyUSD: daily, weeklyUSD: weekly)
        allBudgets[repo] = budget
        save()
    }

    public func removeBudget(repo: String) {
        allBudgets.removeValue(forKey: repo)
        save()
    }

    /// Returns per-repo override if set, else the global default daily threshold.
    public func resolve(repo: String) -> RepoBudget {
        if let b = allBudgets[repo] { return b }
        return RepoBudget(repo: repo, dailyUSD: globalDefaultDailyUSD, weeklyUSD: nil)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(allBudgets) else { return }
        defaults.set(data, forKey: Self.budgetsKey)
    }

    private static func load(from defaults: UserDefaults) -> [String: RepoBudget] {
        guard let data = defaults.data(forKey: Self.budgetsKey),
              let map = try? JSONDecoder().decode([String: RepoBudget].self, from: data)
        else { return [:] }
        return map
    }
}
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter BudgetStoreTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Budget/BudgetStore.swift Tests/ClaudegrainCoreTests/BudgetStoreTests.swift
git commit -m "feat(core): RepoBudget + BudgetStore with UserDefaults backing"
```

---

### Task 2: Migrate legacy `repoOverspendThresholdUSD` → `globalDefaultDailyUSD`

**Files:**
- Modify: `Sources/ClaudegrainCore/Budget/BudgetStore.swift`
- Modify: `Tests/ClaudegrainCoreTests/BudgetStoreTests.swift`

- [ ] **Step 1: Failing test** — append:

```swift
    func testMigratesLegacyRepoOverspendThreshold() {
        let defaults = makeDefaults()
        defaults.set(15.0, forKey: "repoOverspendThresholdUSD")

        let store = BudgetStore(defaults: defaults)
        store.migrateLegacyKeyIfNeeded()

        XCTAssertEqual(store.globalDefaultDailyUSD, 15.0, accuracy: 0.001)
        XCTAssertNil(defaults.object(forKey: "repoOverspendThresholdUSD"),
                     "legacy key should be removed after migration")
    }

    func testMigrationIsIdempotent() {
        let defaults = makeDefaults()
        defaults.set(15.0, forKey: "repoOverspendThresholdUSD")

        let s1 = BudgetStore(defaults: defaults)
        s1.migrateLegacyKeyIfNeeded()
        // Second call must not overwrite a user-set new-key value.
        s1.globalDefaultDailyUSD = 8.0
        s1.migrateLegacyKeyIfNeeded()
        XCTAssertEqual(s1.globalDefaultDailyUSD, 8.0)
    }

    func testMigrationDoesNothingWithoutLegacyKey() {
        let store = BudgetStore(defaults: makeDefaults())
        store.migrateLegacyKeyIfNeeded()
        XCTAssertEqual(store.globalDefaultDailyUSD, 10.0)
    }
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter BudgetStoreTests/testMigrates 2>&1 | tail -5
```

- [ ] **Step 3: Implement**

In `BudgetStore.swift`, add:

```swift
    /// One-shot migration from 0.1.x's single `repoOverspendThresholdUSD`
    /// double value to `globalDefaultDailyUSD`. Removes the legacy key after
    /// reading. Idempotent.
    public func migrateLegacyKeyIfNeeded() {
        let legacyKey = "repoOverspendThresholdUSD"
        guard defaults.object(forKey: legacyKey) != nil else { return }
        let legacyValue = defaults.double(forKey: legacyKey)
        // Only adopt the legacy value if the user hasn't already set the new key.
        if defaults.object(forKey: Self.globalDailyKey) == nil {
            defaults.set(legacyValue, forKey: Self.globalDailyKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter BudgetStoreTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(core): BudgetStore.migrateLegacyKeyIfNeeded"
```

---

### Task 3: Wire `BudgetStore` into `NotificationManager.checkRepoOverspend`

**Files:**
- Modify: `Sources/ClaudegrainApp/NotificationManager.swift`
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift` (inject BudgetStore)
- Modify: `Tests/ClaudegrainCoreTests/NotificationManagerTests.swift`

- [ ] **Step 1: Failing test** — append:

```swift
    func testRepoOverspendUsesPerRepoBudget() {
        var fired: [(NotificationKind, String)] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "ros-\(UUID().uuidString)")!)
        prefs.notifyRepoOverspend = true

        let budgets = BudgetStore(defaults: UserDefaults(suiteName: "ros-budgets-\(UUID().uuidString)")!)
        budgets.globalDefaultDailyUSD = 100.0   // very high default
        budgets.setBudget(repo: "/tight", daily: 1.0, weekly: nil)

        let mgr = NotificationManager(prefs: prefs, budgets: budgets) { kind, _, body in
            fired.append((kind, body))
        }

        let topRepos: [RepoBreakdown] = [
            RepoBreakdown(repo: "/tight", fullCwd: "/tight", costUSD: 5.0, totalTokens: 1),
            RepoBreakdown(repo: "/loose", fullCwd: "/loose", costUSD: 50.0, totalTokens: 1),
        ]

        mgr.evaluateUsage(session: nil, weekly: nil, topRepos: topRepos)

        XCTAssertEqual(fired.count, 1, "/tight should fire (5.0 > 1.0); /loose stays under 100.0")
        XCTAssertEqual(fired.first?.0, .repoOverspend)
        XCTAssertTrue(fired.first?.1.contains("/tight") ?? false)
    }
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter NotificationManagerTests/testRepoOverspendUsesPerRepoBudget 2>&1 | tail -10
```

Expected: NotificationManager init signature mismatch (no `budgets:` parameter).

- [ ] **Step 3: Implement**

In `Sources/ClaudegrainApp/NotificationManager.swift`:

1. Add property + init parameter:

```swift
    private let budgets: BudgetStore

    init(
        prefs: Preferences? = nil,
        budgets: BudgetStore? = nil,
        handler: Handler? = nil
    ) {
        self.prefs = prefs ?? .shared
        self.budgets = budgets ?? BudgetStore()
        if let handler {
            self.handler = handler
            self.usesSystemCenter = false
        } else {
            self.handler = Self.defaultHandler
            self.usesSystemCenter = true
        }
    }
```

2. Replace `checkRepoOverspend(_:)`:

```swift
    private func checkRepoOverspend(_ topRepos: [RepoBreakdown]) {
        for repo in topRepos.prefix(5) {
            let budget = budgets.resolve(repo: repo.id)
            guard let dailyLimit = budget.dailyUSD, repo.costUSD >= dailyLimit else { continue }
            let key = RepoOverspendKey(date: Calendar.current.startOfDay(for: Date()), repo: repo.id)
            guard !repoOverspendFired.contains(key) else { continue }
            fire(.repoOverspend,
                 title: "Repo over budget · \(repo.repo)",
                 body: "Today $\(String(format: "%.2f", repo.costUSD)) ≥ budget $\(String(format: "%.2f", dailyLimit))")
            repoOverspendFired.insert(key)
        }
    }
```

3. In `Sources/ClaudegrainApp/AppCoordinator.swift`, add `budgets: BudgetStore` property + inject into NotificationManager:

```swift
    let budgets: BudgetStore

    init(
        model: AppModel,
        notifications: NotificationManager? = nil,
        dbOverride: EventsDatabase? = nil
    ) throws {
        self.model = model
        if let dbOverride { self.db = dbOverride }
        else { self.db = try EventsDatabase(url: EventsDatabase.defaultURL) }
        self.ingest = IngestActor(db: db)
        self.dataSource = DataSourceCoordinator()

        let store = BudgetStore()
        store.migrateLegacyKeyIfNeeded()
        self.budgets = store

        self.notifications = notifications ?? NotificationManager(prefs: model.preferences, budgets: store)
        self.exporter = EventsExporter(db: self.db)
    }
```

(Keep `dbOverride` plumbing.)

- [ ] **Step 4: Green phase**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -5
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

Expected: all green. NotificationManager existing tests still pass + 1 new test.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(app): NotificationManager uses BudgetStore.resolve per repo"
```

---

### Task 4: `Budgets` settings tab UI

**Files:**
- Create: `Sources/ClaudegrainApp/Settings/BudgetsTab.swift`
- Modify: existing settings hosting view (read first to find the right insertion point)

> **Note**: The existing settings UI lives in `Sources/ClaudegrainApp/ClaudegrainApp.swift` or a similar file (`SettingsView`). Read it first to see how `General`/`Notifications`/`About` tabs are wired (TabView with `.tabItem`). Add `Budgets` between `Notifications` and `About`.

- [ ] **Step 1: Read existing settings tab structure**

Find the file containing `SettingsView` / `TabView` with `General` / `Notifications` / `About` tabs. Common name: `SettingsView.swift` or inline in `ClaudegrainApp.swift`. Read it to see the `.tabItem` style and how each tab's content view is structured.

- [ ] **Step 2: Create `BudgetsTab.swift`**

```swift
import SwiftUI
import ClaudegrainCore

struct BudgetsTab: View {
    @ObservedObject var budgets: BudgetStore
    let recentRepos: [String]    // wired from AppModel.topRepos.map { $0.id }
    @EnvironmentObject private var model: AppModel
    @State private var newRepo: String = ""
    @State private var newDaily: String = ""
    @State private var newWeekly: String = ""

    var body: some View {
        Form {
            Section(header: Text(model.t(.budgetsGlobalSection))) {
                HStack {
                    Text(model.t(.budgetsGlobalDaily))
                    Spacer()
                    TextField("$", value: Binding(
                        get: { budgets.globalDefaultDailyUSD },
                        set: { budgets.globalDefaultDailyUSD = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section(header: Text(model.t(.budgetsRepoSection))) {
                if budgets.allBudgets.isEmpty && recentRepos.isEmpty {
                    Text(model.t(.budgetsEmpty))
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedRepoKeys, id: \.self) { repo in
                    BudgetRowView(budgets: budgets, repo: repo)
                }
            }

            Section(header: Text(model.t(.budgetsAddSection))) {
                HStack {
                    TextField(model.t(.budgetsAddRepoPlaceholder), text: $newRepo)
                    TextField("daily $", text: $newDaily).frame(width: 80)
                    TextField("weekly $", text: $newWeekly).frame(width: 80)
                    Button(model.t(.budgetsAddButton)) {
                        guard !newRepo.isEmpty else { return }
                        budgets.setBudget(
                            repo: newRepo,
                            daily: Double(newDaily),
                            weekly: Double(newWeekly)
                        )
                        newRepo = ""; newDaily = ""; newWeekly = ""
                    }
                }
            }
        }
        .padding()
    }

    private var sortedRepoKeys: [String] {
        let configured = Set(budgets.allBudgets.keys)
        let union = configured.union(recentRepos)
        return union.sorted()
    }
}

private struct BudgetRowView: View {
    @ObservedObject var budgets: BudgetStore
    let repo: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let resolved = budgets.resolve(repo: repo)
        HStack {
            Text(repo).frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1).truncationMode(.middle)
            TextField("daily", value: dailyBinding(initial: resolved.dailyUSD),
                      format: .number.precision(.fractionLength(2)))
                .frame(width: 80).multilineTextAlignment(.trailing)
            TextField("weekly", value: weeklyBinding(initial: resolved.weeklyUSD),
                      format: .number.precision(.fractionLength(2)))
                .frame(width: 80).multilineTextAlignment(.trailing)
            Button(role: .destructive) {
                budgets.removeBudget(repo: repo)
            } label: { Image(systemName: "xmark.circle") }
        }
    }

    private func dailyBinding(initial: Double?) -> Binding<Double> {
        Binding(
            get: { budgets.allBudgets[repo]?.dailyUSD ?? initial ?? 0 },
            set: { budgets.setBudget(repo: repo, daily: $0, weekly: budgets.allBudgets[repo]?.weeklyUSD) }
        )
    }
    private func weeklyBinding(initial: Double?) -> Binding<Double> {
        Binding(
            get: { budgets.allBudgets[repo]?.weeklyUSD ?? initial ?? 0 },
            set: { budgets.setBudget(repo: repo, daily: budgets.allBudgets[repo]?.dailyUSD, weekly: $0) }
        )
    }
}
```

- [ ] **Step 3: Add `Budgets` tab to existing SettingsView**

In whatever file contains the `TabView` with the existing tabs, add:

```swift
            BudgetsTab(budgets: appModel.budgets, recentRepos: appModel.topRepos.map { $0.id })
                .tabItem { Label(model.t(.settingsBudgets), systemImage: "dollarsign.circle") }
```

(Adapt to actual API — `appModel.budgets` requires `AppModel` exposing the `BudgetStore`. If `AppModel` doesn't currently hold it, add a `let budgets: BudgetStore` parameter to `AppModel.init` and pass through from `AppCoordinator`. Read the existing init pattern.)

- [ ] **Step 4: Verify build**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainApp/
git commit -m "feat(app): Budgets settings tab + AppModel.budgets exposure"
```

---

## Section B: C2 — Quiet Hours

### Task 5: `QuietHours` struct + cross-midnight `contains(_:)`

**Files:**
- Create: `Sources/ClaudegrainCore/QuietHours/QuietHours.swift`
- Create: `Tests/ClaudegrainCoreTests/QuietHoursTests.swift`

- [ ] **Step 1: Failing test**

Create `Tests/ClaudegrainCoreTests/QuietHoursTests.swift`:

```swift
import XCTest
@testable import ClaudegrainCore

final class QuietHoursTests: XCTestCase {
    private func date(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 5
        comps.hour = hour; comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    func testNotEnabledNeverContains() {
        let q = QuietHours(enabled: false, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertFalse(q.contains(date(hour: 23, minute: 30)))
    }

    func testWithinSameDayWindow() {
        // 09:00 → 17:00 (workday window for testing — semantics same as quiet hours)
        let q = QuietHours(enabled: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 12, minute: 0)))
        XCTAssertFalse(q.contains(date(hour: 8, minute: 59)))
        XCTAssertFalse(q.contains(date(hour: 17, minute: 0)), "end is exclusive")
    }

    func testCrossMidnightWindow() {
        let q = QuietHours(enabled: true, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 23, minute: 30)))
        XCTAssertTrue(q.contains(date(hour: 0, minute: 30)))
        XCTAssertTrue(q.contains(date(hour: 8, minute: 30)))
        XCTAssertFalse(q.contains(date(hour: 9, minute: 0)), "end is exclusive")
        XCTAssertFalse(q.contains(date(hour: 12, minute: 0)))
    }

    func testStartEqualsEndIsEmpty() {
        let q = QuietHours(enabled: true, startHour: 9, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertFalse(q.contains(date(hour: 9, minute: 0)))
        XCTAssertFalse(q.contains(date(hour: 14, minute: 0)))
    }

    func testEdgeAtStartIsInclusive() {
        let q = QuietHours(enabled: true, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 22, minute: 0)))
    }
}
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter QuietHoursTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement**

Create `Sources/ClaudegrainCore/QuietHours/QuietHours.swift`:

```swift
import Foundation

public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startHour: Int    // 0–23 device-local
    public var startMinute: Int  // 0–59
    public var endHour: Int      // 0–23 device-local
    public var endMinute: Int    // 0–59

    public init(enabled: Bool, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.enabled = enabled
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    public static let `default` = QuietHours(
        enabled: false, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0
    )

    /// Returns true iff `date`'s local time is in `[start, end)`. Window may
    /// span midnight (start > end → wraps next day). `enabled == false` always
    /// returns false.
    public func contains(_ date: Date) -> Bool {
        guard enabled else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMin = startHour * 60 + startMinute
        let endMin = endHour * 60 + endMinute
        if startMin == endMin { return false }   // empty window
        if startMin < endMin {
            // Same-day window.
            return nowMin >= startMin && nowMin < endMin
        } else {
            // Cross-midnight window.
            return nowMin >= startMin || nowMin < endMin
        }
    }
}
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter QuietHoursTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/QuietHours/QuietHours.swift Tests/ClaudegrainCoreTests/QuietHoursTests.swift
git commit -m "feat(core): QuietHours struct with cross-midnight contains"
```

---

### Task 6: Wire `QuietHours` into `NotificationManager.shouldDeliver`

**Files:**
- Modify: `Sources/ClaudegrainApp/NotificationManager.swift`
- Modify: `Sources/ClaudegrainApp/Preferences.swift`
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift`
- Modify: `Tests/ClaudegrainCoreTests/NotificationManagerTests.swift`

- [ ] **Step 1: Failing test** — append:

```swift
    func testQuietHoursSuppressesAllNotifications() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "qh-\(UUID().uuidString)")!)
        prefs.notifyThreshold = true
        prefs.quietHours = QuietHours(enabled: true,
                                       startHour: 0, startMinute: 0,
                                       endHour: 23, endMinute: 59)   // all-day suppress for test

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }
        let snap = SessionBlockSnapshot(
            startedAt: Date().addingTimeInterval(-1800),
            resetsAt:  Date().addingTimeInterval(16_200),
            usedFraction: 0.95,
            totalTokens: 1
        )
        mgr.evaluate(session: snap, weekly: nil)

        XCTAssertTrue(fired.isEmpty, "quiet hours should suppress threshold notification")
    }
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter NotificationManagerTests/testQuietHours 2>&1 | tail -5
```

Expected: `prefs.quietHours` doesn't exist.

- [ ] **Step 3: Implement**

In `Sources/ClaudegrainApp/Preferences.swift`, add a `quietHours` property:

```swift
    enum Key {
        // ...existing...
        static let quietHours = "quietHours.v1"
    }

    var quietHours: QuietHours {
        get {
            guard let data = defaults.data(forKey: Key.quietHours),
                  let q = try? JSONDecoder().decode(QuietHours.self, from: data)
            else { return .default }
            return q
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.quietHours)
            }
            objectWillChange.send()
        }
    }
```

(`QuietHours` already imported transitively via `ClaudegrainCore` import in `Preferences.swift`. If not, add `import ClaudegrainCore`.)

In `NotificationManager.swift`, gate `fire(...)` on quiet hours:

```swift
    private func fire(_ kind: NotificationKind, title: String, body: String) {
        guard shouldDeliver(now: Date()) else { return }
        handler(kind, title, body)
    }

    private func shouldDeliver(now: Date) -> Bool {
        !prefs.quietHours.contains(now)
    }
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(app): NotificationManager respects QuietHours suppression"
```

---

### Task 7: `Quiet Hours` settings tab UI

**Files:**
- Create: `Sources/ClaudegrainApp/Settings/QuietHoursTab.swift`
- Modify: SettingsView host

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import ClaudegrainCore

struct QuietHoursTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var current: QuietHours = .default

    var body: some View {
        Form {
            Toggle(model.t(.quietHoursEnable), isOn: bindEnabled)
            HStack {
                Text(model.t(.quietHoursFrom))
                DatePicker("", selection: bindStart, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
                Text(model.t(.quietHoursTo))
                DatePicker("", selection: bindEnd, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .disabled(!current.enabled)
            Text(model.t(.quietHoursDeviceLocal))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(model.t(.quietHoursDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { current = model.preferences.quietHours }
    }

    private var bindEnabled: Binding<Bool> {
        Binding(
            get: { current.enabled },
            set: { current.enabled = $0; model.preferences.quietHours = current }
        )
    }

    private var bindStart: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: current.startHour, minute: current.startMinute, second: 0, of: Date()) ?? Date() },
            set: { d in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                current.startHour = comps.hour ?? 0
                current.startMinute = comps.minute ?? 0
                model.preferences.quietHours = current
            }
        )
    }

    private var bindEnd: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: current.endHour, minute: current.endMinute, second: 0, of: Date()) ?? Date() },
            set: { d in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                current.endHour = comps.hour ?? 0
                current.endMinute = comps.minute ?? 0
                model.preferences.quietHours = current
            }
        )
    }
}
```

- [ ] **Step 2: Add tab to SettingsView**

```swift
            QuietHoursTab()
                .tabItem { Label(model.t(.settingsQuietHours), systemImage: "moon.zzz") }
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudegrainApp/
git commit -m "feat(app): Quiet Hours settings tab"
```

---

## Section C: C3 — Pause Ingest

### Task 8: `IngestPauseController`

**Files:**
- Create: `Sources/ClaudegrainApp/IngestPauseController.swift`
- Create: `Tests/ClaudegrainCoreTests/IngestPauseControllerTests.swift`

> **Note**: `IngestPauseController` lives in `ClaudegrainApp` (not core) because it coordinates `IngestActor` + `DataSourceCoordinator` — both `MainActor`-adjacent at the app level. The struct itself is `@MainActor`.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import ClaudegrainCore
@testable import ClaudegrainApp

@MainActor
final class IngestPauseControllerTests: XCTestCase {
    func testInitDefaultsToNotPaused() {
        let controller = IngestPauseController(defaults: UserDefaults(suiteName: "pause-\(UUID().uuidString)")!)
        XCTAssertFalse(controller.isPaused)
    }

    func testToggleAndPersist() {
        let defaults = UserDefaults(suiteName: "pause-\(UUID().uuidString)")!
        let c1 = IngestPauseController(defaults: defaults)
        c1.pause()
        XCTAssertTrue(c1.isPaused)

        let c2 = IngestPauseController(defaults: defaults)
        XCTAssertTrue(c2.isPaused)

        c2.resume()
        XCTAssertFalse(c2.isPaused)
    }
}
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter IngestPauseControllerTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement**

```swift
import Foundation
import Combine

@MainActor
public final class IngestPauseController: ObservableObject {
    public static let key = "ingestPaused.v1"

    @Published public private(set) var isPaused: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Self.key)
    }

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        defaults.set(true, forKey: Self.key)
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        defaults.set(false, forKey: Self.key)
    }

    public func toggle() {
        if isPaused { resume() } else { pause() }
    }
}
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter IngestPauseControllerTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainApp/IngestPauseController.swift Tests/ClaudegrainCoreTests/IngestPauseControllerTests.swift
git commit -m "feat(app): IngestPauseController with persisted state"
```

---

### Task 9: Hook pause into `IngestActor` + `DataSourceCoordinator`

**Files:**
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift`

- [ ] **Step 1: Implement**

In `AppCoordinator.swift`:

```swift
    let pauseController: IngestPauseController

    // In init, alongside other lets:
    self.pauseController = IngestPauseController()

    // After existing start() body, add a Combine subscription to the published value:
    private var pauseSubscription: AnyCancellable?

    // In start(), after the existing stream tasks:
    pauseSubscription = pauseController.$isPaused
        .removeDuplicates()
        .sink { [weak self] paused in
            Task { [weak self] in
                if paused {
                    await self?.ingest.stop()
                    await self?.dataSource.stop()
                } else {
                    await self?.ingest.refreshNow()
                    await self?.dataSource.refreshNow()
                    await self?.ingest.startWatching()
                }
            }
        }
```

> **If `IngestActor.startWatching()` already runs from `start()`, calling it again on resume should be safe (idempotent re-subscribe to FSEvents). If not, the simplest fix is to expose a `restartIfNeeded()` method that only starts watching when not already watching. Read `IngestActor.swift` first.**

(Add `import Combine` if missing.)

- [ ] **Step 2: Verify build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(app): wire IngestPauseController into ingest + dataSource"
```

---

### Task 10: Pause UI banner + menu item + key 'p'

**Files:**
- Modify: `Sources/ClaudegrainApp/DetailPanel.swift` (banner + footer kbd)
- Modify: `Sources/ClaudegrainApp/AppModel.swift` (pauseHandler closure mirroring refreshHandler)
- Modify: `Sources/ClaudegrainApp/StatusItemController.swift` (right-click menu item)
- Modify: `Sources/ClaudegrainApp/ClaudegrainApp.swift` (wire handler)

- [ ] **Step 1: Add pauseHandler to AppModel**

```swift
    var pauseHandler: (@MainActor () async -> Void)?
```

(Mirror existing `refreshHandler` / `exportHandler` patterns.)

- [ ] **Step 2: Add `kbd("P", model.t(.kbPause))` button to DetailPanel footer**

Insert next to existing `E`/`F5`/`F10` buttons in the footer. Calls `model.pauseHandler?()`.

- [ ] **Step 3: Add `Pause Ingest` / `Resume Ingest` menu item to right-click NSMenu**

In `StatusItemController.swift`, add to the right-click menu (between Export Usage… and Quit):

```swift
        let pauseTitle = isPaused ? model.t(.menuResumeIngest) : model.t(.menuPauseIngest)
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(handlePauseMenu), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
```

(Read `isPaused` from `AppDelegate.shared?.coordinator?.pauseController.isPaused`. The menu is rebuilt per click via `popUp(...)`, so it'll reflect current state each time.)

- [ ] **Step 4: Add banner to ReceiptBody**

In `DetailPanel.swift`, near the top of `ReceiptBody.body` (after HeaderStrip, before DoubleDivider), add a conditional pause banner:

```swift
            if let coord = AppDelegate.shared?.coordinator, coord.pauseController.isPaused {
                PauseBanner()
            }
```

Define `PauseBanner` as a small View in the same file (or as a sibling file `PauseBanner.swift` if you prefer). It should display: `⏸ Paused — last updated [time] [Resume]`.

- [ ] **Step 5: Wire pauseHandler in ClaudegrainApp.swift**

Mirror the refreshHandler pattern:

```swift
            model.pauseHandler = { [weak coordinator] in
                coordinator?.pauseController.toggle()
            }
```

- [ ] **Step 6: Verify build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudegrainApp/
git commit -m "feat(app): pause UI — banner + menu + 'p' shortcut"
```

---

## Section D: C4 — Commitment Log

### Task 11: `Commitment` struct + `CommitmentLog`

**Files:**
- Create: `Sources/ClaudegrainCore/Commitment/CommitmentLog.swift`
- Create: `Tests/ClaudegrainCoreTests/CommitmentLogTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import ClaudegrainCore

@MainActor
final class CommitmentLogTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("commitments-\(UUID().uuidString).json")
    }

    func testRecordAndPersist() throws {
        let url = tempURL()
        let log1 = CommitmentLog(url: url)
        log1.record(Commitment(
            id: UUID(), repo: "/a", triggeredAt: Date(),
            dailyOverspendUSD: 12.0, status: .open
        ))
        XCTAssertEqual(log1.entries.count, 1)

        let log2 = CommitmentLog(url: url)
        XCTAssertEqual(log2.entries.count, 1)
        XCTAssertEqual(log2.entries.first?.repo, "/a")
    }

    func testUpdateStatus() {
        let url = tempURL()
        let log = CommitmentLog(url: url)
        let id = UUID()
        log.record(Commitment(id: id, repo: "/a", triggeredAt: Date(),
                              dailyOverspendUSD: 5.0, status: .open))
        log.update(id: id, status: .markedPaused)
        XCTAssertEqual(log.entries.first?.status, .markedPaused)
    }

    func testCorruptedFileRecoversAsEmpty() throws {
        let url = tempURL()
        try "bogus json {{{".write(to: url, atomically: true, encoding: .utf8)
        let log = CommitmentLog(url: url)
        XCTAssertTrue(log.entries.isEmpty)
    }
}
```

- [ ] **Step 2: Red phase**

```bash
swift test --filter CommitmentLogTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement**

Create `Sources/ClaudegrainCore/Commitment/CommitmentLog.swift`:

```swift
import Foundation

public struct Commitment: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case open, markedPaused, ignored
    }

    public let id: UUID
    public let repo: String
    public let triggeredAt: Date
    public let dailyOverspendUSD: Double
    public var status: Status

    public init(id: UUID, repo: String, triggeredAt: Date, dailyOverspendUSD: Double, status: Status) {
        self.id = id
        self.repo = repo
        self.triggeredAt = triggeredAt
        self.dailyOverspendUSD = dailyOverspendUSD
        self.status = status
    }
}

@MainActor
public final class CommitmentLog: ObservableObject {
    public static let defaultURL: URL = {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support
            .appendingPathComponent("claudegrain", isDirectory: true)
            .appendingPathComponent("commitments.json")
    }()

    @Published public private(set) var entries: [Commitment] = []

    private let url: URL

    public init(url: URL = CommitmentLog.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.entries = Self.load(from: url)
    }

    public func record(_ commitment: Commitment) {
        entries.append(commitment)
        save()
    }

    public func update(id: UUID, status: Commitment.Status) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = status
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> [Commitment] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Commitment].self, from: data)) ?? []
    }
}
```

- [ ] **Step 4: Green phase**

```bash
swift test --filter CommitmentLogTests 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudegrainCore/Commitment/CommitmentLog.swift Tests/ClaudegrainCoreTests/CommitmentLogTests.swift
git commit -m "feat(core): Commitment + CommitmentLog with JSON persistence"
```

---

### Task 12: UN actionable buttons MARK_PAUSED / IGNORE on repo-overspend

**Files:**
- Modify: `Sources/ClaudegrainApp/NotificationManager.swift`
- Modify: `Sources/ClaudegrainApp/AppCoordinator.swift` (inject CommitmentLog + handle action)
- Modify: `Sources/ClaudegrainApp/AppModel.swift` (publish CommitmentLog)

- [ ] **Step 1: Register actionable category at launch**

In `NotificationManager.ensureAuthorization()` (or alongside it), register a category with two actions:

```swift
    static let repoOverspendCategoryID = "REPO_OVERSPEND"
    static let actionMarkPaused = "MARK_PAUSED"
    static let actionIgnore     = "IGNORE"

    private func ensureAuthorization() {
        guard usesSystemCenter, !authRequested else { return }
        authRequested = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let mark = UNNotificationAction(
            identifier: Self.actionMarkPaused,
            title: "Mark as paused",
            options: [.foreground]
        )
        let ignore = UNNotificationAction(
            identifier: Self.actionIgnore,
            title: "Ignore",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.repoOverspendCategoryID,
            actions: [mark, ignore],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
```

- [ ] **Step 2: Attach categoryIdentifier on repo-overspend fire**

Modify `defaultHandler` (or split out a `fire(...)` overload) so repo-overspend notifications carry `content.categoryIdentifier = REPO_OVERSPEND` AND `content.userInfo = ["repo": repo.id, "cost": repo.costUSD]`. The simplest path:

```swift
    private func fire(_ kind: NotificationKind, title: String, body: String, userInfo: [String: Any] = [:]) {
        guard shouldDeliver(now: Date()) else { return }
        handler(kind, title, body)
        if usesSystemCenter, kind == .repoOverspend {
            // Re-fire as actionable system notification (overrides the simple handler call above)
            // — actually adapt the default handler instead of double-firing. See Step 3.
        }
    }
```

The right approach is to adapt `defaultHandler` to take userInfo + category and `checkRepoOverspend` to pass them:

```swift
    private func checkRepoOverspend(_ topRepos: [RepoBreakdown]) {
        for repo in topRepos.prefix(5) {
            let budget = budgets.resolve(repo: repo.id)
            guard let dailyLimit = budget.dailyUSD, repo.costUSD >= dailyLimit else { continue }
            let key = RepoOverspendKey(date: Calendar.current.startOfDay(for: Date()), repo: repo.id)
            guard !repoOverspendFired.contains(key) else { continue }
            fireRepoOverspend(repo: repo, dailyLimit: dailyLimit)
            repoOverspendFired.insert(key)
        }
    }

    private func fireRepoOverspend(repo: RepoBreakdown, dailyLimit: Double) {
        guard shouldDeliver(now: Date()) else { return }
        let title = "Repo over budget · \(repo.repo)"
        let body  = "Today $\(String(format: "%.2f", repo.costUSD)) ≥ budget $\(String(format: "%.2f", dailyLimit))"

        if usesSystemCenter {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body
            content.sound = .default
            content.categoryIdentifier = Self.repoOverspendCategoryID
            content.userInfo = ["repo": repo.id, "cost": repo.costUSD]
            let req = UNNotificationRequest(identifier: "\(NotificationKind.repoOverspend.rawValue)-\(repo.id)",
                                             content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        } else {
            handler(.repoOverspend, title, body)
        }
    }
```

- [ ] **Step 3: Handle delegate callbacks**

Have `AppCoordinator` (or a dedicated `NotificationDelegate`) implement `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`. On `MARK_PAUSED`, append a `Commitment(status: .markedPaused)`. On `IGNORE`, append `.ignored`. Default tap → open popover (existing behavior).

In `AppCoordinator.swift`:

```swift
    let commitments = CommitmentLog()

    // Add at end of init or in start():
    UNUserNotificationCenter.current().delegate = NotificationActionRelay(
        commitments: commitments
    )
```

Define a helper class:

```swift
@MainActor
final class NotificationActionRelay: NSObject, UNUserNotificationCenterDelegate {
    let commitments: CommitmentLog
    init(commitments: CommitmentLog) { self.commitments = commitments }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let repo = info["repo"] as? String ?? ""
        let cost = info["cost"] as? Double ?? 0
        let action = response.actionIdentifier
        Task { @MainActor in
            let status: Commitment.Status
            switch action {
            case NotificationManager.actionMarkPaused: status = .markedPaused
            case NotificationManager.actionIgnore:     status = .ignored
            default:
                completionHandler(); return
            }
            commitments.record(Commitment(
                id: UUID(), repo: repo, triggeredAt: Date(),
                dailyOverspendUSD: cost, status: status
            ))
            completionHandler()
        }
    }
}
```

(Store the relay so it isn't deallocated — `private var notificationDelegate: NotificationActionRelay?`.)

- [ ] **Step 4: Verify build + manual notification flow if possible**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

(No automated test for the UN action callbacks — too entangled with system. Manual verification deferred.)

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(app): repo-overspend actionable buttons + CommitmentLog wiring"
```

---

### Task 13: Recent commitments sheet

**Files:**
- Create: `Sources/ClaudegrainApp/CommitmentsSheet.swift`
- Modify: `Sources/ClaudegrainApp/DetailPanel.swift` (add footer link)

- [ ] **Step 1: Implement sheet**

```swift
import SwiftUI
import ClaudegrainCore

struct CommitmentsSheet: View {
    @ObservedObject var log: CommitmentLog
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t(.commitmentsTitle))
                .font(.headline)
            if log.entries.isEmpty {
                Text(model.t(.commitmentsEmpty))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                List(log.entries.reversed()) { c in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.repo).bold()
                            Text(formatTime(c.triggeredAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(statusLabel(c.status))
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(statusColor(c.status).opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 240)
            }
            HStack { Spacer(); Button(model.t(.commitmentsClose)) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 460, height: 360)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }

    private func statusLabel(_ s: Commitment.Status) -> String {
        switch s {
        case .open:         return model.t(.commitmentsStatusOpen)
        case .markedPaused: return model.t(.commitmentsStatusPaused)
        case .ignored:      return model.t(.commitmentsStatusIgnored)
        }
    }

    private func statusColor(_ s: Commitment.Status) -> Color {
        switch s {
        case .open:         return .yellow
        case .markedPaused: return .green
        case .ignored:      return .gray
        }
    }
}
```

- [ ] **Step 2: Add a footer link in DetailPanel**

Below the existing `kbd(...)` footer row, add a small button "Recent commitments [N]" that opens the sheet via a presentation closure on `AppModel` (`commitmentsHandler`). Wire from `ClaudegrainApp.swift` similar to refreshHandler.

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudegrainApp/
git commit -m "feat(app): Recent commitments sheet"
```

---

## Section E: Localization, ADRs, release

### Task 14: Localization additions for v0.2 control

**Files:**
- Modify: `Sources/ClaudegrainApp/Localization.swift`

- [ ] **Step 1: Add keys**

Append to `enum L`:

```swift
    // v0.2 — settings tabs
    case settingsBudgets
    case settingsQuietHours

    // v0.2 — budgets
    case budgetsGlobalSection
    case budgetsGlobalDaily
    case budgetsRepoSection
    case budgetsAddSection
    case budgetsAddRepoPlaceholder
    case budgetsAddButton
    case budgetsEmpty

    // v0.2 — quiet hours
    case quietHoursEnable
    case quietHoursFrom
    case quietHoursTo
    case quietHoursDeviceLocal
    case quietHoursDescription

    // v0.2 — pause
    case kbPause
    case menuPauseIngest
    case menuResumeIngest
    case pauseBannerTitle
    case pauseBannerLastUpdate
    case pauseBannerResume

    // v0.2 — commitments
    case commitmentsTitle
    case commitmentsEmpty
    case commitmentsClose
    case commitmentsStatusOpen
    case commitmentsStatusPaused
    case commitmentsStatusIgnored
    case commitmentsFooterLink         // "Recent commitments [%d]"
```

- [ ] **Step 2: EN translations**

```swift
        .settingsBudgets:           "Budgets",
        .settingsQuietHours:        "Quiet Hours",
        .budgetsGlobalSection:      "Global default",
        .budgetsGlobalDaily:        "Daily $",
        .budgetsRepoSection:        "Per-repo overrides",
        .budgetsAddSection:         "Add repo budget",
        .budgetsAddRepoPlaceholder: "Repo path or alias",
        .budgetsAddButton:          "Add",
        .budgetsEmpty:              "No per-repo budgets yet. Recent repos will appear here as you use Claude Code.",
        .quietHoursEnable:          "Enable quiet hours",
        .quietHoursFrom:            "From",
        .quietHoursTo:              "To",
        .quietHoursDeviceLocal:     "Time zone: device local",
        .quietHoursDescription:     "Notifications during this window are suppressed. The menu bar icon and popover still update.",
        .kbPause:                   "pause",
        .menuPauseIngest:           "Pause Ingest",
        .menuResumeIngest:          "Resume Ingest",
        .pauseBannerTitle:          "Paused",
        .pauseBannerLastUpdate:     "last updated %@",
        .pauseBannerResume:         "Resume",
        .commitmentsTitle:          "Recent commitments",
        .commitmentsEmpty:          "No commitments recorded yet.",
        .commitmentsClose:          "Close",
        .commitmentsStatusOpen:     "open",
        .commitmentsStatusPaused:   "paused",
        .commitmentsStatusIgnored:  "ignored",
        .commitmentsFooterLink:     "Recent commitments [%d]",
```

- [ ] **Step 3: ZH translations**

```swift
        .settingsBudgets:           "预算",
        .settingsQuietHours:        "免打扰",
        .budgetsGlobalSection:      "全局默认",
        .budgetsGlobalDaily:        "日预算 $",
        .budgetsRepoSection:        "按仓库覆盖",
        .budgetsAddSection:         "添加仓库预算",
        .budgetsAddRepoPlaceholder: "仓库路径或别名",
        .budgetsAddButton:          "添加",
        .budgetsEmpty:              "暂无单仓库预算。使用 Claude Code 后,最近活跃仓库会出现在这里。",
        .quietHoursEnable:          "启用免打扰时段",
        .quietHoursFrom:            "从",
        .quietHoursTo:              "到",
        .quietHoursDeviceLocal:     "时区:本机本地",
        .quietHoursDescription:     "时段内不投递通知。菜单栏图标和 popover 仍会更新。",
        .kbPause:                   "暂停",
        .menuPauseIngest:           "暂停采集",
        .menuResumeIngest:          "恢复采集",
        .pauseBannerTitle:          "已暂停",
        .pauseBannerLastUpdate:     "最后更新 %@",
        .pauseBannerResume:         "恢复",
        .commitmentsTitle:          "最近承诺",
        .commitmentsEmpty:          "暂无承诺记录。",
        .commitmentsClose:          "关闭",
        .commitmentsStatusOpen:     "未处理",
        .commitmentsStatusPaused:   "已暂停",
        .commitmentsStatusIgnored:  "已忽略",
        .commitmentsFooterLink:     "最近承诺 [%d]",
```

- [ ] **Step 4: Verify build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(app): localization keys for v0.2 control surfaces"
```

---

### Task 15: ADRs 0008, 0009, 0010

**Files:**
- Create: `docs/adr/0008-budget-storage.md`
- Create: `docs/adr/0009-quiet-hours-suppress-only.md`
- Create: `docs/adr/0010-commitment-log.md`

- [ ] **Step 1: Write the three ADRs**

`0008-budget-storage.md`:

```markdown
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
```

`0009-quiet-hours-suppress-only.md`:

```markdown
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
```

`0010-commitment-log.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/adr/0008-budget-storage.md docs/adr/0009-quiet-hours-suppress-only.md docs/adr/0010-commitment-log.md
git commit -m "docs(adr): 0008 budget-storage + 0009 quiet-hours + 0010 commitment-log"
```

---

### Task 16: VERSION + CHANGELOG bump, full test, tag rc5, push, PR

**Files:**
- Modify: `VERSION`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: VERSION = `0.1.6-rc5`**

- [ ] **Step 2: CHANGELOG entry, inserted at top above the previous entry (whatever it is — read first)**

```markdown
## [0.1.6-rc5] — 2026-05-05

Phase 3 of v0.2 — control. Adds proactive notification + ingestion
controls.

### Added
- Per-repo soft budgets (`BudgetStore`). Replaces the single
  `repoOverspendThresholdUSD` value (auto-migrated). New `Budgets`
  settings tab. (ADR-0008)
- Quiet Hours window suppresses all notifications during a configurable
  daily slice (cross-midnight supported). New `Quiet Hours` settings
  tab. (ADR-0009)
- Pause Ingest toggle — halts FSEvents + OAuth polling; resume runs
  catch-up via existing cursor logic. Right-click menu item, `p`
  footer button, popover banner.
- Repo-overspend notifications now carry actionable buttons
  (`Mark as paused` / `Ignore`). Responses are logged to
  `CommitmentLog` (separate JSON file). New `Recent commitments` sheet.
  (ADR-0010)
- Localization: ~30 new EN/ZH strings.

### Changed
- `NotificationManager` consults `BudgetStore.resolve(repo:)` instead
  of a single global threshold.
- `NotificationManager.fire(...)` gated on `QuietHours.contains(now)`.

### Docs
- ADR-0008 budget-storage
- ADR-0009 quiet-hours-suppress-only
- ADR-0010 commitment-log
```

- [ ] **Step 3: Full test suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | grep -E "Executed|failed" | tail -1
```

Expected: ~85 tests pass (Phase 2's 73 + ~12 new across Phase 3).

If anything fails, STOP. BLOCKED.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION CHANGELOG.md
git commit -m "release: v0.1.6-rc5 (phase 3 — control)"
git tag v0.1.6-rc5
```

Don't push — controller decides.

- [ ] **Step 5: Verify branch state**

```bash
git log --oneline main..HEAD | head -25
echo --- VERSION ---
cat VERSION
echo --- TAG ---
git tag --list 'v0.1.6*'
```

---

## Self-Review

**Spec coverage:**
- §4.5 C1 — RepoBudget + BudgetStore ✓ (T1), migration ✓ (T2), NotificationManager wiring ✓ (T3), Settings tab ✓ (T4)
- §4.6 C2 — QuietHours struct + cross-midnight logic ✓ (T5), shouldDeliver gate ✓ (T6), Settings tab ✓ (T7)
- §4.7 C3 — IngestPauseController ✓ (T8), ingest+OAuth coupling ✓ (T9), UI ✓ (T10)
- §4.8 C4 — Commitment + CommitmentLog ✓ (T11), UN actions ✓ (T12), sheet ✓ (T13)
- ADRs ✓ (T15)
- Localization ✓ (T14)
- Release ✓ (T16)

**Placeholder scan:** No "TBD" / "TODO" markers. All steps contain runnable code or exact commands.

**Type consistency:**
- `BudgetStore` — same name throughout (T1, T2, T3, T4)
- `RepoBudget(repo:dailyUSD:weeklyUSD:)` — consistent across all uses
- `QuietHours(enabled:startHour:startMinute:endHour:endMinute:)` — consistent
- `IngestPauseController.{pause,resume,toggle}` — consistent
- `Commitment.Status` — `.open / .markedPaused / .ignored` matches ADR-0010 + UI sheet + UN delegate
- `NotificationManager.actionMarkPaused / actionIgnore` — same identifiers in both T12 fire-side + T12 delegate-side

---

## Execution handoff

Plan saved. Phase 4 (D widget) and Phase 5 (E polish) plans will be written when Phase 3 lands.
