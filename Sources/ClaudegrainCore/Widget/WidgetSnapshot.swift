import Foundation

/// Cross-process contract between the host app and the WidgetKit extension.
///
/// The widget extension runs in its own sandboxed process and cannot read
/// `cache.db` (Application Support) or `commitments.json`. The host writes
/// this single JSON file into the App Group container; the extension reads
/// it. See `docs/plans/v0.2-phase4-widget.md` §3 for the full contract.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let language: String
    public let primaryMetric: String
    public let dataSourceStatus: String

    // Hero
    public let sessionBlockPercent: Double?
    public let sessionBlockResetAt: Date?
    public let weeklyPercent: Double?
    public let todayCostUSD: Double
    public let todayTokens: Int

    // Medium adds
    public let weekSpend: [Double]

    // Large adds
    public let topRepos: [Repo]
    public let cacheHitRate: Double

    public struct Repo: Codable, Equatable, Sendable {
        public let name: String
        public let costUSD: Double
        public let percentOfDay: Double

        public init(name: String, costUSD: Double, percentOfDay: Double) {
            self.name = name
            self.costUSD = costUSD
            self.percentOfDay = percentOfDay
        }
    }

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        language: String,
        primaryMetric: String,
        dataSourceStatus: String,
        sessionBlockPercent: Double?,
        sessionBlockResetAt: Date?,
        weeklyPercent: Double?,
        todayCostUSD: Double,
        todayTokens: Int,
        weekSpend: [Double],
        topRepos: [Repo],
        cacheHitRate: Double
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.language = language
        self.primaryMetric = primaryMetric
        self.dataSourceStatus = dataSourceStatus
        self.sessionBlockPercent = sessionBlockPercent
        self.sessionBlockResetAt = sessionBlockResetAt
        self.weeklyPercent = weeklyPercent
        self.todayCostUSD = todayCostUSD
        self.todayTokens = todayTokens
        self.weekSpend = weekSpend
        self.topRepos = topRepos
        self.cacheHitRate = cacheHitRate
    }

    /// Empty snapshot used when ingest hasn't populated state yet. The
    /// extension renders a "Open Claudegrain to populate" UI on this.
    public static func empty(language: String = "en") -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            language: language,
            primaryMetric: "spend",
            dataSourceStatus: "unknown",
            sessionBlockPercent: nil,
            sessionBlockResetAt: nil,
            weeklyPercent: nil,
            todayCostUSD: 0,
            todayTokens: 0,
            weekSpend: [],
            topRepos: [],
            cacheHitRate: 0
        )
    }
}
