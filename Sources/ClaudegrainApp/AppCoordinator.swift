import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications
import WidgetKit
import ClaudegrainCore

/// Wires `IngestActor` (jsonl pipeline) and `DataSourceCoordinator` (OAuth poll)
/// into the main-actor `AppModel`. Single instance per app launch.
@MainActor
final class AppCoordinator {
    private let model: AppModel
    private let db: EventsDatabase
    private let ingest: IngestActor
    private let dataSource: DataSourceCoordinator
    private let notifications: NotificationManager
    private let forecaster = Forecaster()
    /// JSONL P90 fallback per ADR-0001. Wired in production for the first
    /// time in v0.2 — previously declared but never called, leaving users
    /// without OAuth credentials stuck on `0% session` forever.
    private let estimator: LimitEstimator
    private var ingestTask: Task<Void, Never>?
    private var dataSourceTask: Task<Void, Never>?

    /// Exposed so menu / popover entry points can present the export sheet.
    let exporter: EventsExporter
    let budgets: BudgetStore
    let pauseController: IngestPauseController
    let commitments: CommitmentLog
    private var pauseSubscription: AnyCancellable?
    private var notificationDelegate: NotificationActionRelay?
    private var exportWindow: NSWindow?
    private var commitmentsWindow: NSWindow?

    /// 5-minute throttle on widget-snapshot writes. WidgetKit budgets
    /// ~40 timeline reloads/day; bursting on every JSONL ingest event
    /// would burn that budget. See plan §4.
    private var lastWidgetWriteAt: Date?
    private static let widgetWriteInterval: TimeInterval = 5 * 60

    init(
        model: AppModel,
        notifications: NotificationManager? = nil,
        dbOverride: EventsDatabase? = nil
    ) throws {
        self.model = model
        if let dbOverride {
            self.db = dbOverride
        } else {
            self.db = try EventsDatabase(url: EventsDatabase.defaultURL)
        }
        self.ingest = IngestActor(db: db)
        self.dataSource = DataSourceCoordinator()
        self.estimator = LimitEstimator(db: db)

        // Reuse the BudgetStore owned by AppModel so the Settings UI and
        // the NotificationManager observe the same instance.
        let store = model.budgets
        store.migrateLegacyKeyIfNeeded()
        self.budgets = store

        self.notifications = notifications ?? NotificationManager(prefs: model.preferences, budgets: store)
        self.exporter = EventsExporter(db: self.db)
        // Reuse the AppModel-owned pauseController so popover banner + menu
        // observe the same instance the coordinator drives.
        self.pauseController = model.pauseController
        self.commitments = model.commitments
    }

