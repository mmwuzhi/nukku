import AppKit
import Foundation

@MainActor
final class BrowserMediaSessionProvider {
    static let shared = BrowserMediaSessionProvider()
    private init() {}

    private struct ScriptPayload: Decodable, Sendable {
        let playbackState: String?
        let title: String?
        let artist: String?
        let album: String?
        let artwork: [Artwork]?
        let url: String?
        let hasPlayingMedia: Bool
        let hasPausedMedia: Bool
        let host: String?
        let currentTime: Double?
        let duration: Double?
        let playbackRate: Double?

        struct Artwork: Decodable, Sendable {
            let src: String?
            let sizes: String?
        }
    }

    private struct BrowserScriptResult {
        let payload: ScriptPayload
        let appName: String
        let bundleID: String
        let appIcon: NSImage?
    }

    static let supportedBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
    ]

    func isSupported(_ bundleID: String) -> Bool {
        Self.supportedBundleIDs.contains(bundleID)
    }

    func snapshot(for audible: AudibleProcessMonitor.AudibleApp) async -> MediaSessionSnapshot? {
        guard isSupported(audible.bundleID),
              let result = await scriptResult(for: audible)
        else { return nil }

        let payload = result.payload
        guard payload.hasPlayingMedia || payload.hasPausedMedia || hasUsefulMediaSession(payload) else {
            return nil
        }

        let title = cleaned(payload.title)
        let subtitle = cleaned(payload.artist)
            ?? cleaned(payload.album)
            ?? siteName(from: payload.url, fallbackHost: payload.host)
            ?? result.appName

        guard let title else {
            return nil
        }

        let artworkURL = bestArtworkURL(from: payload.artwork)
        let artwork = await MediaArtworkCache.shared.image(from: artworkURL) ?? result.appIcon
        let state = playbackState(from: payload)

        return MediaSessionSnapshot(
            title: title,
            subtitle: subtitle,
            artwork: artwork,
            sourceAppName: result.appName,
            sourceBundleID: result.bundleID,
            playbackState: state,
            reportedPlaybackState: state,
            confidence: payload.playbackState == "playing" ? .trusted : .probable,
            timestamp: Date(),
            sampledAt: Date(),
            provider: .browserMediaSession,
            duration: payload.duration ?? 0,
            elapsedTime: payload.currentTime ?? 0,
            playbackRate: payload.playbackRate,
            debugSourceSummary: "BrowserMediaSession",
            debugClientBundleID: result.bundleID,
            debugRawKeys: rawKeySummary(from: payload),
            debugPayloadSummary: payloadSummary(from: payload, appName: result.appName, bundleID: result.bundleID),
            usedBrowserSupplement: false
        )
    }

    private func scriptResult(for audible: AudibleProcessMonitor.AudibleApp) async -> BrowserScriptResult? {
        let source = script(bundleID: audible.bundleID)
        guard let raw = await runAppleScript(source),
              let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ScriptPayload.self, from: data)
        else { return nil }

        return BrowserScriptResult(
            payload: payload,
            appName: audible.appName,
            bundleID: audible.bundleID,
            appIcon: audible.appIcon
        )
    }

    private func hasUsefulMediaSession(_ payload: ScriptPayload) -> Bool {
        guard cleaned(payload.title) != nil else { return false }
        return payload.playbackState == "playing" || payload.playbackState == "paused"
    }

    private func playbackState(from payload: ScriptPayload) -> PlaybackState {
        if payload.hasPlayingMedia || payload.playbackState == "playing" {
            return .playing
        }
        if payload.hasPausedMedia || payload.playbackState == "paused" {
            return .paused
        }
        return .unknown
    }

    private func bestArtworkURL(from artwork: [ScriptPayload.Artwork]?) -> String? {
        artwork?
            .compactMap(\.src)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func siteName(from urlString: String?, fallbackHost: String?) -> String? {
        let host = urlString.flatMap { URL(string: $0)?.host } ?? fallbackHost
        guard let host else { return nil }
        return host
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .first
            .map { String($0).capitalized }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "_哔哩哔哩_bilibili", with: "")
            .replacingOccurrences(of: "-哔哩哔哩", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func script(bundleID: String) -> String {
        if bundleID == "com.apple.Safari" {
            return safariScript()
        }
        return chromiumScript(bundleID: bundleID)
    }

    private func chromiumScript(bundleID: String) -> String {
        let js = mediaSessionJavaScript.appleScriptEscaped
        return """
        tell application id "\(bundleID)"
            set nukkuJSON to ""
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if audible of t is true then
                                set nukkuJSON to execute t javascript "\(js)"
                                exit repeat
                            end if
                        end try
                    end repeat
                    if nukkuJSON is not "" then exit repeat
                end repeat
            end try
            if nukkuJSON is not "" then return nukkuJSON
            if frontmost is false then return ""
            try
                set nukkuJSON to execute active tab of front window javascript "\(js)"
            on error
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                if isFocused of t is true then
                                    set nukkuJSON to execute t javascript "\(js)"
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if nukkuJSON is not "" then exit repeat
                    end repeat
                end try
            end try
            return nukkuJSON
        end tell
        """
    }

    private func safariScript() -> String {
        let js = mediaSessionJavaScript.appleScriptEscaped
        return """
        tell application id "com.apple.Safari"
            if frontmost is false then return ""
            try
                return do JavaScript "\(js)" in current tab of front window
            on error
                return ""
            end try
        end tell
        """
    }

    private var mediaSessionJavaScript: String {
        """
        (() => {
          const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
          const media = Array.from(document.querySelectorAll('video,audio'));
          const active = media.find((m) => !m.paused && !m.ended && m.readyState >= 2)
            || media.find((m) => m.paused && !m.ended && m.currentTime > 0)
            || null;
          const hasPlayingMedia = media.some((m) => !m.paused && !m.ended && m.readyState >= 2);
          const hasPausedMedia = media.some((m) => m.paused && !m.ended && m.currentTime > 0);
          return JSON.stringify({
            playbackState: navigator.mediaSession ? navigator.mediaSession.playbackState : null,
            title: metadata ? metadata.title : null,
            artist: metadata ? metadata.artist : null,
            album: metadata ? metadata.album : null,
            artwork: metadata ? metadata.artwork : [],
            url: location.href,
            host: location.hostname,
            hasPlayingMedia,
            hasPausedMedia,
            currentTime: active ? active.currentTime : null,
            duration: active && Number.isFinite(active.duration) ? active.duration : null,
            playbackRate: active ? active.playbackRate : null
          });
        })();
        """
    }

    private func rawKeySummary(from payload: ScriptPayload) -> [String] {
        var keys: [String] = []
        if payload.title != nil { keys.append("title") }
        if payload.artist != nil { keys.append("artist") }
        if payload.album != nil { keys.append("album") }
        if payload.artwork?.isEmpty == false { keys.append("artwork") }
        if payload.playbackState != nil { keys.append("playbackState") }
        if payload.currentTime != nil { keys.append("currentTime") }
        if payload.duration != nil { keys.append("duration") }
        if payload.playbackRate != nil { keys.append("playbackRate") }
        return keys
    }

    private func payloadSummary(from payload: ScriptPayload, appName: String, bundleID: String) -> String {
        [
            "app=\(appName)",
            "bundle=\(bundleID)",
            "title=\(debugPresence(payload.title))",
            "artist=\(debugPresence(payload.artist))",
            "album=\(debugPresence(payload.album))",
            "playbackState=\(payload.playbackState ?? "-")",
            "hasPlayingMedia=\(payload.hasPlayingMedia)",
            "hasPausedMedia=\(payload.hasPausedMedia)",
            "rate=\(payload.playbackRate.map { String(format: "%.2f", $0) } ?? "-")",
            "elapsed=\(payload.currentTime.map { String(format: "%.2f", $0) } ?? "-")",
            "duration=\(payload.duration.map { String(format: "%.2f", $0) } ?? "-")",
            "artworkCount=\(payload.artwork?.count ?? 0)",
            "host=\(payload.host ?? "-")",
        ].joined(separator: " ")
    }

    private func debugPresence(_ value: String?) -> String {
        guard let value else { return "missing" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "empty" : "present(\(trimmed.count))"
    }

    private func runAppleScript(_ source: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            if error != nil { return nil }
            return result?.stringValue
        }.value
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
