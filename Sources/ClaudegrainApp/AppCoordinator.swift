import Foundation
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
    private var ingestTask: Task<Void, Never>?
    private var dataSourceTask: Task<Void, Never>?

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
        self.notifications = notifications ?? NotificationManager(prefs: model.preferences)
    }

    func start() async {
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

        // 3. Forecast block + weekly.
        let buckets = (try? await db.costPerBucket(
            start: now.addingTimeInterval(-3600),
            span:  3600,
            bucketSize: 5 * 60
        )) ?? []
        if let session = model.sessionBlock {
            model.forecastBlock = await forecaster.forecastSessionBlock(block: session, recent: buckets)
        }
        if let weekly = model.weekly {
            model.forecastWeekly = await forecaster.forecastWeekly(weekly: weekly, recent: buckets)
        }
    }

    private func applyDataSourceSnapshot(_ snapshot: DataSourceCoordinator.Snapshot) {
        if let session = snapshot.session { model.sessionBlock = session }
        if let weekly = snapshot.weekly { model.weekly = weekly }
        switch snapshot.state {
        case .oauthLive: model.dataSourceStatus = .oauthLive
        case .jsonlOnly, .oauthAuthError, .oauthDeprecated:
            model.dataSourceStatus = .jsonlOnly
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
