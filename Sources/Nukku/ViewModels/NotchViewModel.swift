import SwiftUI
import Observation

enum NotchState {
    case collapsed
    case expanded
}

@Observable
@MainActor
final class NotchViewModel {
    var state: NotchState = .collapsed
    var activeWidgetID: String? = nil
    var notchWidth: CGFloat = Constants.Notch.defaultWidth
    var notchHeight: CGFloat = Constants.Notch.defaultHeight

    var isExpanded: Bool { state == .expanded }

    var currentCornerRadius: CGFloat {
        state == .expanded ? Constants.Notch.cornerRadiusExpanded : Constants.Notch.cornerRadiusCollapsed
    }

    private var collapseTask: Task<Void, Never>?

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        withAnimation(NotchAnimator.expandSpring) {
            state = .expanded
            notchWidth = Constants.Notch.expandedWidth
            notchHeight = Constants.Notch.expandedHeight
        }
        if activeWidgetID == nil {
            activeWidgetID = WidgetRegistry.shared.enabledWidgets.first?.id
        }
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(Constants.Animation.collapseDelay))
            guard !Task.isCancelled else { return }
            withAnimation(NotchAnimator.collapseSpring) {
                state = .collapsed
                notchWidth = Constants.Notch.defaultWidth
                notchHeight = Constants.Notch.defaultHeight
            }
        }
    }
}
