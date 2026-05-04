import SwiftUI
import ClaudegrainCore

// MARK: - Stencil title — compact 2-row half-block letters

let stencilTitle = """
█▀▀ █   ▄▀█ █ █ █▀▄ █▀▀ █▀▀ █▀█ ▄▀█ █ █▄ █
█▄▄ █▄▄ █▀█ █▄█ █▄▀ ██▄ █▄█ █▀▄ █▀█ █ █ ▀█
"""

struct StencilTitleView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text(stencilTitle)
            .font(.custom("JetBrains Mono", size: 11).weight(.bold))
            .tracking(0.5)
            .foregroundStyle(theme.inkBold)
            .neonGlow(color: theme.inkBold, radius: 3, opacity: theme.glowEnabled ? 0.55 : 0)
            .multilineTextAlignment(.center)
            .lineSpacing(-1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Glow modifier

private struct NeonGlow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius)
            .shadow(color: color.opacity(opacity * 0.5), radius: radius * 2)
    }
}

extension View {
    func neonGlow(color: Color, radius: CGFloat, opacity: Double = 0.5) -> some View {
        modifier(NeonGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Pulse red dot

struct LiveDot: View {
    @State private var animate = false
    @Environment(\.theme) private var theme

    var body: some View {
        Circle()
            .fill(theme.pulse)
            .frame(width: 7, height: 7)
            .scaleEffect(animate ? 0.85 : 1)
            .opacity(animate ? 0.4 : 1)
            .neonGlow(color: theme.pulse, radius: 3, opacity: theme.glowEnabled ? 0.6 : 0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let label: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(theme.ink.opacity(0.25)).frame(height: 1)
            Text(label)
                .font(.custom("JetBrains Mono", size: 9))
                .tracking(1.6)
                .foregroundStyle(theme.ink.opacity(0.7))
            Rectangle().fill(theme.ink.opacity(0.25)).frame(height: 1)
        }
    }
}

struct DoubleDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text(String(repeating: "═", count: 31))
            .font(.custom("JetBrains Mono", size: 11))
            .foregroundStyle(theme.ink.opacity(0.5))
            .padding(.vertical, 2)
    }
}

struct DashedDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text(String(repeating: "╌", count: 25))
            .font(.custom("JetBrains Mono", size: 12))
            .foregroundStyle(theme.ink.opacity(0.42))
            .tracking(0.5)
            .padding(.vertical, 2)
    }
}

struct StarsDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text("* * * * * * * * * * * * *")
            .font(.custom("JetBrains Mono", size: 10))
            .foregroundStyle(theme.ink.opacity(0.32))
            .tracking(2)
            .padding(.vertical, 2)
    }
}

// MARK: - Hero TODAY

struct HeroSpend: View {
    let totals: DailyTotals
    let yesterdayCost: Double
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            Text("[ TOTAL · TODAY ]")
                .font(.cgMonoSmall)
                .tracking(2.2)
                .foregroundStyle(theme.ink.opacity(0.6))

            Text(String(format: "$%.2f", totals.costUSD))
                .font(.cgDisplay)
                .foregroundStyle(theme.inkBold)
                .neonGlow(color: theme.inkBold, radius: 8, opacity: theme.glowEnabled ? 0.55 : 0)
                .neonGlow(color: theme.inkBold, radius: 18, opacity: theme.glowEnabled ? 0.28 : 0)

            HStack(spacing: 6) {
                if yesterdayCost > 0 {
                    let pct = (totals.costUSD - yesterdayCost) / yesterdayCost * 100
                    Text("\(pct >= 0 ? "↑" : "↓") \(String(format: "%.1f", abs(pct)))%")
                        .font(.cgMonoMed)
                        .foregroundStyle(theme.crit)
                        .bold()
                }
                Text("vs $\(String(format: "%.2f", yesterdayCost)) yest · \(totals.totalTokens / 1000)k tok")
                    .font(.cgMonoMed)
                    .foregroundStyle(theme.ink.opacity(0.55))
            }
            .padding(.top, 2)

            ModelStackBar(byModel: totals.byModel)
                .padding(.top, 4)
        }
    }
}

struct ModelStackBar: View {
    let byModel: [String: Int]
    @Environment(\.theme) private var theme

    var body: some View {
        let total = max(byModel.values.reduce(0, +), 1)
        VStack(spacing: 3) {
            HStack(spacing: 1) {
                ForEach(sortedModels, id: \.0) { model, tokens in
                    Rectangle()
                        .fill(color(for: model))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .frame(width: nil)
                        .layoutPriority(Double(tokens) / Double(total))
                }
            }
            HStack {
                Text("Opus \(formatK(byModel["claude-opus-4-7"] ?? 0))")
                Spacer()
                Text("Sonnet \(formatK(byModel["claude-sonnet-4-6"] ?? 0))")
                Spacer()
                Text("Haiku \(formatK(byModel["claude-haiku-4-5"] ?? 0))")
            }
            .font(.cgMonoXSmall)
            .foregroundStyle(theme.ink.opacity(0.7))
        }
    }

    private var sortedModels: [(String, Int)] {
        ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5"].compactMap { key in
            byModel[key].map { (key, $0) }
        }
    }

    private func color(for model: String) -> Color {
        if model.contains("opus") { return theme.opus }
        if model.contains("sonnet") { return theme.sonnet }
        return theme.haiku
    }

    private func formatK(_ tokens: Int) -> String {
        if tokens >= 1000 { return "\(tokens / 1000)k" }
        return "\(tokens)"
    }
}

// MARK: - Vitals (SESSION / WEEKLY / CACHE rows)

struct VitalRow: View {
    let label: String
    let percent: Double
    let resetText: String
    let isWarn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(barColor).frame(width: 5, height: 5)
                        .neonGlow(color: barColor, radius: 2, opacity: theme.glowEnabled ? 0.5 : 0)
                    Text(label)
                        .font(.cgMonoMed)
                        .tracking(1.4)
                        .foregroundStyle(theme.ink.opacity(0.7))
                }
                .frame(width: 88, alignment: .leading)
                Text(asciiBar)
                    .font(.cgMono)
                    .foregroundStyle(barColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int((percent * 100).rounded()))%")
                    .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                    .foregroundStyle(barColor)
                    .neonGlow(color: barColor, radius: 2, opacity: theme.glowEnabled ? 0.4 : 0)
                    .frame(width: 38, alignment: .trailing)
            }
            Text(resetText)
                .font(.cgMonoXSmall)
                .foregroundStyle(theme.ink.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var barColor: Color { isWarn ? theme.warn : theme.inkBold }

    private var asciiBar: String {
        let total = 19
        let filled = Int((percent * Double(total)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: total - filled)
    }
}
