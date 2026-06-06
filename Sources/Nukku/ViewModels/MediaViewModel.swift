import AppKit
import Observation

@Observable
@MainActor
final class MediaViewModel {
    /// Temporary diagnostic indicator surfaced in the widget UI.
    /// Tells us which detection path produced the currently-displayed data.
    enum DataSource: String {
        case mediaRemote      = "M"   // MR per-app — richest data
        case coreAudioWithTab = "A"   // CoreAudio + Chromium AppleScript tab title
        case coreAudioOnly    = "C"   // CoreAudio app name only
    }

    var nowPlayingTitle: String?
    var nowPlayingArtist: String?
    var albumArtwork: NSImage?
    var isPlaying: Bool = false
    var sourceAppName: String?
    var sourceBundleID: String?
    var dataSource: DataSource?
    var isHoveringTransportControl: Bool = false

    var hasMediaSession: Bool {
        nowPlayingTitle != nil || sourceBundleID != nil || albumArtwork != nil
    }

    var elapsedTime: Double = 0
    var duration: Double = 0
    var progress: Double { duration > 0 ? min(elapsedTime / duration, 1.0) : 0 }

    private let mr = MediaRemoteClient.shared
    private var observerTokens: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    @ObservationIgnored
    weak var hudViewModel: HUDViewModel?

    /// After a user-initiated transport toggle, ignore external `isPlaying`
    /// updates for this long. Prevents CoreAudio's lagging "is running" flag
    /// (audio tail can take ~1s to drop) and stray MR notifications from
    /// reverting the optimistic UI change.
    @ObservationIgnored
    private var ignoreIsPlayingUntil: Date = .distantPast

    /// Bumped whenever the displayed title should re-surface from the start —
    /// on a true track change or a user-initiated play/pause toggle. The Media
    /// widget's MarqueeText keys its scroll task on this token so the title
    /// jumps back to the start whenever something noteworthy happened, even
    /// if the user wasn't looking (Alcove-style "hey, the song changed" beat).
    private(set) var marqueeRestartToken: Int = 0

    @ObservationIgnored
    private var previousTitle: String?

    init() {
        setupObservers()
        startPolling()
    }

    isolated deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Observation

