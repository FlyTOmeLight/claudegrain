import SwiftUI
import ClaudegrainCore

@main
struct ClaudegrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    let model = AppModel()
    let statusController = StatusItemController()
    private(set) var coordinator: AppCoordinator?
    private var previewWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerAll()

        if ProcessInfo.processInfo.arguments.contains("--preview") {
            populateMockData()
            openPreviewWindow()
            return
        }

        statusController.attach(model: model)
        Task { await boot() }
    }

    private func boot() async {
        do {
            let c = try AppCoordinator(model: model)
            coordinator = c
            model.refreshHandler = { [weak c] in
                await c?.refreshNow()
            }
            model.exportHandler = { [weak c] in
                c?.openExportSheet()
            }
            await c.start()
        } catch {
            model.dataSourceStatus = .offline
        }
    }

    private func populateMockData() {
        model.sessionBlock = SessionBlockSnapshot(
            startedAt: Date().addingTimeInterval(-3600),
            resetsAt: Date().addingTimeInterval(4 * 3600 + 29 * 60),
            usedFraction: 0.55,
            totalTokens: 320_000
        )
        model.weekly = WeeklyUsageSnapshot(
            usedFraction: 0.32,
            resetsAt: Date().addingTimeInterval(5 * 86400 + 11 * 3600)
        )
        model.todayTotals = DailyTotals(
            costUSD: 8.42,
            totalTokens: 1_240_000,
            byModel: [
                "claude-opus-4-7": 540_000,
                "claude-sonnet-4-6": 620_000,
                "claude-haiku-4-5": 80_000,
            ]
        )
        model.topRepos = [
            .init(repo: "tools/menu-hub", fullCwd: "/Users/me/tools/menu-hub", costUSD: 3.20, totalTokens: 420_000, spend7d: [1.1, 1.3, 0.9, 1.8, 2.0, 2.4, 3.20]),
            .init(repo: "new/prism-endpoint", fullCwd: "/Users/me/new/prism-endpoint", costUSD: 2.10, totalTokens: 310_000, spend7d: [2.6, 2.4, 2.5, 2.3, 2.2, 2.0, 2.10]),
            .init(repo: "new/tendering-service", fullCwd: "/Users/me/new/tendering-service", costUSD: 1.60, totalTokens: 240_000, spend7d: [2.0, 2.2, 2.1, 1.9, 1.8, 1.7, 1.60]),
            .init(repo: "tools/feishu-pdf", fullCwd: "/Users/me/tools/feishu-pdf", costUSD: 0.90, totalTokens: 130_000, spend7d: [0.7, 0.6, 0.7, 0.8, 0.7, 0.85, 0.90]),
            .init(repo: "Users/moonlight", fullCwd: "/Users/moonlight", costUSD: 0.62, totalTokens: 90_000, spend7d: [1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.62]),
        ]
        model.cacheHitRate = 0.87
        model.dataSourceStatus = .oauthLive
        model.weekSpend = [4.2, 5.8, 3.2, 7.1, 6.4, 5.2, 8.42]
    }

    private func openPreviewWindow() {
        let isDark = ProcessInfo.processInfo.environment["CG_PREVIEW_LIGHT"] == nil
        NSApp.setActivationPolicy(.regular)

        let detail = DetailPanel().environmentObject(model)
            .preferredColorScheme(isDark ? .dark : .light)
            .frame(width: 340, height: 720)

        let host = NSHostingController(rootView: detail)
        let win = NSWindow(contentViewController: host)
        win.title = "claudegrain · V18 preview"
        win.styleMask = [.titled, .closable]
        win.center()
        win.makeKeyAndOrderFront(nil)
        previewWindow = win
        NSApp.activate(ignoringOtherApps: true)
    }
}
