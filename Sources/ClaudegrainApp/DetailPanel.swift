import SwiftUI
import ClaudegrainCore

struct DetailPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme: Theme = colorScheme == .dark ? .phosphor : .thermal
        ReceiptScroll(theme: theme)
            .environment(\.theme, theme)
            .environmentObject(model)
            .background(theme.paperBg)
    }
}

private struct ReceiptScroll: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            PaperEdgeShape(side: .top)
                .fill(theme.paperBg)
                .frame(height: 8)
            ScrollView(.vertical, showsIndicators: false) {
                ReceiptBody()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .background(scanlineOverlay)
            PaperEdgeShape(side: .bottom)
                .fill(theme.paperBg)
                .frame(height: 8)
        }
        .frame(width: 340)
    }

    @ViewBuilder
    private var scanlineOverlay: some View {
        if theme.glowEnabled {
            Color.clear
                .overlay(
                    Rectangle()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: theme.inkBold.opacity(theme.scanlineOpacity), location: 0),
                                .init(color: .clear, location: 0.33),
                                .init(color: theme.inkBold.opacity(theme.scanlineOpacity), location: 0.66),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
        }
    }
}

private struct ReceiptBody: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            StencilTitleView()
            Text("v 0.1 · usage · live")
                .font(.cgMonoXSmall)
                .tracking(3.2)
                .foregroundStyle(theme.ink.opacity(0.55))

            HeaderStrip()

            DoubleDivider()

            HeroSpend(totals: model.todayTotals, yesterdayCost: 7.5)

            DashedDivider()

            SectionHeader(label: "USAGE LIMITS")
            VStack(spacing: 2) {
                VitalRow(
                    label: "SESSION",
                    percent: model.sessionBlock?.usedFraction ?? 0,
                    resetText: model.sessionBlock?.resetCountdown ?? "—",
                    isWarn: (model.sessionBlock?.usedFraction ?? 0) >= 0.7
                )
                VitalRow(
                    label: "WEEKLY",
                    percent: model.weekly?.usedFraction ?? 0,
                    resetText: model.weekly?.resetLabel ?? "—",
                    isWarn: (model.weekly?.usedFraction ?? 0) >= 0.85
                )
                VitalRow(
                    label: "CACHE",
                    percent: model.cacheHitRate,
                    resetText: cacheBaselineLabel,
                    isWarn: model.cacheHitRate >= 0.7 && model.cacheHitRate < 0.95
                )
            }

            DashedDivider()

            SectionHeader(label: "7d SPEND · LINE")
            WeekLineChart(points: weekPoints, todayValue: model.todayTotals.costUSD)
            WeekDayLabels()

            StarsDivider()

            SectionHeader(label: "TOP COSTS · 7d trend")
            TopCostsList()

            DoubleDivider()

            SubtotalsBlock()

            DoubleDivider()

            NetTotalRow()

            FooterBlock()
        }
    }

    private var weekPoints: [Double] {
        guard model.weekSpend.count == 7 else {
            // Cold-start fallback before first ingest snapshot lands.
            let today = max(model.todayTotals.costUSD, 0.5)
            return [today * 0.5, today * 0.7, today * 0.4, today * 0.85, today * 0.75, today * 0.6, today]
        }
        return model.weekSpend
    }

    private var cacheBaselineLabel: String {
        let pct = Int((model.cacheHitRate * 100).rounded())
        return "↑ \(pct)% hit · vs P50"
    }
}

private struct HeaderStrip: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            LiveDot()
            Text("LIVE")
                .font(.cgMonoSmall)
                .tracking(1.8)
                .foregroundStyle(theme.inkBold)
                .bold()
            Text("·")
                .font(.cgMonoSmall)
                .foregroundStyle(theme.inkBold.opacity(0.6))
            Text(statusLabel)
                .font(.cgMonoSmall)
                .tracking(1.8)
                .foregroundStyle(theme.inkBold.opacity(0.7))
            Spacer()
            Text(timeString)
                .font(.cgMonoSmall)
                .tracking(1)
                .foregroundStyle(theme.inkBold.opacity(0.7))
        }
    }

    private var statusLabel: String {
        switch model.dataSourceStatus {
        case .oauthLive: return "OAUTH ✓"
        case .jsonlOnly: return "JSONL"
        case .cliFallback: return "CLI"
        case .offline: return "OFFLINE"
        case .unknown: return "BOOT"
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

private struct TopCostsList: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.topRepos.prefix(5).enumerated()), id: \.offset) { idx, repo in
                CostRow(
                    rank: idx + 1,
                    type: "[R]",
                    name: repo.repo,
                    costUSD: repo.costUSD,
                    deltaPct: deltaPct(for: repo),
                    sparkPoints: sparkPoints(for: repo)
                )
            }
        }
    }

    /// Real 7d series from `RepoBreakdown.spend7d`. Falls back to ramp until the
    /// first snapshot lands.
    private func sparkPoints(for repo: RepoBreakdown) -> [Double] {
        if !repo.spend7d.isEmpty { return repo.spend7d }
        let h = abs(repo.repo.hashValue % 100)
        let base = Double(h) / 100.0
        return (0..<7).map { i in 0.3 + base * 0.7 + sin(Double(i) + base * 6) * 0.15 }
    }

    /// Today vs prior 6-day average (most useful direction signal in a 7-point series).
    private func deltaPct(for repo: RepoBreakdown) -> Int? {
        guard repo.spend7d.count == 7 else { return nil }
        let today = repo.spend7d.last ?? 0
        let priorAvg = repo.spend7d.dropLast().reduce(0, +) / Double(max(repo.spend7d.count - 1, 1))
        guard priorAvg > 0.01 else { return nil }
        return Int(((today - priorAvg) / priorAvg * 100).rounded())
    }
}

