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
    private var currentMetrics: Constants.Geometry.StateMetrics { vm.currentMetrics }
    private var presentationMode: NotchPresentationMode { vm.presentationMode }
    private var targetWidth: CGFloat {
        max(currentMetrics.topWidth, currentMetrics.bodyWidth)
    }
    private var targetHeight: CGFloat { currentMetrics.height }
    private var shapeSpring: Animation {
        vm.isExpanded ? NotchAnimator.expand : NotchAnimator.collapse
    }
    private var contentAnimation: Animation? {
        switch presentationMode {
        case .lock: return nil   // instant swap — never fade content above the lock screen
        case .open: return NotchAnimator.contentReveal.delay(0.08)
        default:    return NotchAnimator.contentHide
        }
    }

    var body: some View {
        ZStack(alignment: .top) {

            // ── 1. Fused notch silhouette ──
            // Opaque black in every state. Matching the physical camera cutout exactly is
            // what creates the "one solid Dynamic Island" illusion; glass/sheen breaks it.
            currentShape
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(vm.isExpanded ? 0.30 : 0),
                    radius: 14, y: 8
                )
                .animation(shapeSpring, value: vm.state)
                .animation(shapeSpring, value: vm.activeWidgetID)
                .animation(NotchAnimator.hudTransition, value: hudVM.currentHUD)

            // ── 2. Content layer ──
            ZStack {
                switch presentationMode {
                case .rest:
                    CollapsedView()
                        .environment(mediaVM)
                        .transition(.opacity)

                case .hud:
                    if let hud = visibleHUD {
                        HUDView(hud: hud)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                case .lock:
                    LockView()
                        .transition(.opacity)

                case .level:
                    if let hud = visibleHUD {
                        CompactHUDView(hud: hud)
                            .transition(.opacity)
                    }

                case .open:
                    ExpandedView()
                        .transition(.opacity)
                }
            }
            .frame(width: targetWidth, height: targetHeight)
            .clipShape(currentShape)
            .environment(\.notchNamespace, notchNS)
            .animation(contentAnimation, value: presentationMode)
            .animation(shapeSpring, value: vm.state)
            .animation(shapeSpring, value: vm.activeWidgetID)
            // Lock swaps in instantly so no outgoing media/notification view can
            // fade visibly above the secure lock screen; everything else fades.
            .animation(
                hudVM.currentHUD?.isLock == true ? nil : NotchAnimator.hudTransition,
                value: hudVM.currentHUD
            )
        }
        .frame(
            width:  Constants.Notch.canvasWidth,
            height: Constants.Notch.canvasHeight,
            alignment: .top
        )
        // The actual hover hit gate lives in NotchHostingView (AppKit hitTest with
        // interactiveRect provided by NotchWindowManager). contentShape only narrows
        // click hit-testing inside the visible silhouette.
        .contentShape(currentShape)
        .modifier(NotchInteractionModifier(vm: vm, trigger: expandTrigger))
        .animation(NotchAnimator.hudTransition, value: hudVM.currentHUD)
    }

    private var currentShape: NotchShape {
        NotchShape(
            topWidth:     currentMetrics.topWidth,
            bodyWidth:    currentMetrics.bodyWidth,
            height:       currentMetrics.height,
            coveHeight:   currentMetrics.coveHeight,
            bottomRadius: currentMetrics.bottomRadius,
            tension:      Constants.Geometry.tension
        )
    }

    private var visibleHUD: HUDType? {
        hudVM.currentHUD
    }
}

// MARK: - Interaction modifier (hover vs click)

private struct NotchInteractionModifier: ViewModifier {
    let vm: NotchViewModel
    let trigger: ExpandTrigger  // value type — parent re-creates modifier when setting changes

    func body(content: Content) -> some View {
        // Hover is driven by NSTrackingArea inside NotchHostingView — see TrackingHostingView.swift.
        // SwiftUI .onHover is not used because it uses the view's frame (whole canvas) and
        // can't be narrowed by .contentShape.
        if trigger == .click {
            content
                .onTapGesture {
                    if vm.isExpanded { vm.forceCollapse() } else { vm.expand() }
                }
        } else {
            content
        }
    }
}
