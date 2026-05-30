import AppKit

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    // Approximate notch rect in screen coordinates (origin bottom-left)
    var notchRect: CGRect {
        guard hasNotch else { return .zero }
        let notchHeight = safeAreaInsets.top
        // Estimate notch width by machine model size (Apple has no public API for exact width)
        let estimatedNotchWidth: CGFloat
        switch frame.width {
        case 3456...: estimatedNotchWidth = 255  // 16" MBP
        case 2560...: estimatedNotchWidth = 270  // 14" MBP
        default:      estimatedNotchWidth = 272
        }
        return CGRect(
            x: frame.midX - estimatedNotchWidth / 2,
            y: frame.maxY - notchHeight,
            width: estimatedNotchWidth,
            height: notchHeight
        )
    }

    var menuBarLeadingWidth: CGFloat {
        hasNotch ? notchRect.minX - frame.minX : frame.width / 2
    }

    var menuBarTrailingWidth: CGFloat {
        hasNotch ? frame.maxX - notchRect.maxX : frame.width / 2
    }
}
