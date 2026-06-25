import AppKit
import SwiftUI

/// Transparent AppKit overlay that owns all mouse interaction for a shelf file
/// cell. SwiftUI renders the icon + name behind it; this view handles:
///   - double-click to open (matching Finder; single click does nothing)
///   - drag-out with real Finder semantics: the destination decides move vs copy
///     (folder = move, upload target = copy), which `SwiftUI.onDrag` cannot do
///   - a right-click menu (reveal / open / remove)
/// When the drag ends as a move, the shelf entry is removed (the file relocated);
/// a copy leaves the entry in place.
struct FileItemInteraction: NSViewRepresentable {
    let url: URL
    let icon: NSImage?
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    func makeNSView(context: Context) -> FileCellNSView {
        let view = FileCellNSView()
        view.configure(url: url, icon: icon, onOpen: onOpen, onReveal: onReveal, onRemove: onRemove)
        return view
    }

    func updateNSView(_ nsView: FileCellNSView, context: Context) {
        nsView.configure(url: url, icon: icon, onOpen: onOpen, onReveal: onReveal, onRemove: onRemove)
    }
}

final class FileCellNSView: NSView, NSDraggingSource {
    private var url: URL?
    private var icon: NSImage?
    private var onOpen: (() -> Void)?
    private var onReveal: (() -> Void)?
    private var onRemove: (() -> Void)?

    func configure(url: URL, icon: NSImage?,
                   onOpen: @escaping () -> Void,
                   onReveal: @escaping () -> Void,
                   onRemove: @escaping () -> Void) {
        self.url = url
        self.icon = icon
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRemove = onRemove
    }

    override func mouseDown(with event: NSEvent) {
        // Double-click opens; a single click does nothing (Finder-like). A press
        // followed by movement becomes a drag, handled in mouseDragged.
        if event.clickCount == 2 { onOpen?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = icon ?? NSWorkspace.shared.icon(forFile: url.path)
        let side: CGFloat = 48
        let frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side, height: side
        )
        item.setDraggingFrame(frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Let the destination choose: Finder moves on the same volume, copies across
        // volumes; upload targets request copy. Within our own app, no-op.
        context == .outsideApplication ? [.move, .copy] : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        // A move relocated the original, so drop the now-stale shelf entry; a copy
        // (e.g. uploading into another app) leaves the file and entry untouched.
        if operation == .move { onRemove?() }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let reveal = NSMenuItem(
            title: L10n.tr("fileDrop.revealInFinder", "在 Finder 中显示"),
            action: #selector(handleReveal),
            keyEquivalent: ""
        )
        let open = NSMenuItem(
            title: L10n.tr("fileDrop.open", "打开"),
            action: #selector(handleOpen),
            keyEquivalent: ""
        )
        let remove = NSMenuItem(
            title: L10n.tr("fileDrop.remove", "移除"),
            action: #selector(handleRemove),
            keyEquivalent: ""
        )
        for item in [reveal, open] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func handleReveal() { onReveal?() }
    @objc private func handleOpen() { onOpen?() }
    @objc private func handleRemove() { onRemove?() }
}
