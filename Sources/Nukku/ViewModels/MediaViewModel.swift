import AppKit
import Observation

@Observable
@MainActor
final class MediaViewModel {
    var nowPlayingTitle: String?
    var nowPlayingArtist: String?
    var albumArtwork: NSImage?
    var isPlaying: Bool = false
    var elapsedTime: Double = 0
    var duration: Double = 0

    var progress: Double {
        duration > 0 ? min(elapsedTime / duration, 1.0) : 0
    }

    private let client = MediaRemoteClient.shared
    private var progressTask: Task<Void, Never>?
    private var observerTokens: [NSObjectProtocol] = []

    init() {
        setupNotificationObservers()
        Task { await refresh() }
    }

    private func setupNotificationObservers() {
        let nc = NotificationCenter.default
        observerTokens.append(
            nc.addObserver(forName: MediaRemoteClient.nowPlayingInfoChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
        )
        observerTokens.append(
            nc.addObserver(forName: MediaRemoteClient.isPlayingChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refreshPlayState() }
            }
        )
    }

    func refresh() async {
        let info = await client.fetchNowPlayingInfo()
        nowPlayingTitle = info[MediaRemoteClient.InfoKey.title] as? String
        nowPlayingArtist = info[MediaRemoteClient.InfoKey.artist] as? String
        if let data = info[MediaRemoteClient.InfoKey.artworkData] as? Data {
            albumArtwork = NSImage(data: data)
        } else {
            albumArtwork = nil
        }
        duration = info[MediaRemoteClient.InfoKey.duration] as? Double ?? 0
        elapsedTime = info[MediaRemoteClient.InfoKey.elapsedTime] as? Double ?? 0
        await refreshPlayState()
    }

    private func refreshPlayState() async {
        let playing = await client.fetchIsPlaying()
        isPlaying = playing
        updateProgressTimer(playing: playing)
    }

    private func updateProgressTimer(playing: Bool) {
        progressTask?.cancel()
        guard playing else { return }
        progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedTime += 1
            }
        }
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // Media controls
    func togglePlayPause() { client.send(.togglePlayPause) }
    func nextTrack() { client.send(.nextTrack) }
    func previousTrack() { client.send(.previousTrack) }
}
