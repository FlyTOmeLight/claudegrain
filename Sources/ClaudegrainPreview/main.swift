// Renders the claudegrain detail panel + Settings tabs in a normal window so we
// can take a screenshot of the UI without fighting the menu-bar notch.
import AppKit
import SwiftUI
import Combine
import ClaudegrainCore

@MainActor
final class PreviewModel: ObservableObject {
    @Published var sessionBlock: SessionBlockSnapshot? = SessionBlockSnapshot(
        startedAt: Date().addingTimeInterval(-3600),
        resetsAt: Date().addingTimeInterval(4 * 3600 + 30 * 60),
        usedFraction: 0.55,
        totalTokens: 320_000
    )
    @Published var weekly: WeeklyUsageSnapshot? = WeeklyUsageSnapshot(
        usedFraction: 0.32,
        resetsAt: Date().addingTimeInterval(7 * 86400)
    )
    @Published var todayTotals: DailyTotals = DailyTotals(
        costUSD: 8.42,
        totalTokens: 1_240_000,
        byModel: [
            "claude-opus-4-7": 540_000,
            "claude-sonnet-4-6": 620_000,
            "claude-haiku-4-5": 80_000,
        ]
    )
    @Published var topRepos: [RepoBreakdown] = [
        .init(repo: "tools/menu-hub", costUSD: 3.20, totalTokens: 420_000),
        .init(repo: "new/prism-endpoint", costUSD: 2.10, totalTokens: 310_000),
        .init(repo: "new/tendering-service", costUSD: 1.60, totalTokens: 240_000),
        .init(repo: "tools/feishu-pdf", costUSD: 0.90, totalTokens: 130_000),
        .init(repo: "Users/moonlight", costUSD: 0.62, totalTokens: 90_000),
    ]
    @Published var topTools: [ToolBreakdown] = [
        .init(toolName: "mcp__exa__search", mcpServer: "exa", costUSD: 2.40, totalTokens: 380_000),
        .init(toolName: "Bash", mcpServer: nil, costUSD: 1.80, totalTokens: 290_000),
        .init(toolName: "Edit", mcpServer: nil, costUSD: 1.50, totalTokens: 220_000),
        .init(toolName: "Read", mcpServer: nil, costUSD: 1.10, totalTokens: 170_000),
        .init(toolName: "Agent", mcpServer: nil, costUSD: 0.90, totalTokens: 130_000),
    ]
    @Published var cacheHitRate: Double = 0.87
}

struct PreviewRoot: View {
    @StateObject var model = PreviewModel()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Detail Popover").font(.caption).foregroundStyle(.secondary)
                MockDetailPanel(model: model)
                    .frame(width: 340, height: 480)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Menu Bar Label").font(.caption).foregroundStyle(.secondary)
                MockMenuBarLabel(model: model)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                Text("Settings").font(.caption).padding(.top, 12).foregroundStyle(.secondary)
                MockSettings(model: model)
                    .frame(width: 460, height: 360)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .frame(width: 880, height: 540)
    }
}

struct MockMenuBarLabel: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("\(Int(((model.sessionBlock?.usedFraction ?? 0) * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

struct MockDetailPanel: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gaugeRow
                todayCard
                breakdownCard(title: "Repos", rows: model.topRepos.map { ($0.repo, $0.costUSD) })
                breakdownCard(title: "Tools", rows: model.topTools.map { ($0.toolName, $0.costUSD) })
            }.padding(16)
        }
        .overlay(alignment: .bottom) {
            HStack {
                Image(systemName: "gearshape").imageScale(.small)
                Spacer()
                Image(systemName: "arrow.clockwise").imageScale(.small)
                Text("Quit").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    private var gaugeRow: some View {
        HStack(spacing: 12) {
            ring(label: "Session", percent: model.sessionBlock?.usedFraction, sub: model.sessionBlock?.resetCountdown)
            ring(label: "Weekly", percent: model.weekly?.usedFraction, sub: model.weekly?.resetLabel)
            ring(label: "Cache", percent: model.cacheHitRate, sub: nil)
            ring(label: "Today $", percent: nil, sub: String(format: "$%.2f", model.todayTotals.costUSD))
        }
    }

    private func ring(label: String, percent: Double?, sub: String?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.2), lineWidth: 4)
                if let percent {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(percent, 0), 1)))
                        .stroke(ringColor(percent), style: .init(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(percent.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(width: 56, height: 56)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if let sub { Text(sub).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
    }

    private func ringColor(_ p: Double) -> Color {
        if p >= 0.9 { return .red }
        if p >= 0.7 { return .yellow }
        return .green
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "$%.2f", model.todayTotals.costUSD))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Text("\(model.todayTotals.totalTokens / 1000)k tok")
                    .font(.caption).foregroundStyle(.secondary)
            }
            stackedBar
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var stackedBar: some View {
        let total = max(model.todayTotals.byModel.values.reduce(0, +), 1)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(model.todayTotals.byModel.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                    color(for: entry.key)
                        .frame(width: geo.size.width * CGFloat(entry.value) / CGFloat(total))
                }
            }
        }.frame(height: 6).clipShape(Capsule())
    }

    private func color(for m: String) -> Color {
        if m.contains("opus") { return .blue }
        if m.contains("sonnet") { return .green }
        return .gray
    }

    private func breakdownCard(title: String, rows: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            let maxV = rows.map(\.1).max() ?? 1
            ForEach(rows.prefix(5), id: \.0) { row in
                HStack {
                    Text(row.0).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "$%.2f", row.1)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: row.1 / maxV).progressViewStyle(.linear)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MockSettings: View {
    @ObservedObject var model: PreviewModel
    @State private var notifyThreshold = true
    @State private var notifyBurnRate = false
    @State private var notifyBlockReset = false
    @State private var loginItem = false
    @State private var primary = "Session %"

    var body: some View {
        TabView {
            Form {
                Picker("Menu bar shows", selection: $primary) {
                    Text("Session %").tag("Session %")
                    Text("Weekly %").tag("Weekly %")
                    Text("Today $").tag("Today $")
                    Text("Cache hit %").tag("Cache hit %")
                }
                Toggle("Open at login", isOn: $loginItem)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("General", systemImage: "gear") }

            Form {
                Section("Triggers") {
                    Toggle("Threshold alerts (session 70/90% · weekly 85%)", isOn: $notifyThreshold)
                    Toggle("Burn-rate spikes (over P90 × 2)", isOn: $notifyBurnRate)
                    Toggle("Block reset (10 min before)", isOn: $notifyBlockReset)
                }
                Section("Sound") {
                    Picker("Sound", selection: .constant("claudegrain default")) {
                        Text("claudegrain default").tag("claudegrain default")
                        Text("Glass (system)").tag("Glass")
                        Text("Ping (system)").tag("Ping")
                    }
                    Button("Import sound file…") {}
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("Notifications", systemImage: "bell") }

            VStack(spacing: 8) {
                Text("claudegrain").font(.title2.weight(.semibold))
                Text("v0.1.0").font(.caption).foregroundStyle(.secondary)
                Text("Granular Claude Code usage in your menu bar.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("MIT licensed · open source").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("View source on GitHub") {}
            }.padding(24)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

@MainActor
final class AppDel: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PreviewRoot()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "claudegrain UI preview"
        win.styleMask = [.titled, .closable]
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDel()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

MainActor.assumeIsolated { runApp() }
