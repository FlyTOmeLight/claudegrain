import SwiftUI
import WidgetKit
import ClaudegrainCore

struct ClaudegrainEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge:  LargeView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}

// MARK: - Small (155×155) — single hero metric

private struct SmallView: View {
    let entry: WidgetEntry

    private var pct: Int {
        Int(((entry.snapshot.sessionBlockPercent ?? 0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HeaderRow(snapshot: entry.snapshot)
            Spacer()
            Text("\(pct)%")
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(L.session(entry.snapshot.language))
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 4)
            if let resetText = resetCountdownText(entry.snapshot) {
                Text(resetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(entry.isStale ? 0.6 : 1)
    }
}

// MARK: - Medium (338×155) — hero + week sparkline

private struct MediumView: View {
    let entry: WidgetEntry

    private var pct: Int {
        Int(((entry.snapshot.sessionBlockPercent ?? 0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderRow(snapshot: entry.snapshot)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(pct)%")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                    Text(L.session(entry.snapshot.language))
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "$%.2f \(L.today(entry.snapshot.language))",
                                entry.snapshot.todayCostUSD))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("\(formatTokens(entry.snapshot.todayTokens)) \(L.tokens(entry.snapshot.language))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            WidgetSparkline(values: entry.snapshot.weekSpend)
                .frame(height: 24)
            HStack {
                Spacer()
                Text(L.relative(entry.snapshot.generatedAt, language: entry.snapshot.language))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(entry.isStale ? 0.6 : 1)
    }
}

// MARK: - Large (338×338) — adds top-3 repos + cache hit + weekly %

private struct LargeView: View {
    let entry: WidgetEntry

    private var pct: Int {
        Int(((entry.snapshot.sessionBlockPercent ?? 0) * 100).rounded())
    }
    private var weeklyPct: Int {
        Int(((entry.snapshot.weeklyPercent ?? 0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderRow(snapshot: entry.snapshot)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(pct)%")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text(L.session(entry.snapshot.language))
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "$%.2f", entry.snapshot.todayCostUSD))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text("\(L.cache(entry.snapshot.language)) \(Int((entry.snapshot.cacheHitRate * 100).rounded()))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            WidgetSparkline(values: entry.snapshot.weekSpend)
                .frame(height: 28)
            HStack {
                Text("\(L.weekly(entry.snapshot.language)) \(weeklyPct)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider().opacity(0.3)
            Text(L.topRepos(entry.snapshot.language))
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(entry.snapshot.topRepos, id: \.name) { repo in
                    RepoRow(repo: repo)
                }
                if entry.snapshot.topRepos.isEmpty {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Text(L.relative(entry.snapshot.generatedAt, language: entry.snapshot.language))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(entry.isStale ? 0.6 : 1)
    }
}

// MARK: - Pieces

private struct HeaderRow: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack {
            Text("CLAUDEGRAIN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.primary)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(snapshot.dataSourceStatus.lowercased())
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch snapshot.dataSourceStatus {
        case "oauthLive": return .green
        case "jsonlOnly", "cliFallback": return .yellow
        case "offline":   return .red
        default:          return .gray
        }
    }
}

private struct RepoRow: View {
    let repo: WidgetSnapshot.Repo

    var body: some View {
        HStack(spacing: 6) {
            Text(repo.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "$%.2f", repo.costUSD))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            BarStrip(percent: repo.percentOfDay)
                .frame(width: 36, height: 6)
        }
    }
}

private struct BarStrip: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * percent)
            }
        }
    }
}

private struct WidgetSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count < 2 {
                Text("—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxV = (values.max() ?? 1).clamped(min: 0.01)
                let stride = geo.size.width / CGFloat(max(1, values.count - 1))
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stride
                        let y = geo.size.height * (1 - CGFloat(v / maxV))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else      { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
}

private extension Double {
    func clamped(min lower: Double) -> Double { Swift.max(self, lower) }
}

// MARK: - Helpers

private func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return "\(n / 1_000)k" }
    return "\(n)"
}

private func resetCountdownText(_ snap: WidgetSnapshot) -> String? {
    guard let resetAt = snap.sessionBlockResetAt else { return nil }
    let secs = max(0, Int(resetAt.timeIntervalSince(Date())))
    let h = secs / 3600
    let m = (secs % 3600) / 60
    let prefix = L.resetsIn(snap.language)
    return "\(prefix) \(h)h\(m)m"
}

// MARK: - Localization (widget extension is sandboxed, can't import host's L)

private enum L {
    static func session(_ lang: String) -> String { lang == "zh" ? "会话" : "SESSION" }
    static func today(_ lang: String) -> String { lang == "zh" ? "今日" : "today" }
    static func tokens(_ lang: String) -> String { lang == "zh" ? "tokens" : "tokens" }
    static func cache(_ lang: String) -> String { lang == "zh" ? "缓存" : "cache" }
    static func weekly(_ lang: String) -> String { lang == "zh" ? "周用量" : "weekly" }
    static func topRepos(_ lang: String) -> String { lang == "zh" ? "热点仓库" : "TOP REPOS" }
    static func resetsIn(_ lang: String) -> String { lang == "zh" ? "重置" : "resets" }

    static func relative(_ date: Date, language: String) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 60 { return language == "zh" ? "刚刚" : "just now" }
        let m = secs / 60
        if m < 60 { return language == "zh" ? "\(m) 分钟前" : "\(m)m ago" }
        let h = m / 60
        return language == "zh" ? "\(h) 小时前" : "\(h)h ago"
    }
}
