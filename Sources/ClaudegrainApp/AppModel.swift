import Foundation
import Combine
import ClaudegrainCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sessionBlock: SessionBlockSnapshot?
    @Published var weekly: WeeklyUsageSnapshot?
    @Published var todayTotals: DailyTotals = .zero
    @Published var allTimeTotals: DailyTotals = .zero
    @Published var topRepos: [RepoBreakdown] = []
    @Published var topTools: [ToolBreakdown] = []
    @Published var cacheHitRate: Double = 0
    @Published var weekSpend: [Double] = []
    @Published var forecastBlock: ForecastResult?
    @Published var forecastWeekly: ForecastResult?
    @Published var weekDelta: WeekDelta?
    @Published var modelMix: [ModelFamily: Double] = [:]
    @Published var dataSourceStatus: DataSourceStatus = .unknown
    @Published var isRefreshing: Bool = false
    @Published var heroMode: HeroMode = .today

    /// Wired by `AppDelegate` after `AppCoordinator` is constructed. Nil during preview/spike.
    var refreshHandler: (@MainActor () async -> Void)?

    /// Opens the export sheet. Wired by `AppDelegate` after coordinator construction.
    /// Nil during preview/spike.
    var exportHandler: (@MainActor () -> Void)?

    /// Toggles ingest pause. Wired by `AppDelegate` after coordinator construction.
    var pauseHandler: (@MainActor () -> Void)?

    let loginItem: LoginItemController
    let preferences: Preferences
    let budgets: BudgetStore
    let pauseController: IngestPauseController
    private var prefsCancellable: AnyCancellable?
    private var budgetsCancellable: AnyCancellable?
    private var pauseCancellable: AnyCancellable?

    var primaryMetric: PrimaryMetric {
        get { preferences.primaryMetric }
        set { preferences.primaryMetric = newValue; objectWillChange.send() }
    }

    var language: AppLanguage {
        get { preferences.language }
        set { preferences.language = newValue; objectWillChange.send() }
    }

    var layoutMode: LayoutMode {
        get { preferences.layoutMode }
        set { preferences.layoutMode = newValue; objectWillChange.send() }
    }

    /// Localization shortcut. Reads the user's language preference each call,
    /// so views automatically retranslate after a language switch (because
    /// `Preferences.objectWillChange` flows through the model).
    func t(_ key: L) -> String { L10n.tr(key, language) }

    init(loginItem: LoginItemController? = nil,
         preferences: Preferences? = nil,
         budgets: BudgetStore? = nil,
         pauseController: IngestPauseController? = nil) {
        self.loginItem = loginItem ?? LoginItemController()
        let prefs = preferences ?? .shared
        self.preferences = prefs
        let store = budgets ?? BudgetStore()
        self.budgets = store
        let pause = pauseController ?? IngestPauseController()
        self.pauseController = pause
        // Forward Preferences changes so any view bound to AppModel
        // (popover, settings, menu bar label) live-updates when the user
        // toggles language / layout / metric in Settings.
        self.prefsCancellable = prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        // Forward BudgetStore changes so the Settings UI redraws when
        // budgets are added/removed/edited.
        self.budgetsCancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        // Forward IngestPauseController changes so the popover banner +
        // menu label react instantly when the user toggles pause.
        self.pauseCancellable = pause.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }
}

enum DataSourceStatus {
    case unknown
    case oauthLive
    case jsonlOnly
    case cliFallback
    case offline
}

enum HeroMode: Hashable {
    case total
    case today
}
