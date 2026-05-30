import SwiftUI

enum ClockWidget {
    @MainActor
    static func box() -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "clock",
            displayName: "时钟",
            iconName: "clock"
        ) {
            ClockWidgetView()
        }
    }
}
