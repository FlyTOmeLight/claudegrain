import SwiftUI
import WidgetKit
import ClaudegrainCore

/// Phosphor palette mirrored from `Sources/ClaudegrainApp/Theme.swift`. The
/// widget extension is a separate process and can't import the host's Theme
/// directly; values match V18 Phosphor exactly so the widget reads as
/// part of the same product.
private enum Phos {
    static let paper    = Color(red: 0x04 / 255, green: 0x06 / 255, blue: 0x0A / 255)
    static let ink      = Color(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0xD2 / 255)
    static let inkBold  = Color(red: 0x6D / 255, green: 0xFF / 255, blue: 0xAE / 255)
    static let inkFaint = Color(red: 0x5A / 255, green: 0x8A / 255, blue: 0x72 / 255)
    static let warn     = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255)
    static let crit     = Color(red: 0xFF / 255, green: 0x5C / 255, blue: 0x5C / 255)
}

struct ClaudegrainEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            case .systemLarge:  LargeView(entry: entry)
            default:            SmallView(entry: entry)
            }
        }
        .foregroundStyle(Phos.ink)
        .containerBackground(for: .widget) {
            ZStack {
                Phos.paper
                // Faint scanlines for the receipt feel — every 2pt.
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    let step: CGFloat = 2
                    while y < size.height {
                        let r = CGRect(x: 0, y: y, width: size.width, height: 0.5)
                        ctx.fill(Path(r), with: .color(Phos.inkBold.opacity(0.04)))
                        y += step
                    }
                }
            }
        }
    }
}

// MARK: - Small (155×155) — single hero metric

private struct SmallView: View {
    let entry: WidgetEntry

    private var pct: Int {
        Int(((entry.snapshot.sessionBlockPercent ?? 0) * 100).rounded())
    }