private struct CostRow: View {
    let rank: Int
    let type: String
    let name: String
    let costUSD: Double
    let deltaPct: Int?
    let sparkPoints: [Double]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("\(rank)")
                .font(.cgMonoSmall)
                .foregroundStyle(theme.ink.opacity(0.5))
                .frame(width: 12, alignment: .leading)
            Text(type)
                .font(.cgMonoSmall.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(theme.ink.opacity(0.6))
                .frame(width: 22)
            Text(shorten(name))
                .font(.custom("JetBrains Mono", size: 10.5))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: true, vertical: false)
            DotLeader()
            MiniSparkline(points: sparkPoints)
            if let pct = deltaPct {
                Text("\(pct >= 0 ? "↑" : "↓")\(abs(pct))")
                    .font(.cgMonoSmall.weight(.bold))
                    .foregroundStyle(pct >= 0 ? theme.crit : theme.inkBold)
                    .frame(width: 28, alignment: .trailing)
            } else {
                Spacer().frame(width: 28)
            }
            Text(String(format: "$%.2f", costUSD))
                .font(.custom("JetBrains Mono", size: 11).weight(.bold))
                .foregroundStyle(theme.ink)
                .frame(width: 44, alignment: .trailing)
                .fixedSize()
        }
    }

    private func shorten(_ path: String) -> String {
        let parts = path.split(separator: "/").suffix(2)
        return parts.joined(separator: "/")
    }
}

/// Renders ".  .  .  .  ." filling available width.
struct DotLeader: View {
    @Environment(\.theme) private var theme
    var body: some View {
        GeometryReader { geo in
            let count = max(Int(geo.size.width / 4), 0)
            Text(String(repeating: " .", count: count))
                .font(.cgMonoSmall)
                .foregroundStyle(theme.ink.opacity(0.32))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 11)
        .frame(maxWidth: .infinity)
    }
}

private struct SubtotalsBlock: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 1) {
            row("SHOWN · TOP \(model.topRepos.count) REPOS", String(format: "$%.2f", topReposSum))
            row("OTHER REPOS", "$0.00")
            cacheBlock
        }
    }

    private var topReposSum: Double { model.topRepos.prefix(5).map(\.costUSD).reduce(0, +) }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.cgMonoSmall)
                .tracking(1.6)
                .foregroundStyle(theme.ink.opacity(0.6))
                .fixedSize()
            DotLeader()
            Text(value)
                .font(.cgMonoMed)
                .foregroundStyle(theme.ink.opacity(0.85))
                .fixedSize()
        }
    }

    private var cacheBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 4)
            HStack {
                Text("CACHE SAVINGS BREAKDOWN")
                    .font(.cgMonoSmall)
                    .tracking(1.6)
                    .foregroundStyle(theme.ink.opacity(0.7))
                Spacer()
                Text("−$\(String(format: "%.2f", estimatedCacheSavings))")
                    .font(.cgMonoMed.weight(.bold))
                    .foregroundStyle(theme.inkBold)
                    .neonGlow(color: theme.inkBold, radius: 1.5, opacity: theme.glowEnabled ? 0.4 : 0)
            }
            cacheRow("Read · cache hits", "@$3.20/M", "−$3.39")
            cacheRow("Write · cached", "@$15/M ✗", "−$0.57")
            cacheRow("Hit rate boost", "+12pp", "−$0.24")
        }
    }

    private func cacheRow(_ desc: String, _ tokens: String, _ save: String) -> some View {
        HStack(spacing: 6) {
            Text("▶")
                .font(.cgMonoSmall)
                .foregroundStyle(theme.ink.opacity(0.5))
                .frame(width: 12)
            Text(desc)
                .font(.custom("JetBrains Mono", size: 9.5))
                .foregroundStyle(theme.ink.opacity(0.75))
            Spacer()
            Text(tokens)
                .font(.cgMonoSmall)
                .foregroundStyle(theme.ink.opacity(0.6))
            Text(save)
                .font(.custom("JetBrains Mono", size: 9.5).weight(.bold))
                .foregroundStyle(theme.inkBold)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private var estimatedCacheSavings: Double {
        // Rough estimate: cache hits @$3.20/M + small write/boost terms.
        let cacheReadTokens = Double(model.todayTotals.totalTokens) * model.cacheHitRate
        return cacheReadTokens * 3.20 / 1_000_000 + 0.81
    }
}

private struct NetTotalRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text("NET TODAY")
                .font(.cgMono.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(theme.ink)
            Rectangle()
                .fill(theme.ink.opacity(0.3))
                .frame(height: 1)
                .padding(.bottom, 2)
            Text(String(format: "$%.2f", model.todayTotals.costUSD))
                .font(.custom("JetBrains Mono", size: 13).weight(.bold))
                .foregroundStyle(theme.inkBold)
                .neonGlow(color: theme.inkBold, radius: 3, opacity: theme.glowEnabled ? 0.6 : 0)
        }
    }
}

