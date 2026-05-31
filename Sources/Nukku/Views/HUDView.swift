import SwiftUI

/// Slim HUD shown inside the collapsed notch.
/// Vol/brightness: icon + progress bar (320 × 28 pt).
/// Notification: app icon + title text.
struct HUDView: View {
    let hud: HUDType

    var body: some View {
        if case .notification(let appName, let title, let icon) = hud {
            notificationLayout(appName: appName, title: title, icon: icon)
        } else {
            progressLayout
        }
    }

    // MARK: - Vol / Brightness layout

    private var progressLayout: some View {
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

    // MARK: - Notification layout

    private func notificationLayout(appName: String, title: String, icon: NSImage?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(title.isEmpty ? appName : title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(width: Constants.Notch.hudWidth, height: 28)
    }
}
