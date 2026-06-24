import Foundation
import Testing
@testable import Nukku

@Suite("Media session resolver")
struct MediaSessionResolverTests {
    @Test("Trusted Spotify title wins over CoreAudio app fallback")
    func spotifyWinsOverCoreAudio() {
        let now = Date()
        let spotify = snapshot(
            title: "You Came to Me",
            subtitle: "Sami Yusuf",
            appName: "Spotify",
            bundleID: "com.spotify.client",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .spotify,
            timestamp: now
        )
        let coreAudio = snapshot(
            title: nil,
            subtitle: nil,
            appName: "Spotify",
            bundleID: "com.spotify.client",
            state: .playing,
            reportedState: .playing,
            confidence: .appOnly,
            provider: .coreAudio,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [spotify, coreAudio],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.provider == .spotify)
        #expect(resolved?.displayKind == .richMedia)
        #expect(resolved?.title == "You Came to Me")
    }

    @Test("Rich paused session wins over CoreAudio app fallback")
    func pausedRichMediaWinsOverCoreAudio() {
        let now = Date()
        let pausedRemote = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .paused,
            reportedState: .paused,
            confidence: .trusted,
            provider: .mediaRemote,
            timestamp: now
        )
        let coreAudio = snapshot(
            title: nil,
            subtitle: nil,
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .appOnly,
            provider: .coreAudio,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [pausedRemote, coreAudio],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.provider == .mediaRemote)
        #expect(resolved?.playbackState == .paused)
        #expect(resolved?.displayKind == .richMedia)
    }

    @Test("MediaRemote trusted title wins over browser candidate")
    func mediaRemoteWinsOverBrowserMediaSession() {
        let now = Date()
        let mediaRemote = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Zen",
            bundleID: "app.zen-browser.zen",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .mediaRemote,
            timestamp: now
        )
        let browser = snapshot(
            title: "Browser Metadata",
            subtitle: "YouTube",
            appName: "Zen",
            bundleID: "app.zen-browser.zen",
            state: .playing,
            reportedState: .playing,
            confidence: .probable,
            provider: .browserMediaSession,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [mediaRemote, browser],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.provider == .mediaRemote)
        #expect(resolved?.title == "Actual Track")
    }

    @Test("Browser MediaSession title is displayed as rich media")
    func browserMediaSessionDisplaysRichMedia() {
        let now = Date()
        let browser = snapshot(
            title: "短段大奖赛 260603",
            subtitle: "Bilibili",
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .probable,
            provider: .browserMediaSession,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [browser],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.displayKind == .richMedia)
        #expect(resolved?.title == "短段大奖赛 260603")
    }

    @Test("Browser playing state wins when MediaRemote is stale paused")
    func browserPlayingWinsWhenMediaRemoteIsPaused() {
        let now = Date()
        let mediaRemote = snapshot(
            title: nil,
            subtitle: nil,
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .paused,
            reportedState: .paused,
            confidence: .probable,
            provider: .mediaRemote,
            timestamp: now
        )
        let browser = snapshot(
            title: "YouTube Video",
            subtitle: "YouTube",
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .browserMediaSession,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [mediaRemote, browser],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.provider == .browserMediaSession)
        #expect(resolved?.playbackState == .playing)
        #expect(resolved?.displayKind == .richMedia)
        #expect(resolved?.title == "YouTube Video")
    }

    @Test("Active tab title without media confidence is not rich media")
    func appOnlyCandidateDoesNotBecomeRichMedia() {
        let now = Date()
        let appOnly = snapshot(
            title: nil,
            subtitle: nil,
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .appOnly,
            provider: .coreAudio,
            timestamp: now
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [appOnly],
            previous: nil,
            now: now,
            previousSourceStillRunning: false
        )

        #expect(resolved?.displayKind == .appPlayback)
        #expect(resolved?.title == nil)
    }

    @Test("Paused app-only candidate is retained inside TTL")
    func pausedAppOnlyCandidateRetainedInsideTTL() {
        let now = Date()
        let appOnly = snapshot(
            title: nil,
            subtitle: nil,
            appName: "FlowVision",
            bundleID: "com.example.flowvision",
            state: .paused,
            reportedState: .paused,
            confidence: .appOnly,
            provider: .mediaRemote,
            timestamp: now.addingTimeInterval(-30)
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [appOnly],
            previous: appOnly,
            now: now,
            previousSourceStillRunning: true
        )

        #expect(resolved?.displayKind == .appPlayback)
        #expect(resolved?.playbackState == .paused)
    }

    @Test("Paused app-only candidate expires after TTL")
    func pausedAppOnlyCandidateExpiresAfterTTL() {
        let now = Date()
        let appOnly = snapshot(
            title: nil,
            subtitle: nil,
            appName: "FlowVision",
            bundleID: "com.example.flowvision",
            state: .paused,
            reportedState: .paused,
            confidence: .appOnly,
            provider: .mediaRemote,
            timestamp: now.addingTimeInterval(-(MediaSessionResolver.pausedSessionTTL + 1))
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [appOnly],
            previous: appOnly,
            now: now,
            previousSourceStillRunning: true
        )

        #expect(resolved == nil)
    }

    @Test("Paused session is retained inside TTL")
    func pausedSessionRetainedInsideTTL() {
        let now = Date()
        let previous = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Spotify",
            bundleID: "com.spotify.client",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .spotify,
            timestamp: now.addingTimeInterval(-30)
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [],
            previous: previous,
            now: now,
            previousSourceStillRunning: true
        )

        #expect(resolved?.playbackState == .paused)
        #expect(resolved?.displayKind == .richMedia)
        #expect(resolved?.title == "Actual Track")
    }

    @Test("Paused session expires after TTL")
    func pausedSessionExpiresAfterTTL() {
        let now = Date()
        let previous = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Spotify",
            bundleID: "com.spotify.client",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .spotify,
            timestamp: now.addingTimeInterval(-(MediaSessionResolver.pausedSessionTTL + 1))
        )

        let resolved = MediaSessionResolver.resolve(
            candidates: [],
            previous: previous,
            now: now,
            previousSourceStillRunning: true
        )

        #expect(resolved == nil)
    }

    @Test("Reported paused state is immediate")
    func reportedPausedWinsImmediately() {
        let snapshot = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Spotify",
            bundleID: "com.spotify.client",
            state: .paused,
            reportedState: .paused,
            confidence: .trusted,
            provider: .spotify,
            timestamp: Date()
        )

        #expect(MediaPlaybackHeuristics.immediateState(for: snapshot) == .paused)
        #expect(MediaPlaybackHeuristics.validatedState(for: snapshot, previous: nil) == .paused)
    }

    @Test("Playback rate zero pauses immediately")
    func playbackRateZeroPausesImmediately() {
        let snapshot = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .mediaRemote,
            timestamp: Date(),
            playbackRate: 0
        )

        #expect(MediaPlaybackHeuristics.immediateState(for: snapshot) == .paused)
    }

    @Test("Stalled elapsed time is corrected to paused within burst window")
    func stalledElapsedTimeIsCorrected() {
        let previousTime = Date()
        let previous = MediaPlaybackSample(
            title: "Actual Track",
            sourceBundleID: "company.thebrowser.dia",
            elapsedTime: 42,
            playbackRate: nil,
            reportedPlaybackState: .playing,
            sampledAt: previousTime
        )
        let current = snapshot(
            title: "Actual Track",
            subtitle: "Artist",
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .trusted,
            provider: .mediaRemote,
            timestamp: previousTime.addingTimeInterval(0.18),
            elapsedTime: 42,
            playbackRate: nil
        )

        #expect(MediaPlaybackHeuristics.needsBurstValidation(for: current, previous: previous))
        #expect(MediaPlaybackHeuristics.validatedState(for: current, previous: previous) == .paused)
    }

    @Test("App-level MediaRemote snapshot without title does not stall-flip to paused")
    func appLevelMediaRemoteDoesNotFalsePause() {
        let previousTime = Date()
        let previous = MediaPlaybackSample(
            title: nil,
            sourceBundleID: "company.thebrowser.dia",
            elapsedTime: 0,
            playbackRate: nil,
            reportedPlaybackState: .playing,
            sampledAt: previousTime
        )
        let current = snapshot(
            title: nil,
            subtitle: nil,
            appName: "Dia",
            bundleID: "company.thebrowser.dia",
            state: .playing,
            reportedState: .playing,
            confidence: .probable,
            provider: .mediaRemote,
            timestamp: previousTime.addingTimeInterval(0.18),
            elapsedTime: 0,
            playbackRate: nil
        )

        #expect(MediaPlaybackHeuristics.needsBurstValidation(for: current, previous: previous) == false)
        #expect(MediaPlaybackHeuristics.validatedState(for: current, previous: previous) == .playing)
    }

    private func snapshot(
        title: String?,
        subtitle: String?,
        appName: String,
        bundleID: String,
        state: PlaybackState,
        reportedState: PlaybackState,
        confidence: MediaConfidence,
        provider: MediaSessionProviderKind,
        timestamp: Date,
        elapsedTime: Double = 0,
        playbackRate: Double? = nil,
        usedBrowserSupplement: Bool = false
    ) -> MediaSessionSnapshot {
        MediaSessionSnapshot(
            title: title,
            subtitle: subtitle,
            artwork: nil,
            sourceAppName: appName,
            sourceBundleID: bundleID,
            playbackState: state,
            reportedPlaybackState: reportedState,
            confidence: confidence,
            timestamp: timestamp,
            sampledAt: timestamp,
            provider: provider,
            duration: 0,
            elapsedTime: elapsedTime,
            playbackRate: playbackRate,
            debugSourceSummary: String(describing: provider),
            debugClientBundleID: bundleID,
            debugRawKeys: [],
            usedBrowserSupplement: usedBrowserSupplement
        )
    }
}
