import SwiftUI
import ClaudegrainCore

@main
struct ClaudegrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // App protocol requires a Scene. We host Settings ourselves via
        // `SettingsWindowController` (LSUIElement breaks the stock Settings
        // scene's responder routing), so this is a placeholder that never
        // surfaces — there's no main menu to invoke it from.
        Settings { EmptyView() }
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
        if ProcessInfo.processInfo.arguments.contains("--snapshot") {
            populateMockData()
            renderSnapshot()
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
            model.pauseHandler = { [weak c] in
                c?.pauseController.toggle()
            }
            model.commitmentsHandler = { [weak c] in
                c?.openCommitmentsSheet()
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

        model.topTools = [
            .init(toolName: "Bash", mcpServer: nil, costUSD: 2.40, totalTokens: 380_000),
            .init(toolName: "Edit", mcpServer: nil, costUSD: 1.80, totalTokens: 290_000),
            .init(toolName: "Read", mcpServer: nil, costUSD: 1.50, totalTokens: 220_000),
            .init(toolName: "Write", mcpServer: nil, costUSD: 1.10, totalTokens: 170_000),
            .init(toolName: "ScheduleWakeup", mcpServer: nil, costUSD: 0.62, totalTokens: 90_000),
        ]
        model.modelMix = [
            .opus:   0.43,
            .sonnet: 0.50,
            .haiku:  0.07,
        ]
        model.weekDelta = WeekDelta(
            thisWeekCost: 38.40,
            lastWeekCost: 31.20,
            cacheHitDelta: 0.04
        )
        model.forecastBlock = ForecastResult(
            willHit: false,
            hitAt: nil,
            confidence: .high,
            basis: .ewma
        )
        // 168 (weekday × hour) buckets — realistic-ish weekday workday curve so
        // the heatmap renders something other than empty cells.
        model.hourlyBuckets = (1...7).flatMap { wd -> [HourlyBucket] in
            (0..<24).map { hr in
                let weekday = wd
                let workish = (weekday >= 2 && weekday <= 6) ? 1.0 : 0.35
                let hourCurve: Double = {
                    switch hr {
                    case 9...12: return 1.0
                    case 13...17: return 0.85
                    case 19...22: return 0.55
                    case 0...6: return 0.05
                    default: return 0.25
                    }
                }()
                let intensity = workish * hourCurve
                return HourlyBucket(
                    weekday: weekday,
                    hour: hr,
                    costUSD: intensity * 0.9,
                    tokens: Int(intensity * 110_000),
                    sampleCount: intensity * 4
                )
            }
        }
    }

    /// Headless snapshot — renders DetailPanel offscreen to a PNG and exits.
    /// Bypasses screen-size clipping that breaks fixed-mode captures (content
    /// ~1100pt > visible screen on a 14" MBP).
    ///
    /// Args: --snapshot <out_path>
    /// Env:  CG_PREVIEW_LIGHT=1 → light theme, default dark
    ///       CG_PREVIEW_FIXED=1 → fixed layout mode, default scroll
    private func renderSnapshot() {
        let args = ProcessInfo.processInfo.arguments
        guard let snapIdx = args.firstIndex(of: "--snapshot"),
              snapIdx + 1 < args.count else {
            FileHandle.standardError.write(Data("usage: claudegrain --snapshot <out.png>\n".utf8))
            exit(2)
        }
        let outPath = args[snapIdx + 1]
        let isDark = ProcessInfo.processInfo.environment["CG_PREVIEW_LIGHT"] == nil
        let isFixed = ProcessInfo.processInfo.environment["CG_PREVIEW_FIXED"] != nil

        model.layoutMode = isFixed ? .fixed : .scroll

        let frameHeight: CGFloat = isFixed ? 1300 : 720
        let detail = DetailPanel().environmentObject(model)
            .preferredColorScheme(isDark ? .dark : .light)
            .frame(width: 340, height: frameHeight)

        let host = NSHostingController(rootView: detail)
        host.view.frame = NSRect(x: 0, y: 0, width: 340, height: frameHeight)
        host.view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // SwiftUI/AppKit need a hosting window to resolve the appearance and
        // scale layout properly — but the window never has to surface. An
        // offscreen NSWindow positioned at (-10000, -10000) is invisible
        // even if the user's screen briefly receives focus.
        let stagingWin = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 340, height: frameHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        stagingWin.contentViewController = host
        stagingWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        stagingWin.orderFront(nil)
        host.view.layoutSubtreeIfNeeded()

        // One run-loop spin so SwiftUI commits its first layout pass before we
        // ask AppKit to cache the display.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else {
            FileHandle.standardError.write(Data("snapshot: bitmap rep failed\n".utf8))
            exit(3)
        }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: png encode failed\n".utf8))
            exit(4)
        }
        do {
            try data.write(to: URL(fileURLWithPath: outPath))
            FileHandle.standardOutput.write(Data("wrote \(outPath) (\(data.count) bytes)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("snapshot: write failed: \(error)\n".utf8))
            exit(5)
        }
        exit(0)
    }

    private func openPreviewWindow() {
        let isDark = ProcessInfo.processInfo.environment["CG_PREVIEW_LIGHT"] == nil
        let isFixed = ProcessInfo.processInfo.environment["CG_PREVIEW_FIXED"] != nil
        NSApp.setActivationPolicy(.regular)

        // Force layout mode for the preview run; persists to user defaults but
        // the preview process is short-lived and exits before saving.
        model.layoutMode = isFixed ? .fixed : .scroll

        // Fixed mode renders at intrinsic content height — give the host
        // window enough vertical room (~1100pt for v1.0 with TopTools/heatmap
        // gated off scroll). Scroll mode keeps the original 720pt height.
        let frameHeight: CGFloat = isFixed ? 1300 : 720
        let detail = DetailPanel().environmentObject(model)
            .preferredColorScheme(isDark ? .dark : .light)
            .frame(width: 340, height: frameHeight)

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
