import SwiftUI

/// 7d main line chart with grid lines, area fill, today highlight.
struct WeekLineChart: View {
    let points: [Double]   // 7 values
    let todayValue: Double
    @Environment(\.theme) private var theme

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

                // Area + line
                let pts = computePoints(in: geo.size)
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
                }

                // Y reference labels
                VStack {
                    HStack { Text("$10").font(.cgMonoTiny).foregroundStyle(theme.ink.opacity(0.5)); Spacer() }
                    Spacer()
                    HStack { Text("$ 5").font(.cgMonoTiny).foregroundStyle(theme.ink.opacity(0.5)); Spacer() }
                    Spacer()
                }
            }
        }
        .frame(height: 56)
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let maxV = max(points.max() ?? 1, 1)
        let n = max(points.count - 1, 1)
        let leftPad: CGFloat = 22
        let usableW = size.width - leftPad - 12
        return points.enumerated().map { i, v in
            let x = leftPad + usableW * CGFloat(i) / CGFloat(n)
            let y = size.height * (1 - CGFloat(v / maxV)) + 4
            return CGPoint(x: x, y: y)
        }
    }
}

/// 7d day labels strip (M T W T F S S). Sunday bold neon.
struct WeekDayLabels: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack {
            Spacer().frame(width: 14)
            ForEach(["M", "T", "W", "T", "F", "S"], id: \.self) { d in
                Text(d).font(.cgMonoXSmall).foregroundStyle(theme.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            Text("S").font(.cgMonoXSmall.weight(.bold)).foregroundStyle(theme.inkBold)
                .frame(maxWidth: .infinity)
            Spacer().frame(width: 4)
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