    /// Opens the export sheet as a standalone window. LSUIElement = true ⇒ activate
    /// explicitly so the window keys properly. Reuses one window across invocations.
    func openExportSheet() {
        if let win = exportWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let coord = ExportSheetCoordinator(exporter: exporter)
        let view = ExportSheet(coord: coord)
            .environmentObject(model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = model.t(.exportSheetTitle)
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        exportWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens the recent commitments sheet as a standalone window.
    func openCommitmentsSheet() {
        if let win = commitmentsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = CommitmentsSheet(log: commitments)
            .environmentObject(model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = model.t(.commitmentsTitle)
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        commitmentsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func start() async {
        // Wire UN action callbacks → CommitmentLog. Retain the relay so it's
        // not deallocated; UNUserNotificationCenter only weak-holds delegates.
        let relay = NotificationActionRelay(commitments: commitments)
        UNUserNotificationCenter.current().delegate = relay
        self.notificationDelegate = relay

        // Apply the last-good LiteLLM price catalog (if any) before we cost
        // any events, then kick off a daily background refresh.
        await PriceTableLoader.shared.applyDiskCache()
        await PriceTableLoader.shared.startPeriodicRefresh()

        let snapshotStream = await ingest.startStream()
        let dataSourceStream = await dataSource.start()

        // Bootstrap last 7d in the background so the UI is populated quickly.
        ingestTask = Task { [ingest] in
            try? await ingest.bootstrap(daysBack: 7)
            await ingest.startWatching()
        }

        // Consume snapshot stream → main-actor publish.
        Task { [weak self] in
            for await snapshot in snapshotStream {
                self?.applyIngestSnapshot(snapshot)
            }
        }
        Task { [weak self] in
            for await snapshot in dataSourceStream {
                self?.applyDataSourceSnapshot(snapshot)
            }
        }

        // Honor pause state changes — halt or resume both ingest and OAuth.
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

        // Kick an immediate OAuth + ingest poll so the popover shows real
        // sessionBlock/weekly values without the user having to F5 once at boot.
        Task { [ingest, dataSource, pauseController] in
            guard !pauseController.isPaused else { return }
            await ingest.refreshNow()
            await dataSource.refreshNow()
        }
    }

    func stop() async {
        ingestTask?.cancel()
        dataSourceTask?.cancel()
        await ingest.stop()
        await dataSource.stop()
        await PriceTableLoader.shared.stopPeriodicRefresh()
    }

    /// User-initiated refresh (F5). Re-scans recent JSONL and pings the OAuth path.
    func refreshNow() async {
        await ingest.refreshNow()
        await dataSource.refreshNow()
    }

    private func applyIngestSnapshot(_ snapshot: IngestActor.Snapshot) {
        model.todayTotals = snapshot.today
        model.allTimeTotals = snapshot.allTime
        model.topRepos = snapshot.topRepos
        model.topTools = snapshot.topTools
        model.cacheHitRate = snapshot.cacheHitRate
        model.weekSpend = snapshot.weekSpend
        Task { [weak self] in await self?.refreshDerivedNow() }
        notifications.evaluateUsage(
            session: model.sessionBlock,
            weekly: model.weekly,
            topRepos: snapshot.topRepos
        )
    }

    /// Recompute all derived/aggregated fields from the current DB state and
    /// publish them on `AppModel`. Called on every refresh tick.
    func refreshDerivedNow() async {
        let now = Date()

        // 1. Model mix — last 24h.
        let dayStart = now.addingTimeInterval(-24 * 3600)
        let costsByFamily = (try? await db.costPerModel(since: dayStart, until: now)) ?? [:]
        let totalDaily = costsByFamily.values.reduce(0, +)
        if totalDaily > 0 {
            model.modelMix = costsByFamily.mapValues { $0 / totalDaily }
        } else {
            model.modelMix = [:]
        }

        // 2. WeekDelta.
        model.weekDelta = await WeekDelta.compute(db: db, now: now)

        // 3. Forecast block + weekly. Pass hourly_buckets to enable ADR-0016
        // cycle-aware blend; the forecaster falls back to v1 ewma when hourly
        // data is thin (<3 trusted slots in remaining window).
        let buckets = (try? await db.costPerBucket(
            start: now.addingTimeInterval(-3600),
            span:  3600,
            bucketSize: 5 * 60
        )) ?? []
        let hourly = (try? await db.hourlyBuckets()) ?? []
        model.hourlyBuckets = hourly
        if let session = model.sessionBlock {
            model.forecastBlock = await forecaster.forecastSessionBlock(
                block: session, recent: buckets, hourly: hourly
            )
        }
        if let weekly = model.weekly {
            model.forecastWeekly = await forecaster.forecastWeekly(
                weekly: weekly, recent: buckets, hourly: hourly
            )
        }
        notifications.evaluateBurnRate(session: model.sessionBlock, forecast: model.forecastBlock)

        await fillJSONLFallbackIfNeeded()
        await writeWidgetSnapshotIfDue()
    }

    /// JSONL P90 fallback. When OAuth path is not live (boot, no creds,
    /// 4xx, deprecated), populate sessionBlock + weekly from local jsonl
    /// history so the popover shows numbers instead of `—`. OAuth (when it
    /// later succeeds) overrides on next snapshot.
    private func fillJSONLFallbackIfNeeded() async {
        guard model.dataSourceStatus != .oauthLive else { return }
        var didFill = false
        if model.sessionBlock == nil {
            if let s = try? await estimator.estimateSessionBlock() {
                model.sessionBlock = s
                didFill = true
            }
        }
        if model.weekly == nil {
            if let w = try? await estimator.estimateWeekly() {
                model.weekly = w
                didFill = true
            }
        }
        // Promote stuck `.unknown` to `.jsonlOnly` once the fallback
        // succeeds — keeps the header label honest about what's on screen.
        if didFill && model.dataSourceStatus == .unknown {
            model.dataSourceStatus = .jsonlOnly
        }
    }

    /// Builds a `WidgetSnapshot` from the current `AppModel` state and writes
    /// it to the App Group container (or Application Support fallback in
    /// dev). Throttled to once per `widgetWriteInterval` to stay inside
    /// WidgetKit's reload budget.
    private func writeWidgetSnapshotIfDue() async {
        let now = Date()
        if let last = lastWidgetWriteAt,
           now.timeIntervalSince(last) < Self.widgetWriteInterval {
            return
        }

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            language: model.preferences.language.rawValue,
            primaryMetric: model.primaryMetric.rawValue,
            dataSourceStatus: dataSourceStatusString(model.dataSourceStatus),
            sessionBlockPercent: model.sessionBlock?.usedFraction,
            sessionBlockResetAt: model.sessionBlock?.resetsAt,
            weeklyPercent: model.weekly?.usedFraction,
            todayCostUSD: model.todayTotals.costUSD,
            todayTokens: model.todayTotals.totalTokens,
            weekSpend: model.weekSpend,
            topRepos: model.topRepos.prefix(3).map { repo in
                let pct = model.todayTotals.costUSD > 0
                    ? min(1, repo.costUSD / model.todayTotals.costUSD)
                    : 0
                return WidgetSnapshot.Repo(name: repo.repo, costUSD: repo.costUSD, percentOfDay: pct)
            },
            cacheHitRate: model.cacheHitRate
        )

        let io = Self.resolveWidgetIO()
        do {
            try io.write(snapshot)
            lastWidgetWriteAt = now
            // Tell WidgetKit there's a new snapshot. Throttle is upstream of
            // this call (5-min gate above) so we never burn the OS budget.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Snapshot writes are best-effort. Failure here just delays the
            // widget update; the next scheduled refresh tries again.
            NSLog("widget snapshot write failed: \(error.localizedDescription)")
        }
    }

    /// Resolves the App Group container; falls back to Application Support
    /// when the host isn't entitled (P4-T05 will land entitlements). The
    /// widget extension can only read the App Group path, so this fallback
    /// is dev-only — it lets us validate snapshot generation in SwiftPM
    /// builds before the Xcode project + entitlements ship.
    private static func resolveWidgetIO() -> WidgetSnapshotIO {
        if let io = WidgetSnapshotIO.appGroupContainer() { return io }
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("claudegrain")) ?? fm.temporaryDirectory
        return WidgetSnapshotIO(directory: support)
    }

    private func dataSourceStatusString(_ status: DataSourceStatus) -> String {
        switch status {
        case .oauthLive:    return "oauthLive"
        case .jsonlOnly:    return "jsonlOnly"
        case .cliFallback:  return "cliFallback"
        case .offline:      return "offline"
        case .unknown:      return "unknown"
        }
    }

    private func applyDataSourceSnapshot(_ snapshot: DataSourceCoordinator.Snapshot) {
        if let session = snapshot.session { model.sessionBlock = session }
        if let weekly = snapshot.weekly { model.weekly = weekly }
        switch snapshot.state {
        case .oauthLive:
            model.dataSourceStatus = .oauthLive
            model.lastOAuthSyncAt = Date()
            model.oauthDegraded = false
        case .jsonlOnly:
            model.dataSourceStatus = .jsonlOnly
            model.oauthDegraded = false
        case .oauthAuthError, .oauthDeprecated:
            // ADR-0004: real-time path collapsed permanently or until reauth.
            // UI surfaces a banner so the user knows quotas are estimates.
            model.dataSourceStatus = .jsonlOnly
            model.oauthDegraded = true
        case .oauthBackoff:
            // Keep the prior status; the snapshot UI shows "stale" until next tick succeeds.
            break
        case .checking:
            model.dataSourceStatus = .unknown
        }
        notifications.evaluate(session: model.sessionBlock, weekly: model.weekly)
    }
}

#if DEBUG
enum AppCoordinatorTestHook {
    @MainActor
    static func make(model: AppModel, db: EventsDatabase) throws -> AppCoordinator {
        try AppCoordinator(model: model, dbOverride: db)
    }
}
#endif
