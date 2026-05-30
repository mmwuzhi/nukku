import SwiftUI

struct NotchContainerView: View {
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(MediaViewModel.self) private var mediaVM

    var body: some View {
        ZStack(alignment: .top) {
            // Notch shape background
            NotchShape(
                width: viewModel.notchWidth,
                height: viewModel.notchHeight,
                cornerRadius: viewModel.currentCornerRadius
            )
            .fill(Color.nukkuBackground)
            .shadow(color: .black.opacity(0.4), radius: viewModel.isExpanded ? 20 : 0, y: 4)

            // Content layer, clipped to shape
            Group {
                if viewModel.isExpanded {
                    ExpandedView()
                        .transition(.opacity.animation(NotchAnimator.expandSpring))
                } else {
                    CollapsedView()
                        .transition(.opacity.animation(NotchAnimator.collapseSpring))
                }
            }
            .frame(
                width: viewModel.notchWidth,
                height: viewModel.notchHeight
            )
            .clipShape(
                NotchShape(
                    width: viewModel.notchWidth,
                    height: viewModel.notchHeight,
                    cornerRadius: viewModel.currentCornerRadius
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
