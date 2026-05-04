import Foundation
import ServiceManagement

/// Toggles the app's "open at login" registration via the macOS 13+
/// `SMAppService` API. The app does not auto-register itself; the user
/// must explicitly enable this in Settings.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        self.isEnabled = Self.derive(status: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        // Reflect actual post-call status, not the requested value: the
        // user may have denied the prompt in System Settings.
        isEnabled = Self.derive(status: service.status)
    }

    func refresh() {
        isEnabled = Self.derive(status: service.status)
    }

    private static func derive(status: SMAppService.Status) -> Bool {
        status == .enabled
    }
}
