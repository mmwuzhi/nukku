import SwiftUI

/// Notch silhouette shape.
/// - `topRadius`:    outer corners where the notch meets the screen bezel (top)
/// - `bottomRadius`: inner bottom corners (large when expanded for liquid feel)
struct NotchShape: Shape, Animatable {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    // Four values interpolated simultaneously by SwiftUI spring engine
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(topRadius, bottomRadius)
            )
        }
        set {
            width        = newValue.first.first
            height       = newValue.first.second
            topRadius    = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let midX   = rect.midX
        let startX = midX - width / 2
        let endX   = midX + width / 2
        let bottom = height
        let tR     = max(topRadius, 1)        // outer/top corners
        let bR     = max(bottomRadius, 1)     // inner/bottom corners

        var p = Path()

        // ── Top-left outer corner (screen bezel → notch left wall) ──
        p.move(to: CGPoint(x: startX - tR, y: 0))
        p.addArc(
            center: CGPoint(x: startX, y: tR),
            radius: tR,
            startAngle: .degrees(270),
            endAngle:   .degrees(180),
            clockwise:  true
        )

        // ── Left wall ──
        p.addLine(to: CGPoint(x: startX, y: bottom - bR))

        // ── Bottom-left inner corner ──
        p.addArc(
            center: CGPoint(x: startX + bR, y: bottom - bR),
            radius: bR,
            startAngle: .degrees(180),
            endAngle:   .degrees(90),
            clockwise:  true
        )

        // ── Bottom edge ──
        p.addLine(to: CGPoint(x: endX - bR, y: bottom))

        // ── Bottom-right inner corner ──
        p.addArc(
            center: CGPoint(x: endX - bR, y: bottom - bR),
            radius: bR,
            startAngle: .degrees(90),
            endAngle:   .degrees(0),
            clockwise:  true
        )

        // ── Right wall ──
        p.addLine(to: CGPoint(x: endX, y: tR))

        // ── Top-right outer corner ──
        p.addArc(
            center: CGPoint(x: endX, y: tR),
            radius: tR,
            startAngle: .degrees(0),
            endAngle:   .degrees(270),
            clockwise:  true
        )

        p.closeSubpath()
        return p
    }
}
