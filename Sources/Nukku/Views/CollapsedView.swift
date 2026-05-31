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
                MusicWaveIndicator()
                    .frame(width: 14, height: 14)
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

// Animated bars indicating music playback
struct MusicWaveIndicator: View {
    @State private var phase = false

    private let barCount = 3
    private let barHeights: [CGFloat] = [0.5, 1.0, 0.7]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: phase ? barHeights[i] * 14 : 4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.1),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
