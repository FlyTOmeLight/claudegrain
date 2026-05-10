import SwiftUI

/// 7d main line chart with grid lines, area fill, today highlight.
struct WeekLineChart: View {
    let points: [Double]   // 7 values, oldest → newest. Last entry is today
                           // per `EventsDatabase.costPerDay`, but the SQLite
                           // bucket can lag the OAuth/live total — `todayValue`
                           // is always treated as the source of truth for the
                           // last point so the dot, area, and label agree.
    let todayValue: Double
    @Environment(\.theme) private var theme

    private var effectivePoints: [Double] {
        guard points.count == 7 else { return points }
        var p = points
        p[6] = todayValue
        return p
    }

    private var scaleMax: Double {
        let raw = max(effectivePoints.max() ?? 0, todayValue, 0.01)
        return niceCeil(raw)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Grid
                Path { p in
                    for y in [0.25, 0.5, 0.75] {
                        let yy = geo.size.height * y
                        p.move(to: CGPoint(x: 0, y: yy))
                        p.addLine(to: CGPoint(x: geo.size.width, y: yy))
                    }
                }
                .stroke(theme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [1, 4]))

                // Area + line — strictly dot-to-dot. Earlier I tried
                // extending stubs to the chart edges so the visible
                // region matched the dividers' span, but the line stub
                // sits at the endpoint dots' y (not at chart bottom),
                // which read as a tilted baseline against the flat
                // dividers above/below. Symmetric padding via
                // `computePoints` keeps the chart visually centered.
                let pts = computePoints(in: geo.size)
                let values = effectivePoints
                if !pts.isEmpty {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(theme.inkBold.opacity(0.16))

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(theme.inkBold, lineWidth: 1.5)
                    .neonGlow(color: theme.inkBold, radius: 2, opacity: theme.glowEnabled ? 0.6 : 0)

                    // Past days = small hollow circles
                    ForEach(0..<(pts.count - 1), id: \.self) { i in
                        Circle()
                            .stroke(theme.inkBold, lineWidth: 1.5)
                            .background(Circle().fill(theme.paperBg))
                            .frame(width: 5, height: 5)
                            .position(pts[i])
                    }

                    // Today = large filled
                    Circle()
                        .fill(theme.inkBold)
                        .frame(width: 8, height: 8)
                        .neonGlow(color: theme.inkBold, radius: 3, opacity: theme.glowEnabled ? 0.7 : 0)
                        .position(pts.last!)

                    Text(String(format: "$%.2f", todayValue))
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundStyle(theme.inkBold)
                        .neonGlow(color: theme.inkBold, radius: 2, opacity: theme.glowEnabled ? 0.6 : 0)
                        .position(x: pts.last!.x, y: max(pts.last!.y - 10, 8))
                        .allowsHitTesting(false)

                    // Annotate just the week's peak so the user has a Y-axis
                    // anchor without a full grid scale that crowds the
                    // plot. Skipped when the peak IS today — today's own
                    // bold label already serves as the anchor.
                    if let peakIdx = peakIndex(values), peakIdx < pts.count - 1 {
                        // Offset the label to the right of the dot so they
                        // don't overlap. Label is roughly 60pt wide; nudging
                        // by +30 puts the dot at the *left* of the label.
                        let peakX = pts[peakIdx].x + 30
                        let peakY = max(pts[peakIdx].y - 2, 8)
                        Text("max \(formatPointLabel(values[peakIdx]))")
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundStyle(theme.ink.opacity(0.65))
                            .position(x: peakX, y: peakY)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 56)
    }

    private func peakIndex(_ vs: [Double]) -> Int? {
        guard !vs.isEmpty else { return nil }
        var idx = 0
        for i in 1..<vs.count where vs[i] > vs[idx] { idx = i }
        return idx
    }

