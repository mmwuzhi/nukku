import SwiftUI
import Observation

enum NotchState: Equatable {
    case collapsed
    case expanded
}

enum NotchPresentationMode: Equatable {
    case rest
    case open
    case hud
}

@Observable
@MainActor
final class NotchViewModel {
    var state: NotchState = .collapsed
    var activeWidgetID: String? = nil

    // Set once at launch from screen geometry; never animated
    var collapsedHeight: CGFloat = Constants.Notch.collapsedHeight
    var collapsedWidth:  CGFloat = Constants.Notch.collapsedWidth

    var isExpanded: Bool { state == .expanded }

    /// HUD view-model is set externally so `currentMetrics` can resolve HUD
    /// dimensions. Weak so neither side owns the other.
    @ObservationIgnored
    weak var hudViewModel: HUDViewModel?

    /// Expanded panel height. Media follows Claude Design's compact open model;
    /// other widgets keep enough vertical room for their preferred content.
    var targetExpandedHeight: CGFloat {
        if activeWidgetID == "media" {
            return Constants.Geometry.openBase.height
        }
        let chrome: CGFloat = collapsedHeight + 65
        if let id = activeWidgetID,
           let widget = WidgetRegistry.shared.widgets.first(where: { $0.id == id }) {
            return max(Constants.Geometry.openBase.height, chrome + widget.preferredSize.height)
        }
        return Constants.Geometry.openBase.height
    }

    /// Single presentation state for both shape and content. Normal HUDs own
    /// the surface when collapsed, otherwise the notch state decides rest/open.
    var presentationMode: NotchPresentationMode {
        if hudViewModel?.currentHUD != nil && !isExpanded { return .hud }
        return isExpanded ? .open : .rest
    }

    /// Fused-shape metrics for the current presentation mode. Single source of
    /// truth for SwiftUI rendering and AppKit hover/click gating.
    var currentMetrics: Constants.Geometry.StateMetrics {
        switch presentationMode {
        case .rest: return Constants.Geometry.rest
        case .open: return Constants.Geometry.open(height: targetExpandedHeight)
        case .hud:  return Constants.Geometry.hud
        }
    }

    // Bounding rect for hitTest in hosting-view coordinates (y-down, origin top-left).
    // The visible silhouette is `topWidth` wide at y=0 and `bodyWidth` below the
    // melt cove — `topWidth` is the bounding width.
    var targetInteractiveSize: CGSize {
        let m = currentMetrics
        return CGSize(width: max(m.topWidth, m.bodyWidth), height: m.height)
    }

    private var collapseTask: Task<Void, Never>?
    private var hoverEnterTask: Task<Void, Never>?

    // MARK: - Expand / Collapse

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        if activeWidgetID == nil {
            activeWidgetID = WidgetRegistry.shared.enabledWidgets.first?.id
        }
        activateCurrentWidget()
        state = .expanded
    }

    /// Schedule expand after a short dwell — masks accidental cursor crossings.
    /// Called from hover-enter; balanced by cancelHoverEnter on hover-exit.
    func scheduleHoverExpand() {
        hoverEnterTask?.cancel()
        hoverEnterTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Notch.hoverDwellSeconds))
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    func cancelHoverExpand() {
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
    }

    /// Delayed collapse — respects user's collapseDelay preference.
    func collapse() {
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        collapseTask?.cancel()
        let delay = PreferencesManager.shared.collapseDelay
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            deactivateCurrentWidget()
            state = .collapsed
        }
    }

    /// Immediate collapse — used by click-toggle mode and HUD dismiss.
    func forceCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        deactivateCurrentWidget()
        state = .collapsed
    }

    // MARK: - Widget Lifecycle

    func setActive(_ id: String) {
        guard id != activeWidgetID else { return }
        deactivateCurrentWidget()
        activeWidgetID = id
        activateCurrentWidget()
    }

    private func activateCurrentWidget() {
        guard let id = activeWidgetID else { return }
        // Only activate enabled widgets; a disabled widget must not start background work
        WidgetRegistry.shared.enabledWidgets.first(where: { $0.id == id })?.activate()
    }

    private func deactivateCurrentWidget() {
        guard let id = activeWidgetID else { return }
        // Search all widgets so we can deactivate one that was just disabled mid-session
        WidgetRegistry.shared.widgets.first(where: { $0.id == id })?.deactivate()
    }
}
