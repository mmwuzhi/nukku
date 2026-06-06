import SwiftUI

struct ShortcutsWidgetView: View {
    @Environment(ShortcutsViewModel.self) private var vm
    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if vm.shortcuts.isEmpty {
                emptyState
            } else {
                shortcutsList
            }

            Divider()
                .background(Color.nukkuSeparator)
                .padding(.top, 4)

            addRow
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shortcutsList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(vm.shortcuts) { item in
                    shortcutRow(item)
                }
            }
        }
    }

    private func shortcutRow(_ item: ShortcutsViewModel.ShortcutItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button { vm.run(item) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            Button { vm.remove(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text("在「快捷指令」里创建快捷方式")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("在下方输入名称添加")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("快捷方式名称…", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit { commitAdd() }
            Button { commitAdd() } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func commitAdd() {
        vm.add(newName)
        newName = ""
    }
}
