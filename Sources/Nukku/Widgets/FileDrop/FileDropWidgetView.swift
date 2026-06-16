import SwiftUI

struct FileDropWidgetView: View {
    @Environment(FileDropViewModel.self) private var vm
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if vm.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("拖拽文件到此处")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.files) { file in
                            FileItemView(file: file, vm: vm)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.nukkuAccent : Color.nukkuSeparator,
                    lineWidth: isTargeted ? 2 : 1
                )
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted, perform: vm.handleDrop)
    }
}

private struct FileItemView: View {
    let file: FileDropViewModel.DroppedFile
    let vm: FileDropViewModel

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let icon = file.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 38, height: 38)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
            Text(file.name)
                .font(.system(size: 11))
                .foregroundStyle(Color.nukkuSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .contentShape(Rectangle())
        .help(file.name)
        .overlay(
            FileItemInteraction(
                url: file.url,
                icon: file.icon,
                onOpen: { vm.open(file) },
                onReveal: { vm.reveal(file) },
                onRemove: { vm.remove(file) }
            )
        )
    }
}
