import SwiftUI

/// Slim HUD shown inside the collapsed notch when volume or brightness changes.
/// Designed to fit within hudWidth × collapsedHeight (≈ 320 × 38).
struct HUDView: View {
    let hud: HUDType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hud.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, hud.level))))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .frame(width: Constants.Notch.hudWidth, height: 28)
    }
}