    private var heroColor: Color {
        switch (entry.snapshot.sessionBlockPercent ?? 0) {
        case ..<0.7:  return Phos.inkBold
        case ..<0.9:  return Phos.warn
        default:      return Phos.crit
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HeaderRow(snapshot: entry.snapshot)
            DividerLine()
            Spacer()
            Text("\(pct)%")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(heroColor)
                .shadow(color: heroColor.opacity(0.5), radius: 6)
            Text(L.session(entry.snapshot.language))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Phos.inkFaint)
            Spacer().frame(height: 4)
            if let resetText = resetCountdownText(entry.snapshot) {
                Text(resetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phos.inkFaint)
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

    private var heroColor: Color {
        switch (entry.snapshot.sessionBlockPercent ?? 0) {
        case ..<0.7:  return Phos.inkBold
        case ..<0.9:  return Phos.warn
        default:      return Phos.crit
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderRow(snapshot: entry.snapshot)
            DividerLine()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(pct)%")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(heroColor)
                        .shadow(color: heroColor.opacity(0.5), radius: 5)
                    Text(L.session(entry.snapshot.language))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Phos.inkFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", entry.snapshot.todayCostUSD))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Phos.inkBold)
                    Text(L.today(entry.snapshot.language).uppercased())
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Phos.inkFaint)
                    Text("\(formatTokens(entry.snapshot.todayTokens)) tok")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Phos.inkFaint)
                }
            }
            WidgetSparkline(values: entry.snapshot.weekSpend)
                .frame(height: 24)
            HStack {
                Text("7d")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Phos.inkFaint)
                Spacer()
                Text(L.relative(entry.snapshot.generatedAt, language: entry.snapshot.language))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Phos.inkFaint.opacity(0.6))
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

    private var heroColor: Color {
        switch (entry.snapshot.sessionBlockPercent ?? 0) {
        case ..<0.7:  return Phos.inkBold
        case ..<0.9:  return Phos.warn
        default:      return Phos.crit
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderRow(snapshot: entry.snapshot)
            DividerLine()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(pct)%")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(heroColor)
                        .shadow(color: heroColor.opacity(0.5), radius: 5)
                    Text(L.session(entry.snapshot.language))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Phos.inkFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "$%.2f", entry.snapshot.todayCostUSD))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Phos.inkBold)
                    Text("\(L.cache(entry.snapshot.language)) \(Int((entry.snapshot.cacheHitRate * 100).rounded()))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Phos.inkFaint)
                }
            }
            WidgetSparkline(values: entry.snapshot.weekSpend)
                .frame(height: 28)
            HStack {
                Text("7d")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Phos.inkFaint)
                Spacer()
                Text("\(L.weekly(entry.snapshot.language)) \(weeklyPct)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(weeklyPct >= 90 ? Phos.crit : Phos.inkFaint)
            }
            DashedDivider()
            Text(L.topRepos(entry.snapshot.language))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Phos.inkFaint)
            VStack(spacing: 2) {
                ForEach(entry.snapshot.topRepos, id: \.name) { repo in
                    RepoRow(repo: repo)
                }
                if entry.snapshot.topRepos.isEmpty {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Phos.inkFaint.opacity(0.6))
                }
            }
            Spacer()
            HStack {
                Spacer()
                Text(L.relative(entry.snapshot.generatedAt, language: entry.snapshot.language))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Phos.inkFaint.opacity(0.6))
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
        HStack(spacing: 4) {
            Text("CLAUDEGRAIN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Phos.inkBold)
                .shadow(color: Phos.inkBold.opacity(0.5), radius: 3)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .shadow(color: statusColor.opacity(0.6), radius: 2)
            Text(statusText.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Phos.inkFaint)
        }
    }

    private var statusColor: Color {
        switch snapshot.dataSourceStatus {
        case "oauthLive": return Phos.inkBold
        case "jsonlOnly", "cliFallback": return Phos.warn
        case "offline":   return Phos.crit
        default:          return Phos.inkFaint
        }
    }

    private var statusText: String {
        switch snapshot.dataSourceStatus {
        case "oauthLive":   return "live"
        case "jsonlOnly":   return "jsonl"
        case "cliFallback": return "cli"
        case "offline":     return "offline"
        default:            return "boot"
        }
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Phos.inkFaint.opacity(0.4))
            .frame(height: 0.5)
    }
}

private struct DashedDivider: View {
    var body: some View {
        Text(String(repeating: "╌", count: 30))
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Phos.inkFaint.opacity(0.5))
            .lineLimit(1)
            .clipped()
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
                .foregroundStyle(Phos.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "$%.2f", repo.costUSD))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Phos.inkBold)
                .frame(width: 56, alignment: .trailing)
            BarStrip(percent: repo.percentOfDay)
                .frame(width: 36, height: 7)
        }
    }
}

private struct BarStrip: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Phos.inkFaint.opacity(0.25))
                RoundedRectangle(cornerRadius: 1)
                    .fill(Phos.inkBold)
                    .frame(width: geo.size.width * percent)
                    .shadow(color: Phos.inkBold.opacity(0.6), radius: 2)
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
                    .foregroundStyle(Phos.inkFaint.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxV = (values.max() ?? 1).clamped(min: 0.01)
                let step = geo.size.width / CGFloat(max(1, values.count - 1))
                let path = Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height * (1 - CGFloat(v / maxV))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else      { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                ZStack {
                    // Glow underlay.
                    path.stroke(Phos.inkBold.opacity(0.4), lineWidth: 4)
                        .blur(radius: 3)
                    path.stroke(Phos.inkBold, lineWidth: 1.5)
                    // Trailing dot — current point.
                    if let last = values.last {
                        let x = geo.size.width
                        let y = geo.size.height * (1 - CGFloat(last / maxV))
                        Circle()
                            .fill(Phos.inkBold)
                            .frame(width: 5, height: 5)
                            .position(x: x - 1, y: y)
                            .shadow(color: Phos.inkBold.opacity(0.7), radius: 3)
                    }
                }
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
