import Foundation
import UserNotifications
import ClaudegrainCore

/// Bridges UNUserNotificationCenter action callbacks (MARK_PAUSED / IGNORE on
/// the REPO_OVERSPEND category) into a `CommitmentLog` entry. Retained by
/// `AppCoordinator` since the system holds delegates weakly.
@MainActor
final class NotificationActionRelay: NSObject, UNUserNotificationCenterDelegate {
    let commitments: CommitmentLog

    init(commitments: CommitmentLog) {
        self.commitments = commitments
    }

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
                completionHandler()
                return
            }
            commitments.record(Commitment(
                id: UUID(),
                repo: repo,
                triggeredAt: Date(),
                dailyOverspendUSD: cost,
                status: status
            ))
            completionHandler()
        }
    }
}
