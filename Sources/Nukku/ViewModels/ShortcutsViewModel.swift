import AppKit
import Observation

@Observable
@MainActor
final class ShortcutsViewModel {
    struct ShortcutItem: Identifiable {
        let id = UUID()
        let name: String
    }

    // Plain stored property — @Observable tracks mutations, we persist manually.
    private var csv: String

    init() {
        csv = UserDefaults.standard.string(forKey: "userShortcuts") ?? ""
    }

    var shortcuts: [ShortcutItem] {
        csv.split(separator: "\n", omittingEmptySubsequences: true)
            .map { ShortcutItem(name: String($0)) }
    }

    func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !shortcuts.map(\.name).contains(trimmed) else { return }
        csv = csv.isEmpty ? trimmed : (csv + "\n" + trimmed)
        persist()
    }

    func remove(_ item: ShortcutItem) {
        let remaining = shortcuts.filter { $0.name != item.name }.map(\.name)
        csv = remaining.joined(separator: "\n")
        persist()
    }

    func run(_ item: ShortcutItem) {
        guard let encoded = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func persist() {
        UserDefaults.standard.set(csv, forKey: "userShortcuts")
    }
}
