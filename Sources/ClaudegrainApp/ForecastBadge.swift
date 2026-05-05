import SwiftUI
import ClaudegrainCore

/// One-line forecast indicator next to the hero number. Shows ETA + basis + confidence.
/// Hidden when forecast is nil or basis == .insufficient.
struct ForecastBadge: View {
    let forecast: ForecastResult?
    let labelKey: L          // .forecastBlockHits or .forecastWeeklyHits
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let f = forecast, f.basis != .insufficient {
            HStack(spacing: 5) {
                Text(f.willHit ? "⏱" : "✓")
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(f.willHit ? 1.0 : 0.5))
                Text(f.willHit ? formattedHitText(f) : safeText(f))
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.85))
                Text("·")
                    .font(.cgMonoXSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.4))
                Text(basisLabel(f) + " · " + confLabel(f))
                    .font(.cgMonoXSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.55))
            }
        } else {
            EmptyView()
        }
    }

    private func formattedHitText(_ f: ForecastResult) -> String {
        guard let hit = f.hitAt else { return "" }
        let mins = Int(hit.timeIntervalSinceNow / 60)
        let suffix: String
        if mins >= 60 { suffix = "\(mins/60)h \(mins%60)m" }
        else          { suffix = "\(max(mins, 0))m" }
        return String(format: model.t(labelKey), suffix)
    }

    private func safeText(_ f: ForecastResult) -> String {
        let key: L = (labelKey == .forecastBlockHits) ? .forecastBlockSafe : .forecastBlockSafe
        return model.t(key)
    }

    private func basisLabel(_ f: ForecastResult) -> String {
        switch f.basis {
        case .ewma:         return model.t(.forecastBasisEwma)
        case .linear:       return model.t(.forecastBasisLinear)
        case .insufficient: return ""
        }
    }

    private func confLabel(_ f: ForecastResult) -> String {
        switch f.confidence {
        case .low:    return model.t(.forecastConfidenceLow)
        case .medium: return model.t(.forecastConfidenceMedium)
        case .high:   return model.t(.forecastConfidenceHigh)
        }
    }
}
