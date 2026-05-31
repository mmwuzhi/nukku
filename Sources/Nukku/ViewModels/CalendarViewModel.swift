import EventKit
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    var events: [EKEvent] = []
    var authStatus: EKAuthorizationStatus = .notDetermined

    private let client = EventKitClient()
    private var refreshTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?

    func activate() async {
        await client.requestAccessIfNeeded()
        events = client.events
        authStatus = client.authStatus
        guard authStatus == .fullAccess || authStatus == .authorized else { return }
        startAutoRefresh()
    }

    func deactivate() {
        stopAutoRefresh()
    }

    func refresh() {
        client.fetchToday()
        events = client.events
    }

    // MARK: - Auto refresh

    private func startAutoRefresh() {
        stopAutoRefresh()

        // Respond immediately to EventKit store changes (new/edited events)
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        // Periodic poll every 30 s (catches day-change edge cases)
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        if let observer = storeObserver {
            NotificationCenter.default.removeObserver(observer)
            storeObserver = nil
        }
    }
}
