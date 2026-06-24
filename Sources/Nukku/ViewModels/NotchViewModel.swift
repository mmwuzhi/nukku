import SwiftUI
import Observation

enum NotchState: Equatable {
    case collapsed
    case expanded
}

enum NotchPresentationMode: Equatable {
    case rest
    case open
    case hud     // wide pill — notifications (need room for text)
    case lock    // resting silhouette — lock glyph
    case level   // resting silhouette — volume / brightness / battery readout
}

@Observable
@MainActor
final class NotchViewModel {
    var state: NotchState = .collapsed
    var activeWidgetID: String? = nil

    /// While true, hover-out must not auto-collapse the panel. Modal-style widget
    /// surfaces (the calendar event editor, its date/calendar popovers, the
    /// calendar filter) set this: those popovers are separate windows *outside*
    /// the notch silhouette, so without this, moving the cursor onto a popover
    /// option reads as "left the notch" and collapses the panel mid-interaction.
    /// Only the delayed hover-collapse honors it; explicit dismissals
    /// (`forceCollapse`) still work.
    var suppressAutoCollapse: Bool = false

    // Set once at launch from screen geometry; never animated
    var collapsedHeight: CGFloat = Constants.Notch.collapsedHeight
    var collapsedWidth:  CGFloat = Constants.Notch.collapsedWidth

    var isExpanded: Bool { state == .expanded }

    /// HUD view-model is set externally so `currentMetrics` can resolve HUD
    /// dimensions. Weak so neither side owns the other.
    @ObservationIgnored
    weak var hudViewModel: HUDViewModel?

    /// Media view-model is set externally so the resting silhouette can shrink to
    /// the bare hardware notch when nothing is playing. Weak — no ownership.
    @ObservationIgnored
    weak var mediaViewModel: MediaViewModel?

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
        if let hud = hudViewModel?.currentHUD, !isExpanded {
            // Only notifications need the wider pill. Lock and the level readouts
            // (volume/brightness/battery) stay inside the resting silhouette,
            // styled like the collapsed now-playing shelves.
            if hud.isLock { return .lock }
            if hud.isNotification { return .hud }
            return .level
        }
        return isExpanded ? .open : .rest
    }

    /// Fused-shape metrics for the current presentation mode. Single source of
    /// truth for SwiftUI rendering and AppKit hover/click gating.
    var currentMetrics: Constants.Geometry.StateMetrics {
        switch presentationMode {
        case .rest:
            // With nothing playing, the shoulders carry no content — collapse the
            // silhouette to the bare hardware notch so it reads as invisible black
            // instead of a wider pill bleeding past the cutout.
            return mediaViewModel?.hasMediaSession == true ? Constants.Geometry.rest : bareNotchMetrics
        case .open: return Constants.Geometry.open(height: targetExpandedHeight)
        case .hud:  return Constants.Geometry.hud
        case .lock, .level: return Constants.Geometry.rest   // same silhouette as rest — no expansion
        }
    }

    /// Resting silhouette sized to the physical notch — no shoulders. Keeps the
    /// `rest` melt aesthetic (slight inward bottom curl) but scaled so its top edge
    /// matches the hardware cutout, making it blend invisibly when idle.
    private var bareNotchMetrics: Constants.Geometry.StateMetrics {
        var m = Constants.Geometry.rest
        let shoulder = m.topWidth - m.bodyWidth
        m.topWidth  = collapsedWidth
        m.bodyWidth = collapsedWidth - shoulder
        m.height    = collapsedHeight
        return m
    }

    // Bounding rect for hitTest in hosting-view coordinates (y-down, origin top-left).
    // The visible silhouette is `topWidth` wide at y=0 and `bodyWidth` below the
    // melt cove — `topWidth` is the bounding width.
    var targetInteractiveSize: CGSize {
        let m = currentMetrics
        return CGSize(width: max(m.topWidth, m.bodyWidth), height: m.height)
    }

    /// Fired when the panel crosses the expanded/collapsed boundary. The window
    /// manager uses it to take key-window status while expanded (so the cursor is
    /// owned by the notch, not the app behind it) and hand focus back on collapse.
    @ObservationIgnored
    var onExpandedChange: ((Bool) -> Void)?

    private var collapseTask: Task<Void, Never>?
    private var hoverEnterTask: Task<Void, Never>?

    // MARK: - Expand / Collapse

    func expand() {
        // Do not reveal widgets above the secure lock screen.
        guard hudViewModel?.isScreenLocked != true else { return }
        collapseTask?.cancel()
        collapseTask = nil
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        // Mouse tracking can request expansion again when the cursor returns from
        // a popover. Keep that request idempotent: an active modal suppression lock
        // belongs to the current expanded session and must survive re-entry.
        guard !isExpanded else { return }
        if activeWidgetID == nil {
            activeWidgetID = WidgetRegistry.shared.enabledWidgets.first?.id
        }
        activateCurrentWidget()
        suppressAutoCollapse = false
        state = .expanded
        onExpandedChange?(true)
    }

    /// Schedule expand after a short dwell — masks accidental cursor crossings.
    /// Called from hover-enter; balanced by cancelHoverEnter on hover-exit.
    func scheduleHoverExpand() {
        guard hudViewModel?.isScreenLocked != true else { return }
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
        // A modal-style surface (event editor / open popover) is mid-interaction
        // outside the silhouette; do not auto-collapse out from under it.
        guard !suppressAutoCollapse else { return }
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        collapseTask?.cancel()
        let delay = PreferencesManager.shared.collapseDelay
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            // Suppression may become active after this task was queued (for
            // example, opening a popover during the collapse delay).
            guard !Task.isCancelled, !suppressAutoCollapse else { return }
            deactivateCurrentWidget()
            state = .collapsed
            onExpandedChange?(false)
        }
    }

    /// Immediate collapse — used by click-toggle mode and HUD dismiss.
    func forceCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        // Explicit dismissal always clears the modal lock so it can't get stuck.
        suppressAutoCollapse = false
        deactivateCurrentWidget()
        state = .collapsed
        onExpandedChange?(false)
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
