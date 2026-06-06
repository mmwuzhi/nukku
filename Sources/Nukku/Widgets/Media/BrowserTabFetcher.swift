import AppKit
import Foundation

/// Fetches the active/focused tab title + URL from Chromium-family browsers via
/// AppleScript. Dual-path script handles both standard Chrome (`active tab of
/// front window` works) and Arc/Dia (broken specifier; iterate with `isFocused`
/// fallback).
@MainActor
final class BrowserTabFetcher {
    static let shared = BrowserTabFetcher()
    private init() {}

    struct TabInfo: Equatable, Sendable {
        let title: String
        let url: String?
    }

    /// Chromium-family bundle IDs we know AppleScript syntax for.
    static let supportedBundleIDs: Set<String> = [
        "com.google.Chrome",
        "company.thebrowser.Browser",   // Arc
        "company.thebrowser.dia",       // Dia
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
    ]

    func isSupported(_ bundleID: String) -> Bool {
        Self.supportedBundleIDs.contains(bundleID)
    }

    /// Returns the focused/active tab title + URL for the given browser, or nil
    /// on script failure / permission denial.
    func activeTab(bundleID: String) async -> TabInfo? {
        guard isSupported(bundleID) else { return nil }
        let source = script(bundleID: bundleID)
        guard let raw = await runAppleScript(source) else { return nil }
        if raw.isEmpty { return nil }
        let parts = raw.components(separatedBy: "<<>>")
        let title = parts.first ?? ""
        if title.isEmpty { return nil }
        let url = parts.count > 1 ? parts[1] : nil
        return TabInfo(title: title, url: (url?.isEmpty == false) ? url : nil)
    }

    // MARK: - AppleScript

    private func script(bundleID: String) -> String {
        // Walk every tab across every window looking for `audible = true`.
        // ONLY the audible tab's title is returned; we explicitly do not fall
        // back to active/focused tab because that's usually the tab the user
        // is reading, not the one playing audio (different tabs in a browser).
        //
        // Chromium forks that stripped the `audible` property (Dia, Arc) will
        // silently find nothing here and return "" — the caller's fallback
        // will then show just the app name, which is correct.
        """
        tell application id "\(bundleID)"
            set foundTitle to ""
            set foundURL to ""
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if audible of t is true then
                                set foundTitle to title of t
                                try
                                    set foundURL to URL of t
                                end try
                                exit repeat
                            end if
                        end try
                    end repeat
                    if foundTitle is not "" then exit repeat
                end repeat
            end try
            if foundTitle is "" then return ""
            return foundTitle & "<<>>" & foundURL
        end tell
        """
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
