import AppKit
import SwiftUI

/// Hosts the Settings UI in a manually-managed NSWindow.
///
/// Why not `Settings { SettingsView() }`: with `LSUIElement = true` the app has no
/// main menu, so the SwiftUI Settings scene never gets a routable menu item. The
/// stock `\.openSettings` env action and the `showSettingsWindow:` selector both
/// quietly become no-ops because there's nothing in the responder chain that
/// claims them. Hosting our own NSWindow side-steps the whole responder dance.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(model: AppModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView().environmentObject(model)
        let host = NSHostingController(rootView: root)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = model.t(.kbCfg)
        w.contentViewController = host
        w.isReleasedWhenClosed = false
        w.center()

        self.window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
