import SwiftUI

/// HUD shown in the fused notch pill.
struct HUDView: View {
    let hud: HUDType

    var body: some View {
        if case .notification(let appName, let title, let icon) = hud {
            notificationLayout(appName: appName, title: title, icon: icon)
        } else {
            progressLayout
        }
    }

    // MARK: - Vol / Brightness / Battery layout
    //
    // Pill is 348×64 — top ~38pt is visually fused with the hardware notch,
    // bottom strip carries the actual icon/bar/percent readout.

    private var progressLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: hud.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, alignment: .leading)

                Spacer(minLength: 0)

                if let label = hud.percentLabel {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .frame(height: Constants.Notch.collapsedHeight)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(hud.usesAccentFill ? Color.nukkuAccent : .white.opacity(0.92))
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, hud.level))))
                        .animation(NotchAnimator.hudTransition, value: hud.level)
                }
            }
            .frame(height: 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(
            width: Constants.Geometry.hud.topWidth,
            height: Constants.Geometry.hud.height,
            alignment: .top
        )
    }

    // MARK: - Notification layout

    private func notificationLayout(appName: String, title: String, icon: NSImage?) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title.isEmpty ? appName : title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 22)
        .frame(
            width: Constants.Geometry.hud.topWidth,
            height: Constants.Geometry.hud.height,
            alignment: .bottom
        )
        .padding(.bottom, 7)
    }

}

private extension HUDType {
    var usesAccentFill: Bool {
        if case .brightness = self { return true }
        return false
    }
}
