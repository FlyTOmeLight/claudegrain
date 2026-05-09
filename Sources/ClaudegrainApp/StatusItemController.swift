import AppKit
import SwiftUI
import Combine

/// Drives an NSStatusItem with a custom SwiftUI `MenuBarLabel`. Reliable on notched
/// displays where SwiftUI's `MenuBarExtra` gets hidden behind the notch.
@MainActor
final class StatusItemController: ObservableObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var hosting: NSHostingView<MenuBarLabel>?
    private weak var model: AppModel?

    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
    }

    private var observers: [NSKeyValueObservation] = []
    private var modelCancellable: AnyObject?

    /// Memoized signature of the last applied button state. AppModel publishes
    /// many fields the menu bar doesn't render (forecast, modelMix, weekDelta,
    /// refresh flag, …); without a guard, every publish forces a redraw.
    private var lastButtonSig: String?

    func attach(model: AppModel) {
        self.model = model
        statusItem.length = NSStatusItem.variableLength

        if let button = statusItem.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            // Receive both left + right mouse-up so right-click can summon a
            // context NSMenu while left-click keeps toggling the popover.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.title = "claudegrain"
            updateButton()
        }

        // Wire popover content once — SwiftUI re-renders via @EnvironmentObject.
        let panel = DetailPanel().environmentObject(model)
        let host = NSHostingController(rootView: panel)
        // .preferredContentSize tells the host to publish its intrinsic
        // SwiftUI content size via `preferredContentSize`. We KVO on it and
        // mirror to popover.contentSize so the fixed-layout mode resizes the
        // popover to fit the actual content (no clip, no scrollbar).
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 340, height: 720)

        // Track host's intrinsic size → popover.contentSize. Clamp height to
        // available screen so a tall fixed-mode layout never gets its top
        // clipped by the menu bar / screen edge.
        let sizeObs = host.observe(\.preferredContentSize, options: [.new]) { [weak self] hc, _ in
            guard let self else { return }
            let s = hc.preferredContentSize
            guard s.width > 0, s.height > 0 else { return }
            DispatchQueue.main.async {
                let width: CGFloat = 340
                let visible = NSScreen.main?.visibleFrame.height ?? 800
                let maxH = max(400, visible - 40)
                self.popover.contentSize = NSSize(width: width, height: min(s.height, maxH))
            }
        }
        self.observers = [sizeObs]

        // Re-render menu bar label on AppModel changes (popover updates itself).
        let cancel = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
        self.modelCancellable = cancel
    }

    private func updateButton() {
        guard let button = statusItem.button, let model else { return }
        let metric = model.primaryMetric
        let valueText: String
        switch metric {
        case .sessionPercent:
            valueText = model.sessionBlock.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—"
        case .weeklyPercent:
            valueText = model.weekly.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—"
        case .todayCost:
            valueText = String(format: "$%.2f", model.todayTotals.costUSD)
        case .cacheHit:
            valueText = "\(Int((model.cacheHitRate * 100).rounded()))%"
        }
        let frac = model.sessionBlock?.usedFraction ?? 0
        let bucket = frac >= 0.9 ? 2 : (frac >= 0.7 ? 1 : 0)

        // Drop redraw when nothing the user can see changed.
        let sig = "\(metric.rawValue)|\(valueText)|\(bucket)"
        if sig == lastButtonSig { return }
        lastButtonSig = sig

        let symbolName = "circle.fill"
        let tint: NSColor
        switch bucket {
        case 2: tint = .systemRed
        case 1: tint = .systemYellow
        default: tint = .systemGreen
        }

        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        let dotImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        dotImage?.isTemplate = false
        // Render the dot with tint by drawing into a fresh image.
        let tinted = dotImage.map { src -> NSImage in
            let img = NSImage(size: src.size)
            img.lockFocus()
            tint.set()
            let rect = NSRect(origin: .zero, size: src.size)
            src.draw(in: rect)
            rect.fill(using: .sourceAtop)
            img.unlockFocus()
            return img
        }
        button.image = tinted
        button.imagePosition = .imageLeading
        button.title = " \(valueText)"
    }

    @objc private func handleStatusClick(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: button)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let model else { return }
        let menu = NSMenu()

        let exportItem = NSMenuItem(
            title: model.t(.exportMenuItem),
            action: #selector(handleExportMenu),
            keyEquivalent: "e"
        )
        exportItem.target = self
        menu.addItem(exportItem)

        let isPaused = AppDelegate.shared?.coordinator?.pauseController.isPaused ?? false
        let pauseTitle = isPaused ? model.t(.menuResumeIngest) : model.t(.menuPauseIngest)
        let pauseItem = NSMenuItem(
            title: pauseTitle,
            action: #selector(handlePauseMenu),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: model.t(.kbQuit),
            action: #selector(handleQuitMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Popping the menu via statusItem.menu would steal the primary click
        // action permanently. Showing it transiently with popUp keeps
        // left-click → popover semantics intact.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func handleExportMenu() {
        AppDelegate.shared?.coordinator?.openExportSheet()
    }

    @objc private func handlePauseMenu() {
        AppDelegate.shared?.coordinator?.pauseController.toggle()
    }

    @objc private func handleQuitMenu() {
        NSApp.terminate(nil)
    }
}
