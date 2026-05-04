import Foundation
import Combine
import ClaudegrainCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sessionBlock: SessionBlockSnapshot?
    @Published var weekly: WeeklyUsageSnapshot?
    @Published var todayTotals: DailyTotals = .zero
    @Published var topRepos: [RepoBreakdown] = []
    @Published var topTools: [ToolBreakdown] = []
    @Published var cacheHitRate: Double = 0
    @Published var dataSourceStatus: DataSourceStatus = .unknown

    let loginItem: LoginItemController
    let preferences: Preferences

    var primaryMetric: PrimaryMetric {
        get { preferences.primaryMetric }
        set { preferences.primaryMetric = newValue; objectWillChange.send() }
    }

    init(loginItem: LoginItemController? = nil, preferences: Preferences? = nil) {
        self.loginItem = loginItem ?? LoginItemController()
        self.preferences = preferences ?? .shared
    }
}

enum DataSourceStatus {
    case unknown
    case oauthLive
    case jsonlOnly
    case cliFallback
    case offline
}
