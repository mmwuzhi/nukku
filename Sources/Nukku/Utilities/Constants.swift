import CoreGraphics

enum Constants {
    enum Notch {
        // Fixed canvas — the panel window never resizes
        static let canvasWidth: CGFloat  = 700
        static let canvasHeight: CGFloat = 340   // expanded + shadow headroom

        // Collapsed notch dimensions
        static let collapsedWidth: CGFloat  = 250   // approx MacBook notch width
        static let collapsedHeight: CGFloat = 38    // fallback; overwritten from screen at launch

        // Expanded panel dimensions
        static let expandedWidth: CGFloat  = 420
        static let expandedHeight: CGFloat = 260

        // Corner radii
        static let cornerRadiusCollapsed: CGFloat = 8    // bottom inner corners, collapsed
        static let cornerRadiusExpanded: CGFloat  = 20   // bottom inner corners, expanded
        static let outerCornerRadius: CGFloat     = 8    // top outer corners (screen bezel join)
    }

    enum Animation {
        static let expandResponse:   Double = 0.35
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