    private func formatPointLabel(_ v: Double) -> String {
        if v <= 0 { return "$0" }
        if v >= 1000 {
            let k = v / 1000
            return k >= 10
                ? String(format: "$%.0fk", k)
                : String(format: "$%.1fk", k)
        }
        if v >= 100 { return String(format: "$%.0f", v) }
        if v >= 10  { return String(format: "$%.0f", v) }
        return String(format: "$%.1f", v)
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        let values = effectivePoints
        guard !values.isEmpty else { return [] }
        let maxV = scaleMax
        // Match the X grid used by `WeekDayLabels` so each dot sits over
        // its day letter:
        //   HStack { Spacer 14 · 7×maxWidth cells · Spacer 14 }
        // The dot for day i lives at the center of cell i. Spacers must
        // be equal — asymmetric padding made the chart visually drift
        // right of center (left margin 35 vs right 25), which read as
        // "the chart is tilted" against the symmetric horizontal divider
        // immediately above and below.
        let leftSpacer: CGFloat = 14
        let rightSpacer: CGFloat = 14
        let cellW = (size.width - leftSpacer - rightSpacer) / CGFloat(values.count)
        // Reserve top + bottom padding so the dots can never escape the
        // chart frame; the previous formula let v ≈ 0 dots render at
        // size.height + 4, which painted them on top of the day-letter row
        // below the chart.
        let yPad: CGFloat = 4
        let usableH = size.height - 2 * yPad
        return values.enumerated().map { i, v in
            let x = leftSpacer + cellW * (CGFloat(i) + 0.5)
            let y = yPad + usableH * CGFloat(1 - v / maxV)
            return CGPoint(x: x, y: y)
        }
    }

    /// Round v up to the next "nice" axis tick so the top label is round
    /// (e.g. 2525 → 3000, 181 → 200, 7.3 → 8).
    private func niceCeil(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let step: Double
        if v < 5         { step = 1 }
        else if v < 10   { step = 5 }
        else if v < 100  { step = 10 }
        else if v < 1000 { step = 100 }
        else if v < 10000 { step = 1000 }
        else {
            step = pow(10.0, floor(log10(v)))
        }
        return (v / step).rounded(.up) * step
    }

    private func tooltip(dayIndex i: Int, value: Double) -> String {
        // points are oldest → newest; index 6 is today. Walk back from today.
        let labels = weekdayLabels()
        let label = (i >= 0 && i < labels.count) ? labels[i] : ""
        return label.isEmpty
            ? String(format: "$%.2f", value)
            : "\(label) · \(String(format: "$%.2f", value))"
    }

    private func weekdayLabels() -> [String] {
        // Localized abbreviated weekday names ending at today.
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.dateFormat = "EEE"
        return (0..<7).compactMap { offset in
            let d = cal.date(byAdding: .day, value: -(6 - offset), to: today)
            return d.map { fmt.string(from: $0) }
        }
    }
}

/// Empty-state placeholder for the 7d chart. Renders when ingest hasn't
/// populated `weekSpend` yet — replaces a previous fake-ramp fallback that
/// misled users into thinking they were looking at real data.
struct WeekChartPlaceholder: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.t(.chartCollectingBaseline))
            .font(.cgMonoSmall)
            .tracking(0.6)
            .foregroundStyle(theme.ink.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 56)
            .accessibilityLabel(model.t(.chartCollectingBaseline))
    }
}

/// 7d day labels strip (Mo Tu We Th Fr Sa Su). Two-letter ISO abbrevs so
/// Saturday and Sunday don't both read as "S" — the previous single-letter
/// strip ambiguated weekend days. Sunday gets bold neon for today.
///
/// Side spacers are intentionally equal — `WeekLineChart` mirrors the same
/// 14pt symmetric margin in `computePoints`. Keep them in sync.
struct WeekDayLabels: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack {
            Spacer().frame(width: 14)
            ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { d in
                Text(d).font(.cgMonoXSmall).foregroundStyle(theme.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            Text("Su").font(.cgMonoXSmall.weight(.bold)).foregroundStyle(theme.inkBold)
                .frame(maxWidth: .infinity)
            Spacer().frame(width: 14)
        }
    }
}

/// Per-row mini sparkline (32×14) for top-cost rows.
struct MiniSparkline: View {
    let points: [Double]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let pts = computePoints(in: geo.size)
            if pts.count > 1 {
                Path { p in
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(theme.inkBold, lineWidth: 1)
                .neonGlow(color: theme.inkBold, radius: 1.5, opacity: theme.glowEnabled ? 0.5 : 0)

                Circle()
                    .fill(theme.inkBold)
                    .frame(width: 3, height: 3)
                    .position(pts.last!)
            }
        }
        .frame(width: 32, height: 14)
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let minV = points.min() ?? 0
        let maxV = max(points.max() ?? 1, minV + 0.001)
        return points.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(points.count - 1)
            let normalized = (v - minV) / (maxV - minV)
            let y = size.height * (1 - normalized)
            return CGPoint(x: x, y: max(1, min(size.height - 1, y)))
        }
    }
}
