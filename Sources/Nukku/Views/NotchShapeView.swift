import SwiftUI

struct NotchShape: Shape, Animatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(width, height), cornerRadius) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let midX = rect.midX
        let startX = midX - width / 2
        let endX = midX + width / 2
        let bottom = height
        let outerR = Constants.Notch.outerCornerRadius
        let innerR = max(cornerRadius, 1)

        var path = Path()
        // Start at top-left edge (just outside the notch)
        path.move(to: CGPoint(x: startX - outerR, y: 0))
        // Outer left corner (curving inward from screen edge down into notch left side)
        path.addArc(
            center: CGPoint(x: startX, y: outerR),
            radius: outerR,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true
        )
        // Left vertical edge down to inner corner
        path.addLine(to: CGPoint(x: startX, y: bottom - innerR))
        // Inner bottom-left corner
        path.addArc(
            center: CGPoint(x: startX + innerR, y: bottom - innerR),
            radius: innerR,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: endX - innerR, y: bottom))
        // Inner bottom-right corner
        path.addArc(
            center: CGPoint(x: endX - innerR, y: bottom - innerR),
            radius: innerR,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        // Right vertical edge up
        path.addLine(to: CGPoint(x: endX, y: outerR))
        // Outer right corner
        path.addArc(
            center: CGPoint(x: endX, y: outerR),
            radius: outerR,
            startAngle: .degrees(0),
            endAngle: .degrees(270),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
