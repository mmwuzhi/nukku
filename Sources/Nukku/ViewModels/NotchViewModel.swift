import SwiftUI
import Observation

enum NotchState: Equatable {
    case collapsed
    case expanded
}

@Observable
@MainActor
final class NotchViewModel {
    var state: NotchState = .collapsed
    var activeWidgetID: String? = nil

    // Set once at launch from screen.safeAreaInsets.top; never animated
    var collapsedHeight: CGFloat = Constants.Notch.collapsedHeight

    var isExpanded: Bool { state == .expanded }

    // Rect for hitTest in hosting-view coordinates (y-down, origin top-left)
    var targetInteractiveSize: CGSize {
        isExpanded
            ? CGSize(width: Constants.Notch.expandedWidth, height: Constants.Notch.expandedHeight)
            : CGSize(width: Constants.Notch.collapsedWidth, height: collapsedHeight)
    }

    private var collapseTask: Task<Void, Never>?

    // MARK: - Expand / Collapse

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        if activeWidgetID == nil {
            activeWidgetID = WidgetRegistry.shared.enabledWidgets.first?.id
        }
        activateCurrentWidget()
        state = .expanded
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(Constants.Animation.collapseDelay))
            guard !Task.isCancelled else { return }
            deactivateCurrentWidget()
            state = .collapsed
        }
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
        WidgetRegistry.shared.widgets.first(where: { $0.id == id })?.activate()
    }

    private func deactivateCurrentWidget() {
        guard let id = activeWidgetID else { return }
        WidgetRegistry.shared.widgets.first(where: { $0.id == id })?.deactivate()
    }
}
