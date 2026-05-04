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

    /// Stub for v0.2 burn-rate computation (toggle `b`).
    func noteBurnRate(tokensPerMinute: Double) {
        guard prefs.notifyBurnRate else { return }
        // TODO: implement burn-rate logic in task >9.
    }

    /// Stub for v0.2 repo-overspend check (toggle `d`).
    func noteRepoOverspend(repo: String, costUSD: Double) {
        guard prefs.notifyRepoOverspend else { return }
        // TODO: implement in task >9.
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

