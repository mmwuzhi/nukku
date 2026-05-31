import SwiftUI

struct CollapsedView: View {
    @Environment(MediaViewModel.self)  private var mediaVM
    @Environment(NotchViewModel.self)  private var vm
    @Environment(\.notchNamespace)     private var notchNS

    var body: some View {
        HStack(spacing: 6) {
            if let artwork = mediaVM.albumArtwork, mediaVM.isPlaying, let ns = notchNS {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .matchedGeometryEffect(id: "albumArt", in: ns, isSource: !vm.isExpanded)
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
            }

            if mediaVM.isPlaying {
                MusicEQVisualizer()
                    .frame(width: 18, height: 14)
                    .foregroundStyle(.white)
            }
            if let title = mediaVM.nowPlayingTitle {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
            }
        }
        .padding(.horizontal, 12)
    }
}

// 7-bar EQ visualizer with independent per-bar random animation.
struct MusicEQVisualizer: View {
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 7)
    // @State preserves the publisher across re-renders, avoiding timer restarts.
    @State private var ticker = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<7, id: \.self) { i in
                Capsule()
                    .frame(width: 1.5, height: heights[i])
                    .animation(
                        .easeInOut(duration: 0.10 + Double(i % 3) * 0.02),
                        value: heights[i]
                    )
            }
        }
        .onReceive(ticker) { _ in
            for i in 0..<7 { heights[i] = .random(in: 3...14) }
        }
    }
}
