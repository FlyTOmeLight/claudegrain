import Foundation
import UserNotifications
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

    private let prefs: Preferences
    private let handler: Handler
    private let usesSystemCenter: Bool
    private var lastFiredBySessionStart: [Date: Set<NotificationKind>] = [:]
    private var weeklyResetFired: [Date: Set<NotificationKind>] = [:]
    private var blockResetFiredFor: Date?
    private var burnRateFiredFor: Date?
    private var repoOverspendFired: Set<RepoOverspendKey> = []
    private var authRequested = false

    init(prefs: Preferences? = nil, handler: Handler? = nil) {
        self.prefs = prefs ?? .shared
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
        let threshold = prefs.repoOverspendThresholdUSD
        for repo in topRepos.prefix(5) where repo.costUSD >= threshold {
            let key = RepoOverspendKey(date: Calendar.current.startOfDay(for: Date()), repo: repo.id)
            guard !repoOverspendFired.contains(key) else { continue }
            fire(.repoOverspend,
                 title: "Repo over budget · \(repo.repo)",
                 body: "Today $\(String(format: "%.2f", repo.costUSD)) ≥ threshold $\(String(format: "%.2f", threshold))")
            repoOverspendFired.insert(key)
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
        handler(kind, title, body)
    }

    private func ensureAuthorization() {
        guard usesSystemCenter, !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

