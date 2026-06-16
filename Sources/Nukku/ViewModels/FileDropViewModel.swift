import AppKit
import Observation

@Observable
@MainActor
final class FileDropViewModel {
    struct DroppedFile: Identifiable {
        let id = UUID()
        let url: URL
        let icon: NSImage?
        var name: String { url.lastPathComponent }
    }

    var files: [DroppedFile] = []

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { [weak self] item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor [weak self] in
                    self?.ingest(urls: [url])
                }
            }
        }
        return true
    }

    /// Adds file URLs to the shelf (most-recent first). Shared by the SwiftUI
    /// `.onDrop` path and the AppKit drag-catcher path. Skips files already on the
    /// shelf; an existing entry is re-surfaced to the front instead of duplicated.
    func ingest(urls: [URL]) {
        for url in urls {
            let resolvedURL = url.resolvingSymlinksInPath()
            if let existing = files.firstIndex(where: { $0.url == resolvedURL }) {
                let item = files.remove(at: existing)
                files.insert(item, at: 0)
                continue
            }
            let icon = NSWorkspace.shared.icon(forFile: resolvedURL.path)
            files.insert(DroppedFile(url: resolvedURL, icon: icon), at: 0)
        }
    }

    func open(_ file: DroppedFile) {
        NSWorkspace.shared.open(file.url)
    }

    func reveal(_ file: DroppedFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }

    func remove(_ file: DroppedFile) {
        files.removeAll { $0.id == file.id }
    }
}
