import CoreGraphics

enum Constants {
    enum Notch {
        static let defaultWidth: CGFloat = 272
        static let defaultHeight: CGFloat = 32
        static let expandedWidth: CGFloat = 400
        static let expandedHeight: CGFloat = 260
        static let cornerRadiusCollapsed: CGFloat = 8
        static let cornerRadiusExpanded: CGFloat = 20
        static let outerCornerRadius: CGFloat = 8
    }

    enum Animation {
        static let expandResponse: Double = 0.4
        static let expandDamping: Double = 0.72
        static let collapseResponse: Double = 0.3
        static let collapseDamping: Double = 0.85
        static let collapseDelay: Double = 0.3
    }

    enum Widget {
        static let minSize = CGSize(width: 120, height: 80)
        static let defaultPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 12
    }
}
