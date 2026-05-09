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
            .accessibilityElement()
            .accessibilityLabel("Claudegrain")
            .accessibilityAddTraits(.isHeader)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(theme.pulse)
            .frame(width: 7, height: 7)
            .scaleEffect(animate ? 0.85 : 1)
            .opacity(animate ? 0.4 : 1)
            .neonGlow(color: theme.pulse, radius: 3, opacity: theme.glowEnabled ? 0.6 : 0)
            .animation(Motion.preferred(.cgPulse, reduceMotion: reduceMotion), value: animate)
            .onAppear { if !reduceMotion { animate = true } }
            .accessibilityHidden(true)
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
            .accessibilityHidden(true)
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
            .accessibilityHidden(true)
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
            .accessibilityHidden(true)
    }
}

// MARK: - Hero TOTAL / TODAY

/// Displays the headline cost figure. Two clickable tabs switch between
/// all-time spend (TOTAL) and today's spend (TODAY). Driven by
/// `AppModel.heroMode`; when TODAY is selected, also shows a yesterday-delta
/// hint.
struct HeroSpend: View {
    @EnvironmentObject private var model: AppModel
    let yesterdayCost: Double
    @Environment(\.theme) private var theme

    init(yesterdayCost: Double = 0) {
        self.yesterdayCost = yesterdayCost
    }

    private var current: DailyTotals {
        model.heroMode == .total ? model.allTimeTotals : model.todayTotals
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                tab(.heroTabTotal, mode: .total)
                Text("·")
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.ink.opacity(0.4))
                tab(.heroTabToday, mode: .today)
            }

            Text(String(format: "$%.2f", current.costUSD))
                .font(.cgDisplay)
                .foregroundStyle(theme.inkBold)
                .neonGlow(color: theme.inkBold, radius: 8, opacity: theme.glowEnabled ? 0.55 : 0)
                .neonGlow(color: theme.inkBold, radius: 18, opacity: theme.glowEnabled ? 0.28 : 0)
                .contentTransition(.numericText())
                .animation(.cgFast, value: current.costUSD)
                .accessibilityLabel(heroA11yLabel)

            HStack(spacing: 6) {
                if model.heroMode == .today, yesterdayCost > 0 {
                    let pct = (current.costUSD - yesterdayCost) / yesterdayCost * 100
                    Text("\(pct >= 0 ? "↑" : "↓") \(String(format: "%.1f", abs(pct)))%")
                        .font(.cgMonoMed)
                        .foregroundStyle(theme.crit)
                        .bold()
                    Text(String(
                        format: model.t(.heroVsYesterday),
                        yesterdayCost,
                        "\(current.totalTokens / 1000)"
                    ))
                        .font(.cgMonoMed)
                        .foregroundStyle(theme.ink.opacity(0.55))
                } else {
                    Text(subLabel)
                        .font(.cgMonoMed)
                        .foregroundStyle(theme.ink.opacity(0.55))
                }
            }
            .padding(.top, 2)
            .id(model.heroMode)
            .transition(.opacity)

            ModelStackBar(byModel: current.byModel)
                .padding(.top, 4)
                .id(model.heroMode)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
        .animation(.cgFast, value: model.heroMode)
    }

    /// "$X.XX, today" / "$X.XX, all-time" — VoiceOver friendly.
    private var heroA11yLabel: String {
        let dollars = String(format: "$%.2f", current.costUSD)
        let scope = model.heroMode == .today ? model.t(.heroTabToday) : model.t(.heroTabTotal)
        return "\(dollars), \(scope)"
    }

    private var subLabel: String {
        let toks = "\(current.totalTokens / 1000)"
        switch model.heroMode {
        case .total: return String(format: model.t(.heroSubLifetime), toks)
        case .today: return String(format: model.t(.heroSubToday), toks)
        }
    }

    private func tab(_ key: L, mode: HeroMode) -> some View {
        let active = model.heroMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { model.heroMode = mode }
        } label: {
            Text("[ \(model.t(key)) ]")
                .font(.cgMonoSmall.weight(active ? .bold : .regular))
                .tracking(2.2)
                .foregroundStyle(active ? theme.inkBold : theme.ink.opacity(0.4))
                .neonGlow(
                    color: theme.inkBold,
                    radius: 2,
                    opacity: active && theme.glowEnabled ? 0.45 : 0
                )
        }
        .buttonStyle(.plain)
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
                    .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int((percent * 100).rounded())) percent")
        .accessibilityValue(resetText)
    }

    private var barColor: Color { isWarn ? theme.warn : theme.inkBold }

    private var asciiBar: String {
        let total = 19
        let filled = Int((percent * Double(total)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: total - filled)
    }
}
