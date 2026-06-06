import CoreGraphics

enum Constants {
    enum Notch {
        // Fixed canvas — the panel window never resizes
        static let canvasWidth:  CGFloat = 700
        static let canvasHeight: CGFloat = 340

        // Hardware notch dimensions (overwritten from screen.safeAreaInsets at launch)
        static let collapsedWidth:  CGFloat = 250
        static let collapsedHeight: CGFloat = 38

        // Hover dwell before expand fires
        static let hoverDwellSeconds: Double = 0.1

        // Accent halo height (top color bleed in expanded state)
        static let accentGradientHeight: CGFloat = 90
    }

    /// Per-state silhouette metrics for the fused notch panel.
    ///
    /// Values from Claude Design's handoff (`Media Widget Polish.html`,
    /// `widget.jsx` SHAPES dict). The shape's top edge is always wider
    /// than its body (`topWidth >= bodyWidth`) so the melt curves drip
    /// out of the menu bar instead of necking inward.
    enum Geometry {
        struct StateMetrics: Equatable {
            var topWidth:     CGFloat
            var bodyWidth:    CGFloat
            var height:       CGFloat   // total panel height (0 = use widget preferred)
            var coveHeight:   CGFloat   // depth of melt curve
            var bottomRadius: CGFloat
        }

        static let rest = StateMetrics(
            topWidth: 282, bodyWidth: 270, height: 38,
            coveHeight: 11, bottomRadius: 14
        )

        static let openBase = StateMetrics(
            topWidth: 318, bodyWidth: 300, height: 156,
            coveHeight: 17, bottomRadius: 28
        )

        static let hud = StateMetrics(
            topWidth: 348, bodyWidth: 330, height: 64,
            coveHeight: 14, bottomRadius: 24
        )

        /// Bezier control point ratio for the melt curves (0..1). Higher
        /// values = blunter / wider melt; lower = tighter inward curl.
        static let tension: CGFloat = 0.62

        static func open(height: CGFloat) -> StateMetrics {
            var m = openBase
            m.height = height
            return m
        }
    }

    enum Animation {
        static let expandResponse:   Double = 0.42
        static let expandDamping:    Double = 0.72
        static let collapseResponse: Double = 0.30
        static let collapseDamping:  Double = 0.85
        static let collapseDelay:    Double = 0.30
    }

    enum Widget {
        static let minSize       = CGSize(width: 120, height: 80)
        static let defaultPadding: CGFloat = 12
        static let cornerRadius:   CGFloat = 12
    }
}
