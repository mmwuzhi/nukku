import SwiftUI

// Concrete type-erased widget box stored in the registry.
// Using a class so updates to isEnabled propagate via @Observable.
@Observable
@MainActor
final class AnyNukkuWidgetBox: Identifiable {
    let id: String
    let displayName: String
    let iconName: String
    let accentColor: Color
    let preferredSize: CGSize
    var isEnabled: Bool

    private let _makeBody: @MainActor () -> AnyView
    private let _activate: @MainActor () -> Void
    private let _deactivate: @MainActor () -> Void

    init(
        id: String,
        displayName: String,
        iconName: String,
        accentColor: Color,
        preferredSize: CGSize,
        isEnabled: Bool,
        makeBody: @escaping @MainActor () -> AnyView,
        activate: @escaping @MainActor () -> Void,
        deactivate: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.displayName = displayName
        self.iconName = iconName
        self.accentColor = accentColor
        self.preferredSize = preferredSize
        self.isEnabled = isEnabled
        self._makeBody = makeBody
        self._activate = activate
        self._deactivate = deactivate
    }

    func makeBody() -> AnyView { _makeBody() }
    func activate() { _activate() }
    func deactivate() { _deactivate() }
}

// Helper to build a box from a concrete widget object (class conforming to this informal pattern).
// Widgets don't need to adopt a protocol — just use this factory function.
@MainActor
func makeWidgetBox<V: View>(
    id: String,
    displayName: String,
    iconName: String,
    accentColor: Color,
    preferredSize: CGSize = CGSize(width: 360, height: 180),
    isEnabled: Bool = true,
    activate: @escaping @MainActor () -> Void = {},
    deactivate: @escaping @MainActor () -> Void = {},
    @ViewBuilder body: @escaping @MainActor () -> V
) -> AnyNukkuWidgetBox {
    AnyNukkuWidgetBox(
        id: id,
        displayName: displayName,
        iconName: iconName,
        accentColor: accentColor,
        preferredSize: preferredSize,
        isEnabled: isEnabled,
        makeBody: { AnyView(body()) },
        activate: activate,
        deactivate: deactivate
    )}
