import SwiftUI
import AppKit

struct MediaWidgetView: View {
    @Environment(MediaViewModel.self)  private var vm
    @Environment(NotchViewModel.self)  private var notchVM
    @Environment(\.notchNamespace)     private var notchNS

    private var hasContent: Bool {
        vm.nowPlayingTitle != nil
    }

    private var displayTitle: String {
        if let title = vm.nowPlayingTitle, !title.isEmpty {
            return title
        }
        return "未在播放"
    }

    private var displaySubtitle: String {
        if let artist = vm.nowPlayingArtist, !artist.isEmpty {
            return artist
        }
        if let appName = vm.sourceAppName, !appName.isEmpty {
            return appName
        }
        return "在浏览器或音乐 app 中开始播放"
    }

    var body: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: displayTitle,
                    font: .system(size: 13, weight: .semibold),
                    restartToken: vm.marqueeRestartToken
                )
                .foregroundStyle(.white.opacity(hasContent ? 1.0 : 0.72))
                .frame(height: 18)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(displaySubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(hasContent ? 0.55 : 0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .center)

            playPauseButton
        }
        .frame(height: 50)
        .padding(.horizontal, 8)
    }

    private var playPauseButton: some View {
        Button { vm.togglePlayPause() } label: {
            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.10), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = vm.albumArtwork {
            artworkImage(image)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    @ViewBuilder
    private func artworkImage(_ image: NSImage) -> some View {
        if let ns = notchNS {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .matchedGeometryEffect(id: "albumArt", in: ns, isSource: notchVM.isExpanded)
        } else {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

// MARK: - Marquee scrolling text
//
// Auto-scrolls left when the text overflows the available container width;
// stays static when it fits. Two copies render with a fixed gap so the loop
// is seamless. External `restartToken` bumps make the scroll snap back to
// the start whenever the parent VM wants to re-surface the title.

private struct MarqueeText: View {
    let text: String
    let font: Font
    let restartToken: Int

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let gap: CGFloat = 32
    private let pointsPerSecond: Double = 30
    private let leadInDelay: Double = 0.8

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width + 1
            HStack(spacing: gap) {
                copyOfText.background(widthProbe)
                if needsScroll { copyOfText }
            }
            .offset(x: needsScroll ? offset : 0)
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .task(id: marqueeKey(containerWidth: geo.size.width)) {
                offset = 0
                guard needsScroll, textWidth > 0 else { return }
                try? await Task.sleep(for: .seconds(leadInDelay))
                guard !Task.isCancelled else { return }
                let cycle = textWidth + gap
                withAnimation(.linear(duration: cycle / pointsPerSecond).repeatForever(autoreverses: false)) {
                    offset = -cycle
                }
            }
        }
    }

    private func marqueeKey(containerWidth: CGFloat) -> String {
        "\(text)|\(restartToken)|\(Int(textWidth))|\(Int(containerWidth))"
    }

    private var copyOfText: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
    }

    /// Hidden mirror of the text that measures its intrinsic width via a
    /// GeometryReader behind it. Writes back to `textWidth` so the parent
    /// can decide whether scrolling is needed.
    private var widthProbe: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width, initial: true) { _, w in
                    textWidth = w
                }
        }
    }
}
