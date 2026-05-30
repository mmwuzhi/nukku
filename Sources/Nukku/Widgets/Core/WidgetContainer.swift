import SwiftUI

// Generic rounded-rect container used by all widgets
struct WidgetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Constants.Widget.cornerRadius))
    }
}
