import WidgetKit
import ClaudegrainCore

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isStale: Bool

    static let placeholder: WidgetEntry = {
        let snap = WidgetSnapshot(
            generatedAt: Date(),
            language: "en",
            primaryMetric: "spend",
            dataSourceStatus: "oauthLive",
            sessionBlockPercent: 0.47,
            sessionBlockResetAt: Date().addingTimeInterval(3 * 3600 + 12 * 60),
            weeklyPercent: 0.31,
            todayCostUSD: 3.42,
            todayTokens: 1_200_000,
            weekSpend: [0.5, 0.9, 0.4, 1.2, 1.7, 1.0, 3.42],
            topRepos: [
                .init(name: "menu-hub", costUSD: 1.80, percentOfDay: 0.53),
                .init(name: "prism-endpoint", costUSD: 0.90, percentOfDay: 0.26),
                .init(name: "dotfiles", costUSD: 0.30, percentOfDay: 0.09),
            ],
            cacheHitRate: 0.87
        )
        return WidgetEntry(date: Date(), snapshot: snap, isStale: false)
    }()
}

/// Reads the host-written snapshot from the App Group container. Times out
/// after 15 min — provider returns a single entry with `.after(...)` policy
/// so WidgetKit asks again. The host throttle plus this re-ask interval
/// gives ~5–15 min effective freshness.
struct WidgetSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(currentEntry() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = currentEntry() ?? .placeholder
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> WidgetEntry? {
        guard let io = WidgetSnapshotIO.appGroupContainer(),
              let snap = io.read() else { return nil }
        let stale = Date().timeIntervalSince(snap.generatedAt) > 30 * 60
        return WidgetEntry(date: Date(), snapshot: snap, isStale: stale)
    }
}
