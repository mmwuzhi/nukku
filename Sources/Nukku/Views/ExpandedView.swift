import SwiftUI

struct ExpandedView: View {
    @Environment(NotchViewModel.self) private var viewModel

    var body: some View {
        let registry = WidgetRegistry.shared
        VStack(spacing: 0) {
            // Widget tab bar
            HStack(spacing: 20) {
                ForEach(registry.enabledWidgets, id: \.id) { widget in
                    Button {
                        withAnimation(NotchAnimator.widgetSwitch) {
                            viewModel.activeWidgetID = widget.id
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

            // Active widget content
            if let activeID = viewModel.activeWidgetID,
               let widget = registry.enabledWidgets.first(where: { $0.id == activeID }) {
                widget.makeBody()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Constants.Widget.defaultPadding)
                    .id(activeID)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            } else {
                Spacer()
            }
        }
    }
}
