import Foundation
import AppKit

/// Wraps the MediaRemote.framework private C API, focusing on the per-app
/// surface that still returns data on macOS 26 (Apple locked the *global*
/// `GetNowPlayingInfo` for unprivileged callers but left per-bundle queries
/// open — same path Alcove's `PrivateMediaRemote` ObjC class uses).
///
/// All symbols resolved via `dlopen` so the framework is not a link-time
/// dependency (Apple may further restrict access in the future).
@MainActor
final class MediaRemoteClient {
    static let shared = MediaRemoteClient()

    private typealias FnGetPID         = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias FnGetInfoForApp  = @convention(c) (NSString, DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias FnGetIsPlaying   = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias FnSendCommand    = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias FnRegister       = @convention(c) (DispatchQueue) -> Void

    private let getPID:        FnGetPID?
    private let getInfoForApp: FnGetInfoForApp?
    private let getIsPlaying:  FnGetIsPlaying?
    private let sendCmd:       FnSendCommand?

    enum Command: UInt32 {
        case play             = 0
        case pause            = 1
        case togglePlayPause  = 2
        case nextTrack        = 4
        case previousTrack    = 5
    }

    enum InfoKey {
        static let title       = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist      = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album       = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let duration    = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsed     = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    }

    static let nowPlayingInfoChanged = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingChanged      = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    static let appDidChange          = Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")

    private init() {
        guard let url = CFURLCreateWithFileSystemPath(
                nil,
                "/System/Library/PrivateFrameworks/MediaRemote.framework" as CFString,
                .cfurlposixPathStyle, true),
              let bundle = CFBundleCreate(nil, url)
        else {
            getPID = nil; getInfoForApp = nil; getIsPlaying = nil; sendCmd = nil
            return
        }

        func sym<T>(_ name: String) -> T? {
            CFBundleGetFunctionPointerForName(bundle, name as CFString)
                .map { unsafeBitCast($0, to: T.self) }
        }

        getPID        = sym("MRMediaRemoteGetNowPlayingApplicationPID")
        getInfoForApp = sym("MRMediaRemoteGetNowPlayingInfoForApp")
        getIsPlaying  = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        sendCmd       = sym("MRMediaRemoteSendCommand")

        let register: FnRegister? = sym("MRMediaRemoteRegisterForNowPlayingNotifications")
        register?(.main)
    }

    /// Wrap [String: Any] as Sendable. Safe: each callback delivers a freshly-built dict.
    private struct InfoBox: @unchecked Sendable { let dict: [String: Any] }

    /// PID of the currently-playing app, or 0 if nothing is playing.
    func fetchPID() async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            guard let fn = getPID else { cont.resume(returning: 0); return }
            fn(.main) { cont.resume(returning: $0) }
        }
    }

    /// Bundle ID of the currently-playing app, resolved via NSRunningApplication.
    func currentlyPlayingBundleID() async -> String? {
        let pid = await fetchPID()
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Per-app now-playing dict. Empty if nothing useful (locked, no track, etc.).
    func fetchInfo(forBundle bundleID: String) async -> [String: Any] {
        await withCheckedContinuation { (cont: CheckedContinuation<InfoBox, Never>) in
            guard let fn = getInfoForApp else {
                cont.resume(returning: InfoBox(dict: [:]))
                return
            }
            fn(bundleID as NSString, .main) { d in
                cont.resume(returning: InfoBox(dict: d ?? [:]))
            }
        }.dict
    }

    func fetchIsPlaying() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            guard let fn = getIsPlaying else { cont.resume(returning: false); return }
            fn(.main) { cont.resume(returning: $0) }
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCmd?(command.rawValue, nil) ?? false
    }
}
