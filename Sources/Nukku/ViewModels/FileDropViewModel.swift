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
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                Task { @MainActor [weak self] in
                    self?.files.insert(DroppedFile(url: url, icon: icon), at: 0)
                }
            }
        }
        return true
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
