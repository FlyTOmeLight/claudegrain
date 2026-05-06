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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PaperEdgeShape(side: .top)
                .fill(theme.paperBg)
                .frame(height: 8)
            content
                .background(scanlineOverlay)
            PaperEdgeShape(side: .bottom)
                .fill(theme.paperBg)
                .frame(height: 8)
        }
        .frame(width: 340)
    }

    @ViewBuilder
    private var content: some View {
        switch model.layoutMode {
        case .scroll:
            // Scroll mode: lock 720pt so popover stays at fixed height and
            // overflow gets a scrollbar. NSHostingController publishes this
            // height via preferredContentSize.
            ScrollView(.vertical, showsIndicators: false) {
                ReceiptBody()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(height: 720)
        case .fixed:
            // Fixed mode: intrinsic size only. NSHostingController.sizingOptions
            // = .preferredContentSize publishes the natural content height; the
            // status item controller mirrors it to the popover.
            ReceiptBody()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            Text(model.t(.versionTagline))
                .font(.cgMonoXSmall)
                .tracking(3.2)
                .foregroundStyle(theme.ink.opacity(0.55))

            HeaderStrip()

            if model.pauseController.isPaused {
                PauseBanner()
            }

            DoubleDivider()

            HeroSpend(yesterdayCost: 7.5)

            // Forecast badge — kept in both modes; tiny, hero-adjacent.
            if model.forecastBlock?.basis != .insufficient {
                ForecastBadge(forecast: model.forecastBlock, labelKey: .forecastBlockHits)
                    .padding(.top, 2)
            }

            DashedDivider()

            // WeekDelta — fixed mode skips to fit HD screens (parity with SubtotalsBlock).
            if model.layoutMode == .scroll {
                WeekDeltaRow(delta: model.weekDelta)
                DashedDivider()
            }

            SectionHeader(label: model.t(.sectionUsageLimits))
            VStack(spacing: 2) {
                VitalRow(
                    label: model.t(.vitalSession),
                    percent: model.sessionBlock?.usedFraction ?? 0,
                    resetText: model.sessionBlock?.resetCountdown ?? "—",
                    isWarn: (model.sessionBlock?.usedFraction ?? 0) >= 0.7
                )
                VitalRow(
                    label: model.t(.vitalWeekly),
                    percent: model.weekly?.usedFraction ?? 0,
                    resetText: model.weekly?.resetLabel ?? "—",
                    isWarn: (model.weekly?.usedFraction ?? 0) >= 0.85
                )
                VitalRow(
                    label: model.t(.vitalCache),
                    percent: model.cacheHitRate,
                    resetText: cacheBaselineLabel,
                    isWarn: model.cacheHitRate >= 0.7 && model.cacheHitRate < 0.95
                )
            }

            DashedDivider()

            SectionHeader(label: model.t(.sectionSpend7d))
            WeekLineChart(points: weekPoints, todayValue: model.todayTotals.costUSD)
            WeekDayLabels()

            StarsDivider()

            SectionHeader(label: model.t(.sectionTopCosts))
            TopCostsList()

            // ModelMix — fixed mode skips to fit HD screens.
            if model.layoutMode == .scroll {
                DashedDivider()
                ModelMixRow(mix: model.modelMix)
            }

            DoubleDivider()

            // Fixed mode skips the dense subtotals/cache breakdown so the
            // popover fits an HD screen without clipping. Scroll mode keeps
            // the full receipt.
            if model.layoutMode == .scroll {
                SubtotalsBlock()
                DoubleDivider()
            }

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
        return String(format: model.t(.cacheBaseline), pct)
    }
}

private struct HeaderStrip: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            LiveDot()
            Text(model.t(.statusLive))
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
        case .oauthLive: return model.t(.statusOauth)
        case .jsonlOnly: return model.t(.statusJsonl)
        case .cliFallback: return model.t(.statusCli)
        case .offline: return model.t(.statusOffline)
        case .unknown: return model.t(.statusBoot)
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
            row(
                String(format: model.t(.subtotalShown), model.topRepos.count),
                String(format: "$%.2f", topReposSum)
            )
            row(model.t(.subtotalOther), "$0.00")
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
                Text(model.t(.subtotalCacheBreakdown))
                    .font(.cgMonoSmall)
                    .tracking(1.6)
                    .foregroundStyle(theme.ink.opacity(0.7))
                Spacer()
                Text("−$\(String(format: "%.2f", estimatedCacheSavings))")
                    .font(.cgMonoMed.weight(.bold))
                    .foregroundStyle(theme.inkBold)
                    .neonGlow(color: theme.inkBold, radius: 1.5, opacity: theme.glowEnabled ? 0.4 : 0)
            }
            cacheRow(model.t(.cacheReadHits), "@$3.20/M", "−$3.39")
            cacheRow(model.t(.cacheWriteCached), "@$15/M ✗", "−$0.57")
            cacheRow(model.t(.cacheHitRateBoost), "+12pp", "−$0.24")
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
            Text(model.t(.netToday))
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
    @State private var spinAngle: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                kbd("F2", model.t(.kbCfg)) { openSettingsWindow() }
                refreshButton
                kbd("E", model.t(.kbExport)) { model.exportHandler?() }
                kbd("P", model.t(.kbPause)) { model.pauseHandler?() }
                kbd("F10", model.t(.kbQuit)) { NSApp.terminate(nil) }
            }
            .padding(.top, 6)

            Text("───── \(String(format: model.t(.footerEndEvents), eventCount)) ─────")
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
        // `\.openSettings` is the SwiftUI-native path but the CI Xcode 15 SDK
        // is missing the symbol (see commit 1fd1f27). Selector dispatch hits
        // the same AppKit hook on macOS 13+. After firing, walk the windows
        // and bring any settings window forward — selector alone fails to
        // re-key the window on subsequent taps when the app is LSUIElement.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for w in NSApp.windows {
                let id = w.identifier?.rawValue.lowercased() ?? ""
                let title = w.title.lowercased()
                if id.contains("settings") || title.contains("settings") || title.contains("设置") {
                    w.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button(action: triggerRefresh) {
            HStack(spacing: 4) {
                Text("F5")
                    .font(.cgMonoSmall.weight(.bold))
                    .foregroundStyle(theme.paperBg)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.inkBold)
                    .cornerRadius(2)
                HStack(spacing: 2) {
                    Text(model.t(.kbRefresh))
                        .font(.cgMonoSmall)
                        .tracking(0.6)
                    Text("↻")
                        .font(.cgMonoSmall.weight(.bold))
                        .rotationEffect(.degrees(spinAngle))
                        .opacity(model.isRefreshing ? 1 : 0.55)
                }
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
        .onChange(of: model.isRefreshing) { _, isRefreshing in
            if isRefreshing {
                spinAngle = 0
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { spinAngle = 0 }
            }
        }
    }

    private func triggerRefresh() {
        guard let handler = model.refreshHandler, !model.isRefreshing else { return }
        model.isRefreshing = true
        Task { @MainActor in
            // Floor the spinner duration so the user perceives a real refresh
            // pulse even when the underlying snapshot returns instantly.
            let start = Date()
            await handler()
            let remainder = 0.6 - Date().timeIntervalSince(start)
            if remainder > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainder * 1_000_000_000))
            }
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
            generalTab.tabItem { Label(model.t(.settingsGeneral), systemImage: "gear") }
            notificationsTab.tabItem { Label(model.t(.settingsNotifications), systemImage: "bell") }
            BudgetsTab(budgets: model.budgets, recentRepos: model.topRepos.map { $0.id })
                .tabItem { Label(model.t(.settingsBudgets), systemImage: "dollarsign.circle") }
            QuietHoursTab()
                .tabItem { Label(model.t(.settingsQuietHours), systemImage: "moon.zzz") }
            aboutTab.tabItem { Label(model.t(.settingsAbout), systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
        .padding(.top, 8)
    }

    private var generalTab: some View {
        Form {
            Picker(model.t(.sgMenuBarShows), selection: Binding(
                get: { model.primaryMetric },
                set: { model.primaryMetric = $0 }
            )) {
                Text(model.t(.sgSessionPct)).tag(PrimaryMetric.sessionPercent)
                Text(model.t(.sgWeeklyPct)).tag(PrimaryMetric.weeklyPercent)
                Text(model.t(.sgTodayCost)).tag(PrimaryMetric.todayCost)
                Text(model.t(.sgCacheHit)).tag(PrimaryMetric.cacheHit)
            }
            Picker(model.t(.sgLanguage), selection: Binding(
                get: { model.language },
                set: { model.language = $0 }
            )) {
                Text(model.t(.sgLanguageEnglish)).tag(AppLanguage.english)
                Text(model.t(.sgLanguageChinese)).tag(AppLanguage.chinese)
            }
            Picker(model.t(.sgLayout), selection: Binding(
                get: { model.layoutMode },
                set: { model.layoutMode = $0 }
            )) {
                Text(model.t(.sgLayoutScroll)).tag(LayoutMode.scroll)
                Text(model.t(.sgLayoutFixed)).tag(LayoutMode.fixed)
            }
            Toggle(model.t(.sgOpenAtLogin), isOn: Binding(
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
            Section(model.t(.snTriggers)) {
                Toggle(model.t(.snThreshold), isOn: prefBinding(\.notifyThreshold))
                Toggle(model.t(.snBurnRate), isOn: prefBinding(\.notifyBurnRate))
                Toggle(model.t(.snBlockReset), isOn: prefBinding(\.notifyBlockReset))
                Toggle(model.t(.snRepoOverspend), isOn: prefBinding(\.notifyRepoOverspend))
            }
            Section(model.t(.snSound)) {
                Picker(model.t(.snSound), selection: soundBinding) {
                    Text(model.t(.snSoundDefault)).tag(SoundChoice.app)
                    Text(model.t(.snSoundGlass)).tag(SoundChoice.system(name: "Glass"))
                    Text(model.t(.snSoundPing)).tag(SoundChoice.system(name: "Ping"))
                }
                .pickerStyle(.menu)
                Button(model.t(.snImportSound)) { importSound() }
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
            Text(model.t(.saTagline))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(model.t(.saMit))
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button(model.t(.saViewSource)) {
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

private struct PauseBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text("⏸ \(model.t(.pauseBannerTitle))")
                .font(.cgMonoSmall.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(theme.inkBold)
            Spacer()
            Button(model.t(.pauseBannerResume)) {
                model.pauseHandler?()
            }
            .buttonStyle(.plain)
            .font(.cgMonoSmall.weight(.bold))
            .foregroundStyle(theme.paperBg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.inkBold)
            .cornerRadius(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.inkBold.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(theme.inkBold.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 4)
    }
}