    private func setupObservers() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            MediaRemoteClient.nowPlayingInfoChanged,
            MediaRemoteClient.isPlayingChanged,
            MediaRemoteClient.appDidChange,
        ]
        for name in names {
            observerTokens.append(
                nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in await self?.refresh() }
                }
            )
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        if await refreshFromSpotifyIfAvailable() {
            checkMarqueeRestart()
            return
        }
        if await refreshFromMediaRemote() {
            checkMarqueeRestart()
            return
        }
        await refreshFromCoreAudio()
        checkMarqueeRestart()
    }

    /// Bump `marqueeRestartToken` only when the title transitioned between
    /// two distinct non-empty values (a real track change). Don't bump on
    /// initial load (nil → value) or unload (value → nil), and don't bump
    /// when poll/notification returns the same title.
    private func checkMarqueeRestart() {
        let current = nowPlayingTitle
        if let old = previousTitle, let new = current, old != new {
            marqueeRestartToken &+= 1
        }
        previousTitle = current
    }

    private func refreshFromMediaRemote() async -> Bool {
        guard let bundleID = await mr.currentlyPlayingBundleID() else { return false }
        let info = await mr.fetchInfo(forBundle: bundleID)
        guard let title = info[MediaRemoteClient.InfoKey.title] as? String,
              !title.isEmpty else { return false }

        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first

        nowPlayingTitle  = title
        nowPlayingArtist = (info[MediaRemoteClient.InfoKey.artist] as? String).flatMap { $0.isEmpty ? nil : $0 }
        sourceBundleID   = bundleID
        sourceAppName    = runningApp?.localizedName ?? bundleID
        setIsPlayingExternal(await mr.fetchIsPlaying())
        dataSource       = .mediaRemote

        if let data = info[MediaRemoteClient.InfoKey.artworkData] as? Data,
           data.count <= 10_000_000,
           let img = NSImage(data: data) {
            albumArtwork = img
        } else {
            albumArtwork = runningApp?.icon
        }

        duration    = info[MediaRemoteClient.InfoKey.duration] as? Double ?? 0
        elapsedTime = info[MediaRemoteClient.InfoKey.elapsed]  as? Double ?? 0
        scheduleProgressTimer()
        return true
    }

    private func refreshFromSpotifyIfAvailable() async -> Bool {
        let bundleID = "com.spotify.client"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let info = await fetchSpotifyInfo(),
              !info.title.isEmpty else {
            return false
        }

        nowPlayingTitle  = info.title
        nowPlayingArtist = info.artist.isEmpty ? nil : info.artist
        sourceBundleID   = bundleID
        sourceAppName    = app.localizedName ?? "Spotify"
        albumArtwork     = app.icon
        setIsPlayingExternal(info.isPlaying)
        dataSource       = .mediaRemote
        duration         = 0
        elapsedTime      = 0
        progressTask?.cancel()
        progressTask = nil
        return true
    }

    private struct SpotifyInfo: Sendable {
        let title: String
        let artist: String
        let isPlaying: Bool
    }

    private func fetchSpotifyInfo() async -> SpotifyInfo? {
        let script = """
        tell application "Spotify"
            set playerState to player state as string
            if playerState is "stopped" then return ""
            set trackName to name of current track
            set artistName to artist of current track
            return trackName & "\n" & artistName & "\n" & playerState
        end tell
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var error: NSDictionary?
                guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
                      !output.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let parts = output.components(separatedBy: "\n")
                continuation.resume(returning: SpotifyInfo(
                    title: parts.first ?? "",
                    artist: parts.dropFirst().first ?? "",
                    isPlaying: parts.dropFirst(2).first == "playing"
                ))
            }
        }
    }

    private func refreshFromCoreAudio() async {
        guard let audible = AudibleProcessMonitor.shared.currentlyAudible() else {
            // Nothing currently audible. If the previously-known source app is
            // still alive (likely paused, not closed), keep the last-known
            // track info visible with isPlaying=false so the user can still
            // see and operate the controls. Only fully clear when the source
            // app actually quits.
            if let prevBundle = sourceBundleID,
               !NSRunningApplication
                    .runningApplications(withBundleIdentifier: prevBundle).isEmpty {
                setIsPlayingExternal(false)
                progressTask?.cancel()
                progressTask = nil
                return
            }
            applyNothingPlaying()
            return
        }
        sourceAppName  = audible.appName
        sourceBundleID = audible.bundleID
        albumArtwork   = audible.appIcon
        setIsPlayingExternal(true)
        duration       = 0
        elapsedTime    = 0
        progressTask?.cancel()
        progressTask = nil

        if let tab = await BrowserTabFetcher.shared.activeTab(bundleID: audible.bundleID) {
            nowPlayingTitle  = tab.title
            nowPlayingArtist = audible.appName
            dataSource       = .coreAudioWithTab
        } else {
            nowPlayingTitle  = audible.appName
            nowPlayingArtist = nil
            dataSource       = .coreAudioOnly
        }
    }

    private func applyNothingPlaying() {
        nowPlayingTitle  = nil
        nowPlayingArtist = nil
        albumArtwork     = nil
        isPlaying        = false
        sourceAppName    = nil
        sourceBundleID   = nil
        elapsedTime      = 0
        duration         = 0
        dataSource       = nil
        progressTask?.cancel()
        progressTask = nil
    }

    private func scheduleProgressTimer() {
        progressTask?.cancel()
        guard isPlaying, duration > 0 else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.elapsedTime = min(self.elapsedTime + 1, self.duration)
            }
        }
    }

    // MARK: - Transport controls (MR SendCommand + optimistic UI)

    func togglePlayPause() {
        isPlaying.toggle()                                  // optimistic UI flip
        ignoreIsPlayingUntil = Date().addingTimeInterval(3) // 3s grace period
        marqueeRestartToken &+= 1                            // jump title back to start
        if sourceBundleID == "com.spotify.client" {
            sendSpotifyPlayPause()
        } else {
            _ = mr.send(.togglePlayPause)
        }
    }

    func nextTrack()     { _ = mr.send(.nextTrack) }
    func previousTrack() { _ = mr.send(.previousTrack) }

    func activateSourceApp() {
        guard let bundleID = sourceBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return }
        app.activate(options: [.activateAllWindows])
    }

    private func sendSpotifyPlayPause() {
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Spotify\" to playpause")?
                .executeAndReturnError(&error)
        }
    }

    /// Apply an `isPlaying` value sourced from refresh paths. Respects the
    /// user-toggle grace window so optimistic UI doesn't flicker back.
    private func setIsPlayingExternal(_ value: Bool) {
        if Date() < ignoreIsPlayingUntil { return }
        isPlaying = value
    }
}
