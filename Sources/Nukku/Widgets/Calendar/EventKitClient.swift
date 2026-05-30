import EventKit
import Observation

@Observable
@MainActor
final class EventKitClient {
    private let store = EKEventStore()
    var events: [EKEvent] = []
    var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    func requestAccessIfNeeded() async {
        guard authStatus == .notDetermined else {
            if authStatus == .fullAccess || authStatus == .authorized {
                fetchToday()
            }
            return
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            authStatus = granted ? .fullAccess : .denied
            if granted { fetchToday() }
        } catch {
            authStatus = .denied
        }
    }

    func fetchToday() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
