import Foundation
import UserNotifications
import os.log
import ClaudegrainCore

enum NotificationKind: String, Hashable {
    case sessionWarn70
    case sessionCritical90
    case weeklyWarn85
    case blockResetSoon
    case burnRate
    case repoOverspend
}

@MainActor
final class NotificationManager {
    typealias Handler = (NotificationKind, String, String) -> Void

    static let repoOverspendCategoryID = "REPO_OVERSPEND"
    static let actionMarkPaused = "MARK_PAUSED"
    static let actionIgnore     = "IGNORE"

    private let prefs: Preferences
    private let budgets: BudgetStore
    private let handler: Handler
    private let usesSystemCenter: Bool
    private var lastFiredBySessionStart: [Date: Set<NotificationKind>] = [:]
    private var weeklyResetFired: [Date: Set<NotificationKind>] = [:]
    private var blockResetFiredFor: Date?
    private var burnRateFiredFor: Date?
    private var repoOverspendFired: Set<RepoOverspendKey> = []
    private var authRequested = false
    private static let logger = Logger(subsystem: "dev.claudegrain.menubar", category: "notify")

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

    func evaluate(session: SessionBlockSnapshot?, weekly: WeeklyUsageSnapshot?) {
        ensureAuthorization()

        if prefs.notifyThreshold {
            if let session {
                checkSession(session)
            }
            if let weekly {
                checkWeekly(weekly)
            }
        }

        if prefs.notifyBlockReset, let session {
            checkBlockReset(session)
        }
    }

    /// Wired by `AppCoordinator` after each ingest snapshot so we can react to
    /// repo-level activity and burn-rate spikes against jsonl-derived state.
    func evaluateUsage(
        session: SessionBlockSnapshot?,
        weekly: WeeklyUsageSnapshot?,
        topRepos: [RepoBreakdown]
    ) {
        evaluate(session: session, weekly: weekly)

        if prefs.notifyRepoOverspend {
            checkRepoOverspend(topRepos)
        }
    }

    /// Forecaster-gated burn-rate notification. Fires once per session block when
    /// (willHit == true) AND (confidence >= .medium). Replaces the >2× linear pace
    /// rule (ADR-0005).
    func evaluateBurnRate(session: SessionBlockSnapshot?, forecast: ForecastResult?) {
        guard prefs.notifyBurnRate,
              let session,
              let forecast,
              forecast.willHit,
              forecast.confidence != .low
        else {
            burnRateFiredFor = nil
            return
        }
        guard burnRateFiredFor != session.startedAt else { return }
        let etaMin = forecast.hitAt.map { Int($0.timeIntervalSinceNow / 60) } ?? -1
        fire(.burnRate,
             title: "Claude burn rate spiking",
             body: "Forecast: hit \(forecast.basis.rawValue.uppercased()) " +
                   "(\(forecast.confidence.rawValue)) · ETA ~\(etaMin) min")
        burnRateFiredFor = session.startedAt
    }

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
        let body  = "\(repo.id): today $\(String(format: "%.2f", repo.costUSD)) ≥ budget $\(String(format: "%.2f", dailyLimit))"
        if usesSystemCenter {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = Self.repoOverspendCategoryID
            content.userInfo = ["repo": repo.id, "cost": repo.costUSD]
            let req = UNNotificationRequest(
                identifier: "\(NotificationKind.repoOverspend.rawValue)-\(repo.id)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        } else {
            handler(.repoOverspend, title, body)
        }
    }

    private struct RepoOverspendKey: Hashable {
        let date: Date
        let repo: String
    }

    private func checkSession(_ s: SessionBlockSnapshot) {
        let bucket = lastFiredBySessionStart[s.startedAt] ?? []
        var fired = bucket
        if s.usedFraction >= 0.9, !bucket.contains(.sessionCritical90) {
            fire(.sessionCritical90, title: "Claude session 90% used",
                 body: "Resets in \(s.resetCountdown).")
            fired.insert(.sessionCritical90)
        } else if s.usedFraction >= 0.7, !bucket.contains(.sessionWarn70) {
            fire(.sessionWarn70, title: "Claude session 70% used",
                 body: "Resets in \(s.resetCountdown).")
            fired.insert(.sessionWarn70)
        }
        lastFiredBySessionStart[s.startedAt] = fired
    }

    private func checkWeekly(_ w: WeeklyUsageSnapshot) {
        let bucket = weeklyResetFired[w.resetsAt] ?? []
        guard w.usedFraction >= 0.85, !bucket.contains(.weeklyWarn85) else { return }
        fire(.weeklyWarn85, title: "Claude weekly 85% used",
             body: "Resets \(w.resetLabel).")
        weeklyResetFired[w.resetsAt] = bucket.union([.weeklyWarn85])
    }

    private func checkBlockReset(_ s: SessionBlockSnapshot) {
        let remaining = s.resetsAt.timeIntervalSinceNow
        guard remaining > 0, remaining <= 600 else { return }
        guard blockResetFiredFor != s.startedAt else { return }
        fire(.blockResetSoon, title: "Claude block resets in 10 min",
             body: "Used \(Int((s.usedFraction * 100).rounded()))%.")
        blockResetFiredFor = s.startedAt
    }

    private func fire(_ kind: NotificationKind, title: String, body: String) {
        guard shouldDeliver(now: Date()) else {
            Self.logger.info("notification \(kind.rawValue, privacy: .public) suppressed by quiet hours")
            return
        }
        Self.logger.notice("notification fire: \(kind.rawValue, privacy: .public) — \(title, privacy: .public)")
        handler(kind, title, body)
    }

    private func shouldDeliver(now: Date) -> Bool {
        !prefs.quietHours.contains(now)
    }

    private func ensureAuthorization() {
        guard usesSystemCenter, !authRequested else { return }
        authRequested = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("notification auth request failed: \(String(describing: error), privacy: .public)")
            } else {
                Self.logger.notice("notification auth granted=\(granted, privacy: .public)")
            }
        }

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

    private static func defaultHandler(kind: NotificationKind, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // TODO: replace with custom asset when SoundChoice.app gets a bundled file.
        content.sound = .default
        let req = UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

