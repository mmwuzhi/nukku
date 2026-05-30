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
        VStack(spacing: 4) {
            Group {
                if let icon = file.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            Text(file.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 48)
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.open(file) }
        .contextMenu {
            Button("在 Finder 中显示") { vm.reveal(file) }
            Button("打开") { vm.open(file) }
            Divider()
            Button("移除", role: .destructive) { vm.remove(file) }
        }
    }
}
