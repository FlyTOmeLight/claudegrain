import SwiftUI
import ClaudegrainCore

/// 7×24 weekday × hour heatmap powered by `EventsDatabase.hourlyBuckets()`
/// (ADR-0016). Cell intensity = bucket.cost_usd / max(cost_usd in view).
/// Untrusted buckets (sampleCount < 1) render as a faint dot, never as solid
/// — they aren't a real pattern yet.
struct HeatmapView: View {
    let buckets: [HourlyBucket]
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    private var maxCost: Double {
        buckets.lazy.filter { $0.isTrusted }.map(\.costUSD).max() ?? 0
    }

    /// Reorder Calendar.current's Sun-first row order into the user's
    /// `firstWeekday` so a Mon-start locale gets Mon-first rows.
    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var weekdayLabels: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return weekdayOrder.map { symbols[$0 - 1] }
    }

    var body: some View {
        if maxCost == 0 {
            HStack {
                Text(model.t(.heatmapEmpty))
                    .font(.cgMonoSmall)
                    .tracking(0.6)
                    .foregroundStyle(theme.ink.opacity(0.55))
                Spacer()
            }
            .padding(.vertical, 6)
        } else {
            populated
        }
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(zip(weekdayOrder, weekdayLabels).enumerated()), id: \.offset) { _, pair in
                row(weekday: pair.0, label: pair.1)
            }
            hourAxis
        }
    }

    private func row(weekday: Int, label: String) -> some View {
        HStack(spacing: 2) {
            Text(label.uppercased())
                .font(.cgMonoXSmall)
                .tracking(0.4)
                .foregroundStyle(theme.ink.opacity(0.55))
                .frame(width: 18, alignment: .leading)
            HStack(spacing: 1) {
                ForEach(0...23, id: \.self) { hour in
                    cell(weekday: weekday, hour: hour)
                }
            }
        }
    }

    private func cell(weekday: Int, hour: Int) -> some View {
        let bucket = buckets.first { $0.weekday == weekday && $0.hour == hour }
        let intensity: Double = {
            guard let bucket, bucket.isTrusted, maxCost > 0 else { return 0 }
            // Square root scales mid-range cells up so light usage stays visible.
            return min(1.0, sqrt(bucket.costUSD / maxCost))
        }()
        let isUntrustedNonZero = bucket.map { $0.costUSD > 0 && !$0.isTrusted } ?? false

        return Rectangle()
            .fill(fill(intensity: intensity, untrusted: isUntrustedNonZero))
            .frame(width: 7, height: 7)
            .accessibilityLabel(a11yLabel(weekday: weekday, hour: hour, bucket: bucket))
    }

    private func fill(intensity: Double, untrusted: Bool) -> some ShapeStyle {
        if untrusted {
            return AnyShapeStyle(theme.inkFaint.opacity(0.2))
        }
        if intensity <= 0 {
            return AnyShapeStyle(theme.ink.opacity(0.06))
        }
        // Phosphor green ramp; warn tint when above ~0.85.
        let base = intensity > 0.85 ? theme.warn : theme.inkBold
        return AnyShapeStyle(base.opacity(0.15 + 0.85 * intensity))
    }

    private var hourAxis: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 18)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 23], id: \.self) { mark in
                    Text("\(mark)")
                        .font(.cgMonoXSmall)
                        .tracking(0.4)
                        .foregroundStyle(theme.ink.opacity(0.45))
                        .frame(width: tickWidth(for: mark), alignment: .leading)
                }
            }
        }
    }

    /// Ticks at 0/6/12/18/23. Widths sum to 24×8 = 192 (cell 7 + 1 spacing).
    private func tickWidth(for mark: Int) -> CGFloat {
        switch mark {
        case 0:  return 6 * 8
        case 6:  return 6 * 8
        case 12: return 6 * 8
        case 18: return 5 * 8 - 4
        default: return 4 + 16
        }
    }

    private func a11yLabel(weekday: Int, hour: Int, bucket: HourlyBucket?) -> Text {
        guard let bucket, bucket.costUSD > 0 else {
            return Text("no data")
        }
        let dayName = Calendar.current.standaloneWeekdaySymbols[weekday - 1]
        if !bucket.isTrusted {
            return Text("\(dayName) \(hour):00 — sparse data")
        }
        return Text(String(format: "%@ %02d:00 — $%.2f", dayName, hour, bucket.costUSD))
    }
}

#if DEBUG
struct HeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        let buckets: [HourlyBucket] = (1...7).flatMap { d in
            (0...23).map { h in
                let intensity = Double((d * 7 + h * 13) % 16) / 16.0
                return HourlyBucket(weekday: d, hour: h, costUSD: intensity, tokens: 0,
                                    sampleCount: d == wd ? 5.0 : 2.0)
            }
        }
        return HeatmapView(buckets: buckets)
            .padding(12)
            .background(Theme.phosphor.paperBg)
            .environment(\.theme, .phosphor)
            .environmentObject(AppModel())
    }
}
#endif
