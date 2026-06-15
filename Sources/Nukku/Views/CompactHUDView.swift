import SwiftUI

/// Volume / brightness / battery readout shown inside the resting notch
/// silhouette, styled like the collapsed now-playing shelves: the glyph takes
/// the left shoulder (where artwork sits), a ring-gauge percentage takes the
/// right shoulder (where the transport control sits). No expansion, no separate
/// progress strip below the pill.
struct CompactHUDView: View {
    @Environment(NotchViewModel.self) private var notchVM
    let hud: HUDType

    var body: some View {
        let width = Constants.Geometry.rest.bodyWidth
        let minShelfWidth: CGFloat = 32
        let gapWidth = min(notchVM.collapsedWidth, width - minShelfWidth * 2)
        let shelfWidth = max(minShelfWidth, (width - gapWidth) / 2)
        let h = Constants.Geometry.rest.height

        HStack(spacing: 0) {
            Image(systemName: hud.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: shelfWidth, height: h, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: gapWidth)

            rightContent
                .frame(width: 34, height: h, alignment: .center)
                .frame(width: shelfWidth, height: h, alignment: .trailing)
        }
        .frame(width: width, height: h, alignment: .center)
    }

    @ViewBuilder
    private var rightContent: some View {
        if hud.isMuted {
            // The slashed speaker glyph already says it; keep the shoulder quiet.
            Color.clear
        } else {
            RingGauge(level: hud.level, accent: hud.usesAccentFill)
        }
    }
}

/// Thin circular percentage with the value centered inside.
private struct RingGauge: View {
    let level: Float
    let accent: Bool

    private var clamped: CGFloat { CGFloat(max(0, min(1, level))) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    accent ? Color.nukkuAccent : .white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(NotchAnimator.hudTransition, value: clamped)

            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }
}
