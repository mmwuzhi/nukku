import SwiftUI

/// Rest-state shelves shown in the always-visible fused notch pill.
///
/// The center intentionally stays empty for the physical camera cutout; media
/// lives on the two shoulders: artwork on the left, subtle EQ on the right.
struct CollapsedView: View {
    @Environment(MediaViewModel.self) private var mediaVM
    @Environment(NotchViewModel.self) private var notchVM
    @Environment(\.notchNamespace) private var notchNS

    var body: some View {
        let width = Constants.Geometry.rest.bodyWidth
        let minShelfWidth: CGFloat = 32
        let gapWidth = min(notchVM.collapsedWidth, width - minShelfWidth * 2)
        let shelfWidth = max(minShelfWidth, (width - gapWidth) / 2)

        HStack(spacing: 0) {
            leftShelf
                .frame(width: shelfWidth, height: Constants.Geometry.rest.height, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: gapWidth)

            rightShelf
                .frame(width: shelfWidth, height: Constants.Geometry.rest.height, alignment: .trailing)
        }
        .frame(
            width: width,
            height: Constants.Geometry.rest.height,
            alignment: .center
        )
    }

    @ViewBuilder
    private var leftShelf: some View {
        if let artwork = mediaVM.albumArtwork, mediaVM.hasMediaSession {
            Button {
                mediaVM.activateSourceApp()
            } label: {
                if let ns = notchNS {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .matchedGeometryEffect(id: "albumArt", in: ns, isSource: !notchVM.isExpanded)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var rightShelf: some View {
        if mediaVM.hasMediaSession {
            Button {
                mediaVM.togglePlayPause()
            } label: {
                rightShelfContent
                    .frame(width: 32, height: Constants.Geometry.rest.height, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 18, height: 14)
        }
    }

    @ViewBuilder
    private var rightShelfContent: some View {
        if mediaVM.isPlaying && !mediaVM.isHoveringTransportControl {
            MusicEQVisualizer(barCount: 4)
                .frame(width: 18, height: 14)
                .foregroundStyle(Color.nukkuAccent)
        } else {
            Image(systemName: mediaVM.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: mediaVM.isPlaying ? 15 : 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// EQ visualizer with independent per-bar random animation.
struct MusicEQVisualizer: View {
    var barCount: Int = 7
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 7)
    // @State preserves the publisher across re-renders, avoiding timer restarts.
    @State private var ticker = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .frame(width: 1.5, height: heights[i])
                    .animation(
                        .easeInOut(duration: 0.10 + Double(i % 3) * 0.02),
                        value: heights[i]
                    )
            }
        }
        .onReceive(ticker) { _ in
            if heights.count != barCount {
                heights = Array(repeating: 4, count: barCount)
            }
            for i in 0..<barCount { heights[i] = .random(in: 3...14) }
        }
    }
}
