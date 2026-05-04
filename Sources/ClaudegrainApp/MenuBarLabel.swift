import SwiftUI
import ClaudegrainCore
import OSLog

private let log = Logger(subsystem: "dev.claudegrain.menubar", category: "label")

struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }

    private var label: String {
        let value: String
        switch model.primaryMetric {
        case .sessionPercent:
            value = percent(model.sessionBlock?.usedFraction)
        case .weeklyPercent:
            value = percent(model.weekly?.usedFraction)
        case .todayCost:
            value = String(format: "$%.2f", model.todayTotals.costUSD)
        case .cacheHit:
            value = percent(model.cacheHitRate)
        }
        log.notice("metric=\(String(describing: self.model.primaryMetric), privacy: .public) sessionFrac=\(String(describing: self.model.sessionBlock?.usedFraction), privacy: .public) cacheHit=\(self.model.cacheHitRate, privacy: .public) → \(value, privacy: .public)")
        return value
    }

    private var statusColor: Color {
        let frac = model.sessionBlock?.usedFraction ?? 0
        if frac >= 0.9 { return .red }
        if frac >= 0.7 { return .yellow }
        return .green
    }

    private func percent(_ frac: Double?) -> String {
        guard let frac else { return "—" }
        return "\(Int((frac * 100).rounded()))%"
    }
}
