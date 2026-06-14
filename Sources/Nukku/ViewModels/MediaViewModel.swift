import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MediaViewModel {
    enum DataSource: String {
        case mediaRemote = "M"
        case browserMedia = "B"
        case coreAudioOnly = "C"
    }

    var nowPlayingTitle: String?
    var nowPlayingArtist: String?
    var albumArtwork: NSImage?
    private(set) var displayPlaybackState: PlaybackState = .stopped
    private(set) var validatedPlaybackState: PlaybackState = .stopped
    private(set) var reportedPlaybackState: PlaybackState = .stopped
    var sourceAppName: String?
    var sourceBundleID: String?
    var dataSource: DataSource?
    var isHoveringTransportControl: Bool = false
    var debugSourceSummary: String?
    var debugClientBundleID: String?
    var debugRawKeysSummary: String?
    var didUseBrowserSupplement: Bool = false
    var debugPlaybackRate: Double?

    var playbackState: PlaybackState {
        displayPlaybackState
    }

    var isPlaying: Bool {
        displayPlaybackState.isPlaying
    }

    var hasMediaSession: Bool {
        displayKind != .empty
    }

    var displayKind: MediaDisplayKind {
        currentSession?.displayKind ?? .empty
    }

    var elapsedTime: Double = 0
    var duration: Double = 0
    var progress: Double { duration > 0 ? min(elapsedTime / duration, 1.0) : 0 }

    private let browserMediaSessionProvider = BrowserMediaSessionProvider.shared
    private var pollTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var currentSession: MediaSessionSnapshot?

    @ObservationIgnored
    weak var hudViewModel: HUDViewModel?

    @ObservationIgnored
    private var ignoreExternalStateUntil: Date = .distantPast

    private(set) var marqueeRestartToken: Int = 0

    @ObservationIgnored
    private var previousTitle: String?

    @ObservationIgnored
    private var lastPlaybackSample: MediaPlaybackSample?

    private let burstRefreshInterval: Duration = .milliseconds(140)
    private let burstRefreshCount: Int = 2
    private let optimisticGuardWindow: TimeInterval = 0.4
    private let defaultPollInterval: Duration = .seconds(2)
    private let fallbackPollInterval: Duration = .milliseconds(250)

    init() {
        if PreferencesManager.shared.showMediaDiagnostics {
            MediaDiagnosticsLogger.reset()
        }
        startPolling()
    }

    /// Starts the system now-playing listener and routes its push events into `refresh()`.
    /// Called explicitly from `AppDelegate` (not `init`) so unit tests can construct the
    /// view model without spawning the perl subprocess.
    func startSystemNowPlaying() {
        SystemNowPlayingClient.shared.onUpdate = { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        SystemNowPlayingClient.shared.start()
    }

    private var diagnosticsEnabled: Bool {
        PreferencesManager.shared.showMediaDiagnostics
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(allowBurstValidation: false)
                let interval = await self?.currentPollInterval() ?? .seconds(2)
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await refresh(allowBurstValidation: true)
    }

    private func refresh(allowBurstValidation: Bool) async {
        // System now-playing (perl-adapter) is the primary source for everything that
        // publishes to macOS — including Spotify with real album art. The resolver then
        // picks among all live candidates, so a paused Spotify no longer masks a playing
        // browser. The browser MediaSession JS path remains an opt-in supplement.
        let mediaRemote = SystemNowPlayingClient.shared.currentSnapshot()
        let audible = AudibleProcessMonitor.shared.currentlyAudible()
        let browser = await browserSnapshot(
            audible: audible,
            mediaRemoteBundleID: mediaRemote?.sourceBundleID
        )
        let mergedRemote = mergedMediaRemoteSnapshot(mediaRemote, browser: browser)
        let shouldIncludeBrowser = shouldIncludeStandaloneBrowserCandidate(
            mediaRemote: mergedRemote ?? mediaRemote,
            browser: browser
        )
        let coreAudio = (mediaRemote == nil && browser == nil)
            ? audible.map(coreAudioSnapshot(for:))
            : nil

        let resolved = MediaSessionResolver.resolve(
            candidates: [mergedRemote ?? mediaRemote, shouldIncludeBrowser ? browser : nil, coreAudio],
            previous: currentSession,
            previousSourceStillRunning: previousSourceStillRunning()
        )
        apply(resolved, allowBurstValidation: allowBurstValidation)
        checkMarqueeRestart()
    }

    /// Queries the browser MediaSession JS path for the best-candidate supported
    /// browser. Discovery is decoupled from live audio output so a *paused*
    /// browser tab (no audio) is still read — the audio gate previously hid
    /// paused Bilibili/YouTube in Dia, Brave, etc.
    private func browserSnapshot(
        audible: AudibleProcessMonitor.AudibleApp?,
        mediaRemoteBundleID: String?
    ) async -> MediaSessionSnapshot? {
        var candidates: [AudibleProcessMonitor.AudibleApp] = []
        var seen: Set<String> = []
        func add(_ app: AudibleProcessMonitor.AudibleApp?) {
            guard let app,
                  browserMediaSessionProvider.isSupported(app.bundleID),
                  seen.insert(app.bundleID).inserted
            else { return }
            candidates.append(app)
        }

        // Priority: actively-audible > MediaRemote's now-playing app > frontmost
        // > previous session source (sticky, paused-but-recent).
        add(audible)
        add(browserApp(forBundleID: mediaRemoteBundleID))
        add(browserApp(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        add(browserApp(forBundleID: currentSession?.sourceBundleID))

        if diagnosticsEnabled, !candidates.isEmpty {
            MediaDiagnosticsLogger.write(
                "[BrowserCandidates] " + candidates.map(\.bundleID).joined(separator: ",")
            )
        }

        for candidate in candidates {
            if let snapshot = await browserMediaSessionProvider.snapshot(for: candidate) {
                return snapshot
            }
        }
        return nil
    }

    private func browserApp(forBundleID bundleID: String?) -> AudibleProcessMonitor.AudibleApp? {
        guard let bundleID,
              browserMediaSessionProvider.isSupported(bundleID),
              let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        return AudibleProcessMonitor.AudibleApp(
            pid: app.processIdentifier,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            appIcon: app.icon
        )
    }

    private func checkMarqueeRestart() {
        let current = currentSession?.hasRichTitle == true ? nowPlayingTitle : nil
        if let old = previousTitle, let new = current, old != new {
            marqueeRestartToken &+= 1
        }
        previousTitle = current
    }

    private func coreAudioSnapshot(for audible: AudibleProcessMonitor.AudibleApp) -> MediaSessionSnapshot {
        let sampledAt = Date()
        return MediaSessionSnapshot(
            title: nil,
            subtitle: nil,
            artwork: audible.appIcon,
            sourceAppName: audible.appName,
            sourceBundleID: audible.bundleID,
            playbackState: .playing,
            reportedPlaybackState: .playing,
            confidence: .appOnly,
            timestamp: sampledAt,
            sampledAt: sampledAt,
            provider: .coreAudio,
            duration: 0,
            elapsedTime: 0,
            playbackRate: nil,
            debugSourceSummary: "CoreAudio",
            debugClientBundleID: audible.bundleID,
            debugRawKeys: ["bundleID", "isRunning"],
            usedBrowserSupplement: false
        )
    }

    private func mergedMediaRemoteSnapshot(
        _ mediaRemote: MediaSessionSnapshot?,
        browser: MediaSessionSnapshot?
    ) -> MediaSessionSnapshot? {
        guard var mediaRemote else { return browser }
        guard let browser,
              browser.sourceBundleID == mediaRemote.sourceBundleID
        else {
            return mediaRemote
        }

        let needsTitle = mediaRemote.hasRichTitle == false && browser.hasRichTitle
        let needsArtwork = mediaRemote.artwork == nil && browser.artwork != nil
        let shouldAdoptBrowserState = shouldPreferBrowserState(over: mediaRemote, browser: browser)
        let shouldSupplement = needsTitle || needsArtwork || shouldAdoptBrowserState
        guard shouldSupplement else { return mediaRemote }

        if needsTitle {
            mediaRemote.title = browser.title
            mediaRemote.subtitle = browser.subtitle
            mediaRemote.confidence = maxConfidence(mediaRemote.confidence, browser.confidence)
        }
        if needsArtwork {
            mediaRemote.artwork = browser.artwork
        }
        if shouldAdoptBrowserState {
            mediaRemote.playbackState = browser.playbackState
            mediaRemote.reportedPlaybackState = browser.reportedPlaybackState
            mediaRemote.playbackRate = browser.playbackRate
            mediaRemote.elapsedTime = browser.elapsedTime
            if browser.duration > 0 {
                mediaRemote.duration = browser.duration
            }
            mediaRemote.sampledAt = browser.sampledAt
            mediaRemote.timestamp = browser.timestamp
        }

        mediaRemote.usedBrowserSupplement = true
        mediaRemote.debugSourceSummary = "MediaRemote+BrowserMediaSession"
        mediaRemote.debugRawKeys = Array(Set(mediaRemote.debugRawKeys + browser.debugRawKeys)).sorted()
        return mediaRemote
    }

    private func shouldIncludeStandaloneBrowserCandidate(
        mediaRemote: MediaSessionSnapshot?,
        browser: MediaSessionSnapshot?
    ) -> Bool {
        guard let browser else { return false }
        guard let mediaRemote else { return true }
        if mediaRemote.sourceBundleID != browser.sourceBundleID {
            return true
        }
        return browser.hasRichTitle && (
            mediaRemote.hasRichTitle == false
                || mediaRemote.playbackState != browser.playbackState
                || mediaRemote.reportedPlaybackState != browser.reportedPlaybackState
        )
    }

    private func shouldPreferBrowserState(
        over mediaRemote: MediaSessionSnapshot,
        browser: MediaSessionSnapshot
    ) -> Bool {
        guard browser.reportedPlaybackState != .unknown else { return false }
        if mediaRemote.reportedPlaybackState == .unknown {
            return true
        }
        if browser.reportedPlaybackState == .playing && mediaRemote.reportedPlaybackState != .playing {
            return true
        }
        if browser.playbackState == .playing && mediaRemote.playbackState != .playing {
            return true
        }
        if browser.hasRichTitle && mediaRemote.hasRichTitle == false {
            return true
        }
        return false
    }

    private func maxConfidence(_ lhs: MediaConfidence, _ rhs: MediaConfidence) -> MediaConfidence {
        let score: (MediaConfidence) -> Int = {
            switch $0 {
            case .trusted: return 3
            case .probable: return 2
            case .appOnly: return 1
            }
        }
        return score(lhs) >= score(rhs) ? lhs : rhs
    }

    private func apply(_ snapshot: MediaSessionSnapshot?, allowBurstValidation: Bool) {
        let previousSample = lastPlaybackSample
        currentSession = snapshot

        guard let snapshot else {
            nowPlayingTitle = nil
            nowPlayingArtist = nil
            albumArtwork = nil
            displayPlaybackState = .stopped
            validatedPlaybackState = .stopped
            reportedPlaybackState = .stopped
            sourceAppName = nil
            sourceBundleID = nil
            elapsedTime = 0
            duration = 0
            dataSource = nil
            debugSourceSummary = nil
            debugClientBundleID = nil
            debugRawKeysSummary = nil
            didUseBrowserSupplement = false
            debugPlaybackRate = nil
            lastPlaybackSample = nil
            progressTask?.cancel()
            progressTask = nil
            burstTask?.cancel()
            burstTask = nil
            return
        }

        sourceAppName = snapshot.sourceAppName
        sourceBundleID = snapshot.sourceBundleID
        albumArtwork = snapshot.artwork
        duration = snapshot.duration
        elapsedTime = snapshot.elapsedTime
        dataSource = dataSource(for: snapshot.provider)
        reportedPlaybackState = snapshot.reportedPlaybackState
        validatedPlaybackState = MediaPlaybackHeuristics.validatedState(for: snapshot, previous: previousSample)
        debugSourceSummary = snapshot.debugSourceSummary
        debugClientBundleID = snapshot.debugClientBundleID
        debugRawKeysSummary = snapshot.debugRawKeys.joined(separator: ",")
        didUseBrowserSupplement = snapshot.usedBrowserSupplement
        debugPlaybackRate = snapshot.playbackRate

        switch snapshot.displayKind {
        case .richMedia:
            nowPlayingTitle = snapshot.title
            nowPlayingArtist = diagnosticsEnabled ? diagnosticsSummary(for: snapshot) : snapshot.subtitle
        case .appPlayback:
            let appName = snapshot.sourceAppName ?? "App"
            nowPlayingTitle = appPlaybackTitle(appName: appName, state: displayPlaybackState)
            nowPlayingArtist = diagnosticsEnabled ? diagnosticsSummary(for: snapshot) : "无法读取媒体标题"
        case .empty:
            nowPlayingTitle = nil
            nowPlayingArtist = nil
        }

        let immediateState = MediaPlaybackHeuristics.immediateState(for: snapshot)
        let correctedState = correctedDisplayState(immediate: immediateState, validated: validatedPlaybackState)
        setDisplayPlaybackStateExternal(correctedState)

        if snapshot.displayKind == .appPlayback,
           let appName = snapshot.sourceAppName {
            nowPlayingTitle = appPlaybackTitle(appName: appName, state: displayPlaybackState)
        }

        lastPlaybackSample = snapshot.activitySample

        if duration > 0 {
            scheduleProgressTimer()
        } else {
            progressTask?.cancel()
            progressTask = nil
        }

        if diagnosticsEnabled {
            emitDiagnosticsLog(for: snapshot)
        }

        if allowBurstValidation,
           MediaPlaybackHeuristics.needsBurstValidation(for: snapshot, previous: previousSample) {
            scheduleBurstValidation()
        }
    }

    private func correctedDisplayState(immediate: PlaybackState, validated: PlaybackState) -> PlaybackState {
        if immediate == .playing && validated == .paused {
            return .paused
        }
        return immediate
    }

    private func scheduleBurstValidation() {
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<burstRefreshCount {
                try? await Task.sleep(for: burstRefreshInterval)
                guard !Task.isCancelled else { return }
                await self.refresh(allowBurstValidation: false)
            }
        }
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

    // MARK: - Transport controls

    func togglePlayPause() {
        let optimisticState: PlaybackState = isPlaying ? .paused : .playing
        validatedPlaybackState = optimisticState
        setDisplayPlaybackState(optimisticState)
        ignoreExternalStateUntil = Date().addingTimeInterval(optimisticGuardWindow)
        // Note: do NOT bump marqueeRestartToken here — play/pause must not re-scroll the
        // title. The marquee restarts only on an actual title change (checkMarqueeRestart).
        if sourceBundleID == "com.spotify.client" {
            sendSpotifyPlayPause()
        } else {
            SystemNowPlayingClient.shared.togglePlayPause()
        }
    }

    func nextTrack() { SystemNowPlayingClient.shared.nextTrack() }
    func previousTrack() { SystemNowPlayingClient.shared.previousTrack() }

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

    private func setDisplayPlaybackStateExternal(_ value: PlaybackState) {
        if Date() < ignoreExternalStateUntil && value != displayPlaybackState {
            return
        }
        setDisplayPlaybackState(value)
    }

    private func setDisplayPlaybackState(_ value: PlaybackState) {
        displayPlaybackState = value
        if currentSession?.displayKind == .appPlayback,
           let appName = sourceAppName {
            nowPlayingTitle = appPlaybackTitle(appName: appName, state: value)
        }
        if value == .playing, duration > 0 {
            scheduleProgressTimer()
        } else if value != .playing {
            progressTask?.cancel()
            progressTask = nil
        }
    }

    private func previousSourceStillRunning() -> Bool {
        guard let bundleID = currentSession?.sourceBundleID else { return false }
        return !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .isEmpty
    }

    private func dataSource(for provider: MediaSessionProviderKind) -> DataSource {
        switch provider {
        case .spotify, .mediaRemote:
            .mediaRemote
        case .browserMediaSession:
            .browserMedia
        case .coreAudio:
            .coreAudioOnly
        }
    }

    private func appPlaybackTitle(appName: String, state: PlaybackState) -> String {
        switch state {
        case .playing:
            "\(appName) 正在播放"
        case .paused:
            "\(appName) 已暂停"
        case .stopped:
            "\(appName) 已停止"
        case .unknown:
            "\(appName) 正在播放"
        }
    }

    private func diagnosticsSummary(for snapshot: MediaSessionSnapshot) -> String {
        let rate = snapshot.playbackRate.map { String(format: "%.2f", $0) } ?? "-"
        let elapsed = String(format: "%.1f", snapshot.elapsedTime)
        let client = snapshot.debugClientBundleID ?? "-"
        let supplement = snapshot.usedBrowserSupplement ? "B+" : "B-"
        return "src:\(snapshot.debugSourceSummary) client:\(client) rpt:\(snapshot.reportedPlaybackState.label) dsp:\(displayPlaybackState.label) val:\(validatedPlaybackState.label) rate:\(rate) t:\(elapsed) \(supplement)"
    }

    private func currentPollInterval() -> Duration {
        guard let snapshot = currentSession else { return defaultPollInterval }
        let isBrowserSource = snapshot.sourceBundleID.map(browserMediaSessionProvider.isSupported(_:)) ?? false
        let needsFastPolling =
            snapshot.provider == .coreAudio
            || (snapshot.provider == .mediaRemote && snapshot.hasRichTitle == false && isBrowserSource)
            || (snapshot.provider == .browserMediaSession && snapshot.hasRichTitle == false)
        return needsFastPolling ? fallbackPollInterval : defaultPollInterval
    }

    private func emitDiagnosticsLog(for snapshot: MediaSessionSnapshot) {
        let message = """
        [MediaDiagnostics] source=\(snapshot.debugSourceSummary) client=\(snapshot.debugClientBundleID ?? "-") \
        reported=\(snapshot.reportedPlaybackState.label) display=\(displayPlaybackState.label) \
        validated=\(validatedPlaybackState.label) rate=\(snapshot.playbackRate.map { String(format: "%.2f", $0) } ?? "-") \
        elapsed=\(String(format: "%.2f", snapshot.elapsedTime)) duration=\(String(format: "%.2f", snapshot.duration)) \
        supplemented=\(snapshot.usedBrowserSupplement) keys=\(snapshot.debugRawKeys.joined(separator: ","))
        """
        print(message)
        MediaDiagnosticsLogger.write(message)
    }
}

private extension PlaybackState {
    var label: String {
        switch self {
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .stopped:
            "stopped"
        case .unknown:
            "unknown"
        }
    }
}
