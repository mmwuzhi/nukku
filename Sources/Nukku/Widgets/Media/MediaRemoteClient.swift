import Foundation
import AppKit

// MediaRemote is a private framework; load it dynamically to avoid compile-time dependency.
@MainActor
final class MediaRemoteClient {
    static let shared = MediaRemoteClient()

    private typealias GetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlayingFn =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias RegisterForNotificationsFn =
        @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn =
        @convention(c) (UInt32, AnyObject?) -> Bool

    private var getNowPlayingInfo: GetNowPlayingInfoFn?
    private var getIsPlaying: GetIsPlayingFn?
    private var sendCommand: SendCommandFn?

    private init() {
        guard let url = CFURLCreateWithFileSystemPath(
            nil,
            "/System/Library/PrivateFrameworks/MediaRemote.framework" as CFString,
            .cfurlposixPathStyle,
            true
        ), let bundle = CFBundleCreate(nil, url) else { return }

        func sym<T>(_ name: String) -> T? {
            CFBundleGetFunctionPointerForName(bundle, name as CFString)
                .map { unsafeBitCast($0, to: T.self) }
        }

        getNowPlayingInfo = sym("MRMediaRemoteGetNowPlayingInfo")
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        sendCommand = sym("MRMediaRemoteSendCommand")

        let register: RegisterForNotificationsFn? = sym("MRMediaRemoteRegisterForNowPlayingNotifications")
        register?(.main)
    }

    enum InfoKey {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    }

    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    // Notification names posted by MediaRemote
    static let nowPlayingInfoChanged = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingChanged = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    // Wraps [String: Any] as Sendable. Safe: MediaRemote creates a fresh dict per callback.
    private struct NowPlayingInfoBox: @unchecked Sendable { let dict: [String: Any] }

    func fetchNowPlayingInfo() async -> [String: Any] {
        await withCheckedContinuation { (cont: CheckedContinuation<NowPlayingInfoBox, Never>) in
            guard let fn = getNowPlayingInfo else {
                cont.resume(returning: NowPlayingInfoBox(dict: [:]))
                return
            }
            fn(.main) { info in cont.resume(returning: NowPlayingInfoBox(dict: info)) }
        }.dict
    }

    func fetchIsPlaying() async -> Bool {
        await withCheckedContinuation { cont in
            guard let fn = getIsPlaying else {
                cont.resume(returning: false)
                return
            }
            fn(.main) { playing in cont.resume(returning: playing) }
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}
