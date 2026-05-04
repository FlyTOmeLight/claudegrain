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

    func attach(model: AppModel) {
        self.model = model
        statusItem.length = NSStatusItem.variableLength

        if let button = statusItem.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.title = "claudegrain"
            updateButton()
        }

        // Wire popover content once — SwiftUI re-renders via @EnvironmentObject.
        let panel = DetailPanel().environmentObject(model)
        popover.contentViewController = NSHostingController(rootView: panel)
        popover.contentSize = NSSize(width: 340, height: 720)

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
        let symbolName: String
        let tint: NSColor
        if frac >= 0.9 { symbolName = "circle.fill"; tint = .systemRed }
        else if frac >= 0.7 { symbolName = "circle.fill"; tint = .systemYellow }
        else { symbolName = "circle.fill"; tint = .systemGreen }

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

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
