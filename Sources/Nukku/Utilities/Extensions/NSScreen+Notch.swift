import AppKit

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// Exact notch width derived from the menu-bar flanking areas.
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the menu-bar segments
    /// to the left and right of the notch; what remains is the notch itself.
    var notchWidth: CGFloat {
        guard hasNotch else { return 0 }
        let left  = auxiliaryTopLeftArea?.width  ?? 0
        let right = auxiliaryTopRightArea?.width ?? 0
        return frame.width - left - right
    }

    var notchRect: CGRect {
        guard hasNotch else { return .zero }
        return CGRect(
            x: frame.midX - notchWidth / 2,
            y: frame.maxY - safeAreaInsets.top,
            width:  notchWidth,
            height: safeAreaInsets.top
        )
    }

    var menuBarLeadingWidth: CGFloat {
        hasNotch ? notchRect.minX - frame.minX : frame.width / 2
    }

    var menuBarTrailingWidth: CGFloat {
        hasNotch ? frame.maxX - notchRect.maxX : frame.width / 2
    }
}
