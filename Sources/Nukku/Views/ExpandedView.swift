import AppKit
import SwiftUI

struct ExpandedView: View {
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let registry = WidgetRegistry.shared
        VStack(spacing: 0) {
            // ── Widget tab bar ──
            // Push below the hardware notch — `vm.collapsedHeight` is the safeAreaInsets.top
            // read at startup so this adapts across MBP models / non-notch screens.
            HStack(spacing: 0) {
                ForEach(Array(registry.enabledWidgets.enumerated()), id: \.element.id) { index, widget in
                    if index > 0 { Spacer(minLength: 0) }
                    TabTile(
                        widget: widget,
                        isActive: viewModel.activeWidgetID == widget.id
                    ) {
                        withAnimation(NotchAnimator.widgetSwitch) {
                            viewModel.setActive(widget.id)
                        }
                    }
                }
                Spacer(minLength: 8)
                // The notch is the app's only surface and it runs as a menu-less
                // accessory, so this gear is the sole entry to the Settings scene.
                // Activate first so the window comes to the front of the inactive app.
                SettingsTile {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, viewModel.collapsedHeight + 2)
            .padding(.bottom, 7)
            .padding(.horizontal, 18)

            Divider()
                .background(Color.nukkuSeparator)
                .padding(.horizontal, 16)

            // ── Active widget content ──
            if let activeID = viewModel.activeWidgetID,
               let widget = registry.enabledWidgets.first(where: { $0.id == activeID }) {
                widget.makeBody()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Constants.Widget.defaultPadding)
                    .id(activeID)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal:   .opacity.combined(with: .move(edge: .leading))
                    ))
            } else {
                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(NotchAnimator.widgetSwitch) {
                        if value.translation.width < 0 {
                            if let next = registry.nextEnabledID(after: viewModel.activeWidgetID) {
                                viewModel.setActive(next)
                            }
                        } else {
                            if let prev = registry.prevEnabledID(before: viewModel.activeWidgetID) {
                                viewModel.setActive(prev)
                            }
                        }
                    }
                }
        )
    }
}

// MARK: - Tab tile (Apple Control Center style)

private struct TabTile: View {
    let widget: AnyNukkuWidgetBox
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: widget.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? widget.accentColor : Color.nukkuInactiveTab)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.nukkuActiveTabFill)
                        .opacity(isActive ? 1 : 0)
                )
                .scaleEffect(isActive ? 1.0 : 0.92)
                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(widget.displayName)
    }
}

// MARK: - Settings tile

private struct SettingsTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.nukkuInactiveTab)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("偏好设置")
    }
}
