import SwiftUI

struct NotchContainerView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(MediaViewModel.self) private var mediaVM

    // ── Geometry derived from state (View owns the geometry, ViewModel doesn't) ──
    private var targetWidth:  CGFloat { vm.isExpanded ? Constants.Notch.expandedWidth  : Constants.Notch.collapsedWidth }
    private var targetHeight: CGFloat { vm.isExpanded ? Constants.Notch.expandedHeight : vm.collapsedHeight }
    private var bottomRadius: CGFloat { vm.isExpanded ? Constants.Notch.cornerRadiusExpanded : Constants.Notch.cornerRadiusCollapsed }

    // ── Spring selection ──
    private var shapeSpring: Animation { vm.isExpanded ? NotchAnimator.expand : NotchAnimator.collapse }

    var body: some View {
        ZStack(alignment: .top) {

            // ── 1. Notch silhouette ──
            currentShape
                .fill(Color.black)
                // Shadow appears only when expanded
                .shadow(
                    color: .black.opacity(vm.isExpanded ? 0.30 : 0),
                    radius: 16, y: 8
                )
                .animation(shapeSpring, value: vm.state)

            // ── 2. Content layer (clipped to notch shape) ──
            ZStack {
                // Collapsed content: visible when collapsed, hidden instantly when expanding
                CollapsedView()
                    .environment(mediaVM)
                    .opacity(vm.isExpanded ? 0 : 1)
                    .animation(
                        vm.isExpanded
                            ? NotchAnimator.contentHide               // snap out on expand
                            : NotchAnimator.contentReveal.delay(0.15), // wait for shape to close
                        value: vm.state
                    )

                // Expanded content: hidden when collapsed, fades in after shape starts opening
                ExpandedView()
                    .opacity(vm.isExpanded ? 1 : 0)
                    .animation(
                        vm.isExpanded
                            ? NotchAnimator.contentReveal.delay(0.08)  // let shape open first
                            : NotchAnimator.contentHide,               // snap out on collapse
                        value: vm.state
                    )
            }
            .frame(width: targetWidth, height: targetHeight)
            .clipShape(currentShape)
            .animation(shapeSpring, value: vm.state)
        }
        // Fixed canvas frame — the window NEVER resizes
        .frame(
            width:  Constants.Notch.canvasWidth,
            height: Constants.Notch.canvasHeight,
            alignment: .top
        )
        // Hover area tracks the animated notch shape exactly
        .contentShape(currentShape)
        .onHover { hovering in
            if hovering { vm.expand() } else { vm.collapse() }
        }
    }

    // Single source of truth for shape parameters
    private var currentShape: NotchShape {
        NotchShape(
            width:        targetWidth,
            height:       targetHeight,
            topRadius:    Constants.Notch.outerCornerRadius,
            bottomRadius: bottomRadius
        )
    }
}
