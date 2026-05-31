import AppKit
import Observation

@Observable
@MainActor
final class AppLauncherViewModel {
    struct PinnedApp: Identifiable {
        let id: String   // absolute URL string
        let url: URL
        var name: String { url.deletingPathExtension().lastPathComponent }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    }

    // Plain stored property — @Observable tracks mutations, we persist manually.
    private var csv: String

    init() {
        csv = UserDefaults.standard.string(forKey: "pinnedApps") ?? ""
    }

    var apps: [PinnedApp] {
        csv.split(separator: ";", omittingEmptySubsequences: true)
            .compactMap { URL(string: String($0)) }
            .map { PinnedApp(id: $0.absoluteString, url: $0) }
    }

    func add(_ url: URL) {
        var paths = csv.split(separator: ";", omittingEmptySubsequences: true).map(String.init)
        let key = url.absoluteString
        guard paths.count < 8, !paths.contains(key) else { return }
        paths.append(key)
        csv = paths.joined(separator: ";")
        persist()
    }

    func remove(_ app: PinnedApp) {
        let remaining = apps.filter { $0.id != app.id }.map { $0.url.absoluteString }
        csv = remaining.joined(separator: ";")
        persist()
    }

    func launch(_ app: PinnedApp) {
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加"
        panel.message = "选择一个应用（最多 8 个）"
        if panel.runModal() == .OK, let url = panel.url {
            add(url)
        }
    }

    // MARK: - Private

    private func persist() {
        UserDefaults.standard.set(csv, forKey: "pinnedApps")
    }
}
