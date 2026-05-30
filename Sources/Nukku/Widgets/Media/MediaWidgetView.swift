import SwiftUI
import AppKit

struct MediaWidgetView: View {
    @Environment(MediaViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 12) {
            // Album artwork
            Group {
                if let image = vm.albumArtwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(Color.nukkuSurface, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(vm.nowPlayingTitle ?? "未在播放")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(vm.nowPlayingArtist ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * vm.progress, height: 3)
                    }
                }
                .frame(height: 3)

                // Controls
                HStack(spacing: 24) {
                    Button { vm.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                    }
                    Button { vm.togglePlayPause() } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                    }
                    Button { vm.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                    }
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
        }
    }
}
