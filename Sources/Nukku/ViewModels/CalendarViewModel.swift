import EventKit
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    var events: [EKEvent] = []
    var authStatus: EKAuthorizationStatus = .notDetermined

    private let client = EventKitClient()

    func activate() async {
        await client.requestAccessIfNeeded()
        events = client.events
        authStatus = client.authStatus
    }

    func refresh() {
        client.fetchToday()
        events = client.events
    }
}
