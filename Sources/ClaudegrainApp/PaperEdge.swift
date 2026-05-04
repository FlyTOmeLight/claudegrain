import SwiftUI

/// Zigzag torn-paper edge — used at the top and bottom of the receipt only.
struct PaperEdgeShape: Shape {
    enum Side { case top, bottom }
    let side: Side
    let toothWidth: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = Int((rect.width / toothWidth).rounded(.up))
        switch side {
        case .top:
            // teeth point up (notches into the paper from the top)
            p.move(to: CGPoint(x: 0, y: rect.maxY))
            for i in 0..<count {
                let x0 = CGFloat(i) * toothWidth
                p.addLine(to: CGPoint(x: x0 + toothWidth / 2, y: 0))
                p.addLine(to: CGPoint(x: x0 + toothWidth, y: rect.maxY))
            }
            p.closeSubpath()
        case .bottom:
            // teeth point down
            p.move(to: CGPoint(x: 0, y: 0))
            for i in 0..<count {
                let x0 = CGFloat(i) * toothWidth
                p.addLine(to: CGPoint(x: x0 + toothWidth / 2, y: rect.maxY))
                p.addLine(to: CGPoint(x: x0 + toothWidth, y: 0))
            }
            p.closeSubpath()
        }
        return p
    }
}
