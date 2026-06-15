import SwiftUI

/// Screen-lock / unlock indicator shown inside the resting notch silhouette.
///
/// Deliberately reuses the collapsed shelf geometry so the pill never grows: a
/// single lock glyph sits on the left shoulder (the same slot now-playing
/// artwork uses), the center stays clear for the camera, and the right shoulder
/// is empty. Quiet status, no expansion.
struct LockView: View {
    @Environment(NotchViewModel.self) private var notchVM
    @Environment(HUDViewModel.self)   private var hudVM

    private var isLocked: Bool {
        if case .lock(let locked) = hudVM.currentHUD { return locked }
        return true
    }

    var body: some View {
        let width = Constants.Geometry.rest.bodyWidth
        let minShelfWidth: CGFloat = 32
        let gapWidth = min(notchVM.collapsedWidth, width - minShelfWidth * 2)
        let shelfWidth = max(minShelfWidth, (width - gapWidth) / 2)

        HStack(spacing: 0) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: shelfWidth, height: Constants.Geometry.rest.height, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: gapWidth)

            Color.clear
                .frame(width: shelfWidth, height: Constants.Geometry.rest.height)
        }
        .frame(
            width: width,
            height: Constants.Geometry.rest.height,
            alignment: .center
        )
    }
}
