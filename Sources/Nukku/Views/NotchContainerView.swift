import SwiftUI

struct NotchContainerView: View {
    @Environment(NotchViewModel.self)  private var vm
    @Environment(MediaViewModel.self)  private var mediaVM
    @Environment(HUDViewModel.self)    private var hudVM
    @Namespace private var notchNS

    // @AppStorage is reactive directly in the view — avoids the @ObservationIgnored issue
    // in PreferencesManager which would freeze the branch at first render.
    @AppStorage("expandTrigger") private var expandTriggerRaw: String = ExpandTrigger.hover.rawValue
    private var expandTrigger: ExpandTrigger { ExpandTrigger(rawValue: expandTriggerRaw) ?? .hover }

    // ── Geometry derived from state ──
    private var isHUDActive: Bool { !vm.isExpanded && hudVM.currentHUD != nil }
    private var targetWidth: CGFloat {
        if isHUDActive { return Constants.Notch.hudWidth }
        return vm.isExpanded ? Constants.Notch.expandedWidth : vm.collapsedWidth
    }
    private var targetHeight: CGFloat {
        vm.isExpanded ? Constants.Notch.expandedHeight : vm.collapsedHeight
    }
    private var bottomRadius: CGFloat {
        vm.isExpanded ? Constants.Notch.cornerRadiusExpanded : Constants.Notch.cornerRadiusCollapsed
    }
    private var shapeSpring: Animation {
        vm.isExpanded ? NotchAnimator.expand : NotchAnimator.collapse
    }

    var body: some View {
        ZStack(alignment: .top) {

            // ── 1. Notch silhouette ──
            currentShape
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(vm.isExpanded ? 0.30 : 0),
                    radius: 16, y: 8
                )
                .animation(shapeSpring, value: vm.state)
                .animation(NotchAnimator.hudTransition, value: isHUDActive)

            // ── 1b. Liquid Glass layer (macOS 26, visible when expanded) ──
            Color.clear
                .frame(width: targetWidth, height: targetHeight)
                .glassEffect(.regular)
                .clipShape(currentShape)
                .opacity(vm.isExpanded ? 1 : 0)
                .animation(shapeSpring, value: vm.state)
                .animation(NotchAnimator.hudTransition, value: isHUDActive)

            // ── 2. Content layer ──
            ZStack {
                // HUD overlay (collapsed only)
                if let hud = hudVM.currentHUD, !vm.isExpanded {
                    HUDView(hud: hud)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Collapsed media/clock content
                CollapsedView()
                    .environment(mediaVM)
                    .opacity(vm.isExpanded || isHUDActive ? 0 : 1)
                    // Two separate animation drivers: one for expand/collapse, one for HUD crossfade
                    .animation(
                        vm.isExpanded ? NotchAnimator.contentHide : NotchAnimator.contentReveal.delay(0.15),
                        value: vm.state
                    )
                    .animation(NotchAnimator.contentHide, value: isHUDActive)

                // Expanded panel content
                ExpandedView()
                    .opacity(vm.isExpanded ? 1 : 0)
                    .animation(
                        vm.isExpanded
                            ? NotchAnimator.contentReveal.delay(0.08)
                            : NotchAnimator.contentHide,
                        value: vm.state
                    )
            }
            .frame(width: targetWidth, height: targetHeight)
            .clipShape(currentShape)
            .environment(\.notchNamespace, notchNS)
            .animation(shapeSpring, value: vm.state)
            .animation(NotchAnimator.hudTransition, value: isHUDActive)
        }
        .frame(
            width:  Constants.Notch.canvasWidth,
            height: Constants.Notch.canvasHeight,
            alignment: .top
        )
        .contentShape(currentShape)
        // Pass expandTrigger as a value so the modifier re-evaluates when the user changes it
        .modifier(NotchInteractionModifier(vm: vm, trigger: expandTrigger))
        .animation(NotchAnimator.hudTransition, value: hudVM.currentHUD != nil)
    }

    private var currentShape: NotchShape {
        NotchShape(
            width:        targetWidth,
            height:       targetHeight,
            topRadius:    Constants.Notch.outerCornerRadius,
            bottomRadius: bottomRadius
        )
    }
}

// MARK: - Interaction modifier (hover vs click)

private struct NotchInteractionModifier: ViewModifier {
    let vm: NotchViewModel
    let trigger: ExpandTrigger  // value type — parent re-creates modifier when setting changes

    func body(content: Content) -> some View {
        if trigger == .hover {
            content
                .onHover { hovering in
                    if hovering { vm.expand() } else { vm.collapse() }
                }
        } else {
            content
                .onTapGesture {
                    if vm.isExpanded { vm.forceCollapse() } else { vm.expand() }
                }
        }
    }
}
