import SwiftUI

/// The visible drop affordance shown below the notch while a file drag is in
/// flight. Performs the drop via the SwiftUI `.onDrop` so it gets the standard
/// `isTargeted` highlight for free.
struct NotchDropTrayView: View {
    let onDrop: ([URL]) -> Void
    /// Reports hover state so the window owner can keep the tray alive while the
    /// drag is over it (the detector strip fires draggingExited during handoff).
    let onTargetedChange: (Bool) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isTargeted ? Color.nukkuAccent : Color.nukkuSecondaryLabel)
            Text(L10n.tr("fileDrop.tray", "拖到这里暂存"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isTargeted ? Color.nukkuLabel : Color.nukkuSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.nukkuBackground.opacity(isTargeted ? 0.92 : 0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.nukkuAccent : Color.nukkuSeparator,
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [7, 5])
                )
        )
        .scaleEffect(isTargeted ? 1.0 : 0.97)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(10)
        .animation(.easeOut(duration: 0.16), value: isTargeted)
        .onChange(of: isTargeted) { _, targeted in onTargetedChange(targeted) }
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                guard !urls.isEmpty else { return }
                onDrop(urls)
            }
            return true
        }
    }
}
