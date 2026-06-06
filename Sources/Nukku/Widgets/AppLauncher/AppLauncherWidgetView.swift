import SwiftUI
import AppKit

struct AppLauncherWidgetView: View {
    @Environment(AppLauncherViewModel.self) private var vm
    @State private var deleteTargetID: String? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(vm.apps) { app in
                    appCell(app)
                }
                if vm.apps.count < 8 {
                    addCell
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appCell(_ app: AppLauncherViewModel.PinnedApp) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                deleteTargetID = nil
                vm.launch(app)
            } label: {
                VStack(spacing: 4) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                    Text(app.name)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 56)
                }
                .padding(6)
                .frame(width: 68, height: 64)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    deleteTargetID = app.id
                }
            )

            if deleteTargetID == app.id {
                Button {
                    vm.remove(app)
                    deleteTargetID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }

    private var addCell: some View {
        Button { vm.pickApp() } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.65))
                Text("添加")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .frame(width: 68, height: 64)
            .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
