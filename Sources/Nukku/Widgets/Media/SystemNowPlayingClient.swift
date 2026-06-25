import AppKit
import Foundation
import MediaRemoteAdapter

/// Reads system now-playing via the entitled perl-adapter (`ejbills/mediaremote-adapter`).
///
/// macOS 15.4+ blocks direct in-process MediaRemote access (entitlement check in
/// `mediaremoted`), so the adapter shells out to `/usr/bin/perl` — an Apple-entitled
/// binary — which `dlopen`s the helper dylib and streams now-playing JSON. This is the
/// same data Control Center sees, including browsers (Zen/Safari/Chrome) that publish
/// MediaSession metadata, with no browser flags required.
@MainActor
final class SystemNowPlayingClient {
    static let shared = SystemNowPlayingClient()

    /// Fired on the main actor whenever a fresh now-playing event arrives.
    var onUpdate: (() -> Void)?

    private let controller = MediaController()
    private var started = false
    private var cachedSnapshot: MediaSessionSnapshot?
    private var restartAttempts = 0
    private var restartTask: Task<Void, Never>?
    private let maxRestartDelay: Double = 30

    /// `TrackInfo` carries a non-Sendable `NSImage`; each callback delivers a freshly
    /// built value, so it is safe to ferry across the actor hop unchecked.
    private struct TrackInfoBox: @unchecked Sendable {
        let value: TrackInfo?
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        controller.onTrackInfoReceived = { [weak self] info in
            let box = TrackInfoBox(value: info)
            Task { @MainActor in self?.handle(box.value) }
        }
        controller.onListenerTerminated = { [weak self] in
            Task { @MainActor in self?.scheduleRestart() }
        }
        controller.startListening()
    }

    /// Stops the listener and cancels any pending restart. Call on app termination.
    func stop() {
        restartTask?.cancel()
        restartTask = nil
        started = false
        controller.stopListening()
    }

    func currentSnapshot() -> MediaSessionSnapshot? {
        cachedSnapshot
    }

    // MARK: - Transport

    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }

    // MARK: - Internal

    private func handle(_ info: TrackInfo?) {
        restartAttempts = 0  // a delivered event means the listener is healthy
        cachedSnapshot = info.flatMap(Self.snapshot(from:))
        onUpdate?()
    }

    /// Restarts the listener with exponential backoff (capped) so a persistently
    /// failing perl child can't spin in a rapid respawn loop. Keeps retrying
    /// indefinitely (media may start later); the delay is reset once an event arrives.
    private func scheduleRestart() {
        guard started else { return }  // intentional stop(); don't respawn
        started = false
        controller.stopListening()

        let delay = min(pow(2.0, Double(restartAttempts)), maxRestartDelay)
        restartAttempts += 1
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    private static func snapshot(from info: TrackInfo) -> MediaSessionSnapshot? {
        let payload = info.payload
        let title = nonEmpty(payload.title)
        let hasTitle = title != nil
        guard payload.bundleIdentifier != nil || hasTitle else { return nil }

        let reported: PlaybackState = (payload.isPlaying == true) ? .playing : .paused
        let now = Date()
        return MediaSessionSnapshot(
            title: title,
            subtitle: nonEmpty(payload.artist) ?? nonEmpty(payload.album),
            artwork: payload.artwork,
            sourceAppName: payload.applicationName,
            sourceBundleID: payload.bundleIdentifier,
            playbackState: reported,
            reportedPlaybackState: reported,
            confidence: hasTitle ? .trusted : .appOnly,
            timestamp: now,
            sampledAt: now,
            provider: .mediaRemote,
            duration: (payload.durationMicros ?? 0) / 1_000_000,
            elapsedTime: payload.currentElapsedTime ?? 0,
            playbackRate: payload.playbackRate,
            debugSourceSummary: "SystemNowPlaying",
            debugClientBundleID: payload.bundleIdentifier,
            debugRawKeys: rawKeys(from: payload),
            debugPayloadSummary: payloadSummary(from: payload),
            usedBrowserSupplement: false
        )
    }

    private static func rawKeys(from payload: TrackInfo.Payload) -> [String] {
        var keys: [String] = []
        if payload.title != nil { keys.append("title") }
        if payload.artist != nil { keys.append("artist") }
        if payload.album != nil { keys.append("album") }
        if payload.artwork != nil { keys.append("artwork") }
        if payload.isPlaying != nil { keys.append("isPlaying") }
        if payload.durationMicros != nil { keys.append("duration") }
        if payload.elapsedTimeMicros != nil { keys.append("elapsed") }
        if payload.playbackRate != nil { keys.append("playbackRate") }
        return keys.sorted()
    }

    private static func payloadSummary(from payload: TrackInfo.Payload) -> String {
        [
            "app=\(debugValue(payload.applicationName))",
            "bundle=\(debugValue(payload.bundleIdentifier))",
            "pid=\(payload.PID.map(String.init) ?? "-")",
            "title=\(debugPresence(payload.title))",
            "artist=\(debugPresence(payload.artist))",
            "album=\(debugPresence(payload.album))",
            "isPlaying=\(payload.isPlaying.map(String.init) ?? "-")",
            "rate=\(payload.playbackRate.map { String(format: "%.2f", $0) } ?? "-")",
            "elapsed=\(secondsSummary(micros: payload.elapsedTimeMicros))",
            "duration=\(secondsSummary(micros: payload.durationMicros))",
            "timestamp=\(secondsSummary(micros: payload.timestampEpochMicros))",
            "artworkBytes=\(artworkByteCount(payload.artworkDataBase64).map(String.init) ?? "-")",
            "artworkMime=\(debugValue(payload.artworkMimeType))",
            "artworkDecoded=\(payload.artwork == nil ? "false" : "true")",
        ].joined(separator: " ")
    }

    private static func debugPresence(_ value: String?) -> String {
        guard let value else { return "missing" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "empty" : "present(\(trimmed.count))"
    }

    private static func debugValue(_ value: String?) -> String {
        guard let value else { return "-" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "empty" : trimmed
    }

    private static func secondsSummary(micros: Double?) -> String {
        guard let micros else { return "-" }
        return String(format: "%.2f", micros / 1_000_000)
    }

    private static func artworkByteCount(_ base64: String?) -> Int? {
        guard let base64 else { return nil }
        return Data(base64Encoded: base64)?.count
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
