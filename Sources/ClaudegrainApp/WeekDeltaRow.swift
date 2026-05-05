import SwiftUI
import ClaudegrainCore

/// Single-line "Δ vs last week" mini row. Shows "first week" on first run.
struct WeekDeltaRow: View {
    let delta: WeekDelta?
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(model.t(.weekDeltaLabel))
                .font(.cgMonoXSmall)
                .tracking(1.4)
                .foregroundStyle(theme.ink.opacity(0.55))
            Spacer()
            Text(deltaText)
                .font(.cgMonoSmall)
                .foregroundStyle(deltaColor)
        }
    }

    private var deltaText: String {
        guard let d = delta else { return "—" }
        guard let pct = d.pctChange else { return model.t(.weekDeltaFirstWeek) }
        let pctInt = Int((pct * 100).rounded())
        let cachePP = Int((d.cacheHitDelta * 100).rounded())
        let cacheStr = cachePP >= 0
            ? String(format: model.t(.weekDeltaCacheUp), cachePP)
            : String(format: model.t(.weekDeltaCacheDown), cachePP)
        if pctInt >= 0 {
            return String(format: model.t(.weekDeltaPctUp), pctInt, cacheStr)
        } else {
            return String(format: model.t(.weekDeltaPctDown), pctInt, cacheStr)
        }
    }

    private var deltaColor: Color {
        guard let pct = delta?.pctChange else { return theme.ink.opacity(0.7) }
        // Up = warmer (more spend = warning), down = cool (saved $).
        return pct > 0 ? theme.warn : theme.inkBold
    }
}
