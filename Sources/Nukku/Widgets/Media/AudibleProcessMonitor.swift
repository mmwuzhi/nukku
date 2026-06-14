import Foundation
import CoreAudio
import AppKit

/// Detects which process is currently producing audio output via macOS 14.2+
/// public CoreAudio per-process APIs (`kAudioHardwarePropertyProcessObjectList` +
/// `kAudioProcessProperty{PID,IsRunning,BundleID}`).
///
/// Handles Chromium-style helper-process audio routing by mapping known helper
/// bundles back to the parent browser app.
@MainActor
final class AudibleProcessMonitor {
    static let shared = AudibleProcessMonitor()
    private init() {}

    struct AudibleApp: Equatable {
        let pid: pid_t
        let bundleID: String
        let appName: String
        let appIcon: NSImage?
    }

    /// Returns the first currently-audible non-system app, or nil.
    /// Helper processes are resolved to their parent browser when possible.
    func currentlyAudible() -> AudibleApp? {
        guard let audioObjects = audioProcessObjectIDs() else { return nil }
        for id in audioObjects {
            guard isRunningOutput(id) else { continue }
            guard let pid = pid(for: id), pid > 0 else { continue }
            guard let bundleID = bundleID(for: id), !bundleID.isEmpty else { continue }
            if isSystemBundle(bundleID) { continue }

            // Map known helper bundles to their parent browser.
            if let parent = resolveParentBrowser(forBundle: bundleID) {
                if PreferencesManager.shared.showMediaDiagnostics {
                    MediaDiagnosticsLogger.write(
                        "[CA] object=\(id) helperBundle=\(bundleID) parentBundle=\(parent.bundleID) parentPID=\(parent.pid)"
                    )
                }
                return parent
            }

            guard let runningApp = NSRunningApplication(processIdentifier: pid) else { continue }
            if PreferencesManager.shared.showMediaDiagnostics {
                MediaDiagnosticsLogger.write(
                    "[CA] object=\(id) bundle=\(bundleID) pid=\(pid) app=\(runningApp.localizedName ?? bundleID)"
                )
            }
            return AudibleApp(
                pid: pid,
                bundleID: bundleID,
                appName: runningApp.localizedName ?? bundleID,
                appIcon: runningApp.icon
            )
        }
        return nil
    }

    // MARK: - Helper-process → parent browser

    /// Bundle ID prefixes (helper processes) → candidate parent browser bundle IDs.
    /// Dia and Arc share the same helper bundle, so we list both candidates and
    /// pick whichever parent is currently running.
    private static let helperMap: [(prefix: String, parents: [String])] = [
        ("company.thebrowser.browser.helper", ["company.thebrowser.dia",
                                                "company.thebrowser.Browser"]),
        ("com.google.Chrome.helper",         ["com.google.Chrome"]),
        ("com.brave.Browser.helper",         ["com.brave.Browser"]),
        ("com.microsoft.edgemac.helper",     ["com.microsoft.edgemac"]),
        ("com.vivaldi.Vivaldi.helper",       ["com.vivaldi.Vivaldi"]),
        ("org.mozilla.firefox.",             ["org.mozilla.firefox"]),
        ("app.zen-browser.zen.",             ["app.zen-browser.zen"]),
    ]

    private func resolveParentBrowser(forBundle bundleID: String) -> AudibleApp? {
        for (prefix, candidates) in Self.helperMap where bundleID.hasPrefix(prefix) {
            for parentBundle in candidates {
                if let parent = NSRunningApplication
                        .runningApplications(withBundleIdentifier: parentBundle).first {
                    return AudibleApp(
                        pid: parent.processIdentifier,
                        bundleID: parentBundle,
                        appName: parent.localizedName ?? parentBundle,
                        appIcon: parent.icon
                    )
                }
            }
        }
        return nil
    }

    // MARK: - CoreAudio plumbing

    private func audioProcessObjectIDs() -> [AudioObjectID]? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr
        else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr
        else { return nil }
        return ids
    }

    private func pid(for id: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &pid) == noErr else { return nil }
        return pid
    }

    /// `IsRunning` is too broad for playback detection because it stays true
    /// while a process has audio IO in progress even without an active output
    /// stream. For media presence we only want processes with live output.
    private func isRunningOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running == 1
    }

    private func bundleID(for id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    private func isSystemBundle(_ id: String) -> Bool {
        let prefixes = [
            "com.apple.audiomxd",
            "com.apple.mediaremoted",
            "com.apple.universalaccessd",
            "com.apple.controlcenter",
            "com.apple.cmio.",
            "com.apple.WebKit.GPU",
            "com.apple.SiriNCService",
            "com.apple.assistantd",
            "com.apple.CoreSpeech",
            "com.apple.corespeechd",
            "com.apple.TelephonyUtilities",
            "com.apple.cloudpaird",
            "com.apple.avconferenced",
            "com.apple.loginwindow",
            "com.apple.accessibility.",
            "systemsoundserverd",
        ]
        return prefixes.contains { id.hasPrefix($0) }
    }
}
