import SwiftUI

/// Dynamic-Island-style fused silhouette.
///
/// Anchored at y=0 (top of canvas) where the shape is *widest* (`topWidth`) and
/// drips outward from the hardware notch via two concave **melt** Bezier
/// curves. Below the cove (depth = `coveHeight`) the panel narrows to
/// `bodyWidth` and runs straight down to convex bottom corners.
///
/// `topWidth >= bodyWidth` — the panel never necks inward like the old
/// shoulder shape did. Same pure black as the hardware notch produces the
/// fusion illusion; no glass blur on top.
///
/// Geometry derived from Claude Design's `fusedPath` (see
/// `.claude/plans/...` design handoff). Six animatable values so SwiftUI
/// springs can interpolate state-to-state without popping.
struct NotchShape: Shape, Animatable {
    var topWidth:     CGFloat
    var bodyWidth:    CGFloat
    var height:       CGFloat
    var coveHeight:   CGFloat
    var bottomRadius: CGFloat
    var tension:      CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(topWidth, bodyWidth),
                    AnimatablePair(height, coveHeight)
                ),
                AnimatablePair(bottomRadius, tension)
            )
        }
        set {
            topWidth     = newValue.first.first.first
            bodyWidth    = newValue.first.first.second
            height       = newValue.first.second.first
            coveHeight   = newValue.first.second.second
            bottomRadius = newValue.second.first
            tension      = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let midX     = rect.midX
        let halfTop  = topWidth / 2
        let halfBody = bodyWidth / 2
        let cove     = max(coveHeight, 0.001)
        let H        = max(height, cove + 0.001)

        // Top edge endpoints (where the shape meets y=0, widest).
        let topL  = CGPoint(x: midX - halfTop,  y: 0)
        let topR  = CGPoint(x: midX + halfTop,  y: 0)
        // Body edge endpoints (where the melt ends and straight walls begin).
        let bodyL = CGPoint(x: midX - halfBody, y: cove)
        let bodyR = CGPoint(x: midX + halfBody, y: cove)

        // Tension scales the Bezier control offsets — higher = blunter melt,
        // lower = tighter inward curl.
        let h = tension * (halfTop - halfBody)
        let v = tension * cove
        let bR = max(0, min(bottomRadius, halfBody, H - cove))

        var p = Path()
        p.move(to: topL)

        // ── Left melt (concave from panel interior) ──
        // Drips out of the menu bar: starts at the wider top edge, curves
        // inward+down, lands tangent to the left wall at `cove`.
        p.addCurve(
            to: bodyL,
            control1: CGPoint(x: topL.x + h, y: 0),
            control2: CGPoint(x: bodyL.x,    y: cove - v)
        )

        // Left wall, straight down to the bottom corner.
        p.addLine(to: CGPoint(x: bodyL.x, y: H - bR))

        // Bottom-left convex corner.
        p.addQuadCurve(
            to: CGPoint(x: bodyL.x + bR, y: H),
            control: CGPoint(x: bodyL.x, y: H)
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: bodyR.x - bR, y: H))

        // Bottom-right convex corner.
        p.addQuadCurve(
            to: CGPoint(x: bodyR.x, y: H - bR),
            control: CGPoint(x: bodyR.x, y: H)
        )

        // Right wall.
        p.addLine(to: CGPoint(x: bodyR.x, y: cove))

        // ── Right melt (mirror of left) ──
        p.addCurve(
            to: topR,
            control1: CGPoint(x: bodyR.x,    y: cove - v),
            control2: CGPoint(x: topR.x - h, y: 0)
        )

        p.closeSubpath()
        return p
    }
}