private struct FooterBlock: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                kbd("F2", "cfg") { openSettingsWindow() }
                kbd("F5", "refresh") { triggerRefresh() }
                kbd("F10", "quit") { NSApp.terminate(nil) }
            }
            .padding(.top, 6)

            Text("───── END · \(eventCount) EVENTS ─────")
                .font(.cgMonoXSmall)
                .tracking(1.6)
                .foregroundStyle(theme.ink.opacity(0.55))

            Text("▌▌█ ▌█▌▌ ▌█ ▌▌█ █▌▌█▌ ▌█▌ ▌▌█ █▌")
                .font(.custom("JetBrains Mono", size: 12))
                .foregroundStyle(theme.ink.opacity(0.7))

            HStack {
                Text("claudegrain.dev")
                Spacer()
                Text("● MIT 2026")
                Spacer()
                Text("0xCG-V0.1")
            }
            .font(.cgMonoXSmall)
            .tracking(0.6)
            .foregroundStyle(theme.ink.opacity(0.5))
        }
    }

    private var eventCount: String {
        // Placeholder formatter; wire to EventsDatabase row count later.
        "—"
    }

    private func openSettingsWindow() {
        // LSUIElement = true ⇒ default policy is .accessory; activate explicitly
        // so the Settings scene window comes forward and accepts focus.
        NSApp.activate(ignoringOtherApps: true)
        // `\.openSettings` exists in newer SDKs but the CI Xcode 15 SDK is
        // missing the symbol. Selector dispatch hits the same AppKit hook
        // that SwiftUI's accessor uses internally and works on macOS 13+.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func triggerRefresh() {
        guard let handler = model.refreshHandler, !model.isRefreshing else { return }
        model.isRefreshing = true
        Task { @MainActor in
            await handler()
            model.isRefreshing = false
        }
    }

    private func kbd(_ key: String, _ desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.cgMonoSmall.weight(.bold))
                    .foregroundStyle(theme.paperBg)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.inkBold)
                    .cornerRadius(2)
                Text(desc)
                    .font(.cgMonoSmall)
                    .tracking(0.6)
                    .foregroundStyle(theme.inkBold)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.inkBold.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(theme.inkBold.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(3)
            .neonGlow(color: theme.inkBold, radius: 3, opacity: theme.glowEnabled ? 0.18 : 0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings (kept structurally similar; theme-aware)

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 360)
        .padding(.top, 8)
    }

    private var generalTab: some View {
        Form {
            Picker("Menu bar shows", selection: Binding(
                get: { model.primaryMetric },
                set: { model.primaryMetric = $0 }
            )) {
                Text("Session %").tag(PrimaryMetric.sessionPercent)
                Text("Weekly %").tag(PrimaryMetric.weeklyPercent)
                Text("Today $").tag(PrimaryMetric.todayCost)
                Text("Cache hit %").tag(PrimaryMetric.cacheHit)
            }
            Toggle("Open at login", isOn: Binding(
                get: { model.loginItem.isEnabled },
                set: { model.loginItem.setEnabled($0) }
            ))
            if let err = model.loginItem.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var notificationsTab: some View {
        Form {
            Section("Triggers") {
                Toggle("Threshold alerts (session 70/90% · weekly 85%)",
                       isOn: prefBinding(\.notifyThreshold))
                Toggle("Burn-rate spikes (over P90 × 2)",
                       isOn: prefBinding(\.notifyBurnRate))
                Toggle("Block reset (10 min before)",
                       isOn: prefBinding(\.notifyBlockReset))
                Toggle("Per-repo overspend",
                       isOn: prefBinding(\.notifyRepoOverspend))
            }
            Section("Sound") {
                Picker("Sound", selection: soundBinding) {
                    Text("claudegrain default").tag(SoundChoice.app)
                    Text("Glass (system)").tag(SoundChoice.system(name: "Glass"))
                    Text("Ping (system)").tag(SoundChoice.system(name: "Ping"))
                }
                .pickerStyle(.menu)
                Button("Import sound file…") { importSound() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 8) {
            Text("claudegrain")
                .font(.title2.weight(.semibold))
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Granular Claude Code usage in your menu bar.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("MIT licensed · open source")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("View source on GitHub") {
                if let url = URL(string: "https://github.com/Artzainnn/claudegrain") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(24)
    }

    private func prefBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.preferences[keyPath: keyPath] = $0 }
        )
    }

    private var soundBinding: Binding<SoundChoice> {
        Binding(
            get: { model.preferences.notificationSoundChoice },
            set: { model.preferences.notificationSoundChoice = $0 }
        )
    }

    private func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.preferences.notificationSoundChoice = .imported(path: url.path)
        }
    }
}
