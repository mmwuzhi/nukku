import SwiftUI

struct ExpandedView: View {
    @Environment(NotchViewModel.self) private var viewModel

    var body: some View {
        let registry = WidgetRegistry.shared
        VStack(spacing: 0) {
            // ── Widget tab bar ──
            HStack(spacing: 20) {
                ForEach(registry.enabledWidgets, id: \.id) { widget in
                    Button {
                        withAnimation(NotchAnimator.widgetSwitch) {
                            viewModel.setActive(widget.id)
                        }
                    } label: {
                        Image(systemName: widget.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(
                                viewModel.activeWidgetID == widget.id ? .white : .secondary
                            )
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

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
