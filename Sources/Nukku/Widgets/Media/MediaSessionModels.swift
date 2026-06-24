import AppKit
import Foundation

enum PlaybackState: Equatable {
    case playing
    case paused
    case stopped
    case unknown

    var isPlaying: Bool {
        self == .playing
    }
}

enum MediaConfidence: Equatable {
    case trusted
    case probable
    case appOnly
}

enum MediaDisplayKind: Equatable {
    case empty
    case appPlayback
    case richMedia
}

enum MediaSessionProviderKind: Equatable {
    case spotify
    case mediaRemote
    case browserMediaSession
    case coreAudio
}

struct MediaPlaybackSample: Equatable {
    var title: String?
    var sourceBundleID: String?
    var elapsedTime: Double
    var playbackRate: Double?
    var reportedPlaybackState: PlaybackState
    var sampledAt: Date
}

struct MediaSessionSnapshot: Equatable {
    var title: String?
    var subtitle: String?
    var artwork: NSImage?
    var sourceAppName: String?
    var sourceBundleID: String?
    var playbackState: PlaybackState
    var reportedPlaybackState: PlaybackState
    var confidence: MediaConfidence
    var timestamp: Date
    var sampledAt: Date
    var provider: MediaSessionProviderKind
    var duration: Double
    var elapsedTime: Double
    var playbackRate: Double?
    var debugSourceSummary: String
    var debugClientBundleID: String?
    var debugRawKeys: [String]
    var usedBrowserSupplement: Bool

    var displayKind: MediaDisplayKind {
        if hasRichTitle { return .richMedia }
        if sourceBundleID != nil || sourceAppName != nil || artwork != nil { return .appPlayback }
        return .empty
    }

    var hasRichTitle: Bool {
        guard confidence != .appOnly else { return false }
        return title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var activitySample: MediaPlaybackSample? {
        guard sourceBundleID != nil || title != nil else { return nil }
        return MediaPlaybackSample(
            title: title,
            sourceBundleID: sourceBundleID,
            elapsedTime: elapsedTime,
            playbackRate: playbackRate,
            reportedPlaybackState: reportedPlaybackState,
            sampledAt: sampledAt
        )
    }

    static func == (lhs: MediaSessionSnapshot, rhs: MediaSessionSnapshot) -> Bool {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.sourceAppName == rhs.sourceAppName
            && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.playbackState == rhs.playbackState
            && lhs.reportedPlaybackState == rhs.reportedPlaybackState
            && lhs.confidence == rhs.confidence
            && lhs.provider == rhs.provider
            && lhs.duration == rhs.duration
            && lhs.elapsedTime == rhs.elapsedTime
            && lhs.playbackRate == rhs.playbackRate
            && lhs.debugSourceSummary == rhs.debugSourceSummary
            && lhs.debugClientBundleID == rhs.debugClientBundleID
            && lhs.debugRawKeys == rhs.debugRawKeys
            && lhs.usedBrowserSupplement == rhs.usedBrowserSupplement
    }
}

enum MediaPlaybackHeuristics {
    static let minimumStallWallDelta: TimeInterval = 0.12
    static let minimumProgressDelta: Double = 0.05

    static func immediateState(for snapshot: MediaSessionSnapshot) -> PlaybackState {
        switch snapshot.reportedPlaybackState {
        case .paused, .stopped:
            return snapshot.reportedPlaybackState
        case .playing:
            if let rate = snapshot.playbackRate, rate <= 0.01 {
                return .paused
            }
            return .playing
        case .unknown:
            if let rate = snapshot.playbackRate, rate <= 0.01 {
                return .paused
            }
            return snapshot.playbackState
        }
    }

    static func validatedState(
        for snapshot: MediaSessionSnapshot,
        previous: MediaPlaybackSample?
    ) -> PlaybackState {
        let immediate = immediateState(for: snapshot)
        guard immediate == .playing else { return immediate }
        guard hasStalledElapsed(snapshot: snapshot, previous: previous) else { return .playing }
        return .paused
    }

    static func needsBurstValidation(
        for snapshot: MediaSessionSnapshot,
        previous: MediaPlaybackSample?
    ) -> Bool {
        guard snapshot.provider == .mediaRemote else { return false }
        guard snapshot.reportedPlaybackState == .playing else { return false }
        guard snapshot.playbackRate == nil || snapshot.playbackRate ?? 0 <= 0.01 else { return false }
        return hasStalledElapsed(snapshot: snapshot, previous: previous)
    }

    private static func hasStalledElapsed(
        snapshot: MediaSessionSnapshot,
        previous: MediaPlaybackSample?
    ) -> Bool {
        guard snapshot.hasRichTitle else {
            return false
        }
        guard let previous,
              let currentTitle = snapshot.title,
              let previousTitle = previous.title,
              previousTitle == currentTitle,
              previous.sourceBundleID == snapshot.sourceBundleID,
              currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return false
        }

        let wallDelta = snapshot.sampledAt.timeIntervalSince(previous.sampledAt)
        guard wallDelta >= minimumStallWallDelta else {
            return false
        }

        let mediaDelta = snapshot.elapsedTime - previous.elapsedTime
        return mediaDelta <= minimumProgressDelta
    }
}

enum MediaSessionResolver {
    static let pausedSessionTTL: TimeInterval = 60 * 5

    static func resolve(
        candidates: [MediaSessionSnapshot?],
        previous: MediaSessionSnapshot?,
        now: Date = Date(),
        previousSourceStillRunning: Bool
    ) -> MediaSessionSnapshot? {
        let viable = candidates.compactMap { $0 }.filter { snapshot in
            guard snapshot.displayKind != .empty, snapshot.playbackState != .stopped else {
                return false
            }
            // A title-less app can remain registered as the OS now-playing client
            // indefinitely after it pauses. Unlike rich track metadata, that app-only
            // identity is not useful enough to keep the notch visible forever.
            if snapshot.confidence == .appOnly, snapshot.playbackState != .playing {
                return now.timeIntervalSince(snapshot.timestamp) <= pausedSessionTTL
            }
            return true
        }

        if let best = viable.max(by: { score($0) < score($1) }) {
            return best
        }

        guard var previous, previousSourceStillRunning else { return nil }
        guard now.timeIntervalSince(previous.timestamp) <= pausedSessionTTL else { return nil }
        previous.playbackState = .paused
        previous.reportedPlaybackState = .paused
        previous.duration = 0
        previous.elapsedTime = 0
        previous.playbackRate = 0
        previous.sampledAt = now
        return previous
    }

    private static func score(_ snapshot: MediaSessionSnapshot) -> Int {
        var score = 0
        switch snapshot.displayKind {
        case .richMedia:
            score += 100
        case .appPlayback:
            score += 40
        case .empty:
            break
        }

        switch snapshot.confidence {
        case .trusted:
            score += 30
        case .probable:
            score += 18
        case .appOnly:
            break
        }

        switch snapshot.provider {
        case .spotify:
            score += 12
        case .mediaRemote:
            score += 10
        case .browserMediaSession:
            score += 8
        case .coreAudio:
            score += 1
        }

        switch snapshot.playbackState {
        case .playing:
            score += 6
        case .paused:
            score += 4
        case .unknown:
            score += 2
        case .stopped:
            score -= 100
        }

        if snapshot.usedBrowserSupplement {
            score += 3
        }
        if snapshot.artwork != nil {
            score += 1
        }
        return score
    }
}
