import EventKit
import Foundation
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    var authStatus: EKAuthorizationStatus = .notDetermined
    var visibleMonth: Date = Date()
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    var eventsByDay: [Date: [EKEvent]] = [:]
    var calendars: [EKCalendar] = []

    private let client = EventKitClient()
    private var refreshTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?

    // MARK: - Derived

    var gridDays: [Date] { CalendarGrid.days(forMonthOf: visibleMonth) }

    var selectedDayEvents: [EKEvent] {
        eventsByDay[Calendar.current.startOfDay(for: selectedDate)] ?? []
    }

    var monthTitle: String {
        visibleMonth.formatted(.dateTime.year().month(.wide))
    }

    func hasEvents(on day: Date) -> Bool {
        !(eventsByDay[Calendar.current.startOfDay(for: day)] ?? []).isEmpty
    }

    func isInVisibleMonth(_ day: Date) -> Bool {
        CalendarGrid.isSameMonth(day, visibleMonth)
    }

    // MARK: - Lifecycle

    func activate() async {
        await client.requestAccessIfNeeded()
        authStatus = client.authStatus
        guard authStatus == .fullAccess else { return }
        calendars = client.allCalendars()
        reload()
        startAutoRefresh()
    }

    // MARK: - Calendar visibility

    func isHidden(_ calendar: EKCalendar) -> Bool {
        PreferencesManager.shared.hiddenCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        var hidden = PreferencesManager.shared.hiddenCalendarIDs
        let id = calendar.calendarIdentifier
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        PreferencesManager.shared.hiddenCalendarIDs = hidden
        reload()
    }

    func deactivate() {
        stopAutoRefresh()
    }

    // MARK: - Navigation

    func goToPreviousMonth() { shiftMonth(-1) }
    func goToNextMonth() { shiftMonth(1) }

    func goToToday() {
        visibleMonth = .now
        selectedDate = Calendar.current.startOfDay(for: .now)
        reload()
    }

    func select(_ day: Date) {
        selectedDate = Calendar.current.startOfDay(for: day)
    }

    private func shiftMonth(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: delta, to: visibleMonth)
        else { return }
        visibleMonth = next
        // Keep the selection inside the visible month so the day list and the
        // "new event" default day track navigation.
        if cal.isDate(next, equalTo: .now, toGranularity: .month) {
            selectedDate = cal.startOfDay(for: .now)
        } else {
            let comps = cal.dateComponents([.year, .month], from: next)
            selectedDate = cal.date(from: comps) ?? cal.startOfDay(for: next)
        }
        reload()
    }

    // MARK: - Editing

    var writableCalendars: [EKCalendar] { client.writableCalendars() }

    func makeNewEvent(on day: Date) -> EKEvent {
        let event = client.makeEvent()
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        event.startDate = start
        event.endDate = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        event.calendar = preferredDefaultCalendar()
        return event
    }

    /// Avoid defaulting new events to a UUID-named local calendar: prefer the
    /// system default when it has a readable name, otherwise the first writable
    /// calendar with a real name.
    private func preferredDefaultCalendar() -> EKCalendar? {
        let writable = writableCalendars
        if let def = client.defaultCalendar(),
           def.hasReadableTitle,
           writable.contains(where: { $0.calendarIdentifier == def.calendarIdentifier }) {
            return def
        }
        return writable.first(where: { $0.hasReadableTitle }) ?? writable.first
    }

    @discardableResult
    func save(_ event: EKEvent) -> Bool {
        do {
            try client.save(event)
            reload()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func delete(_ event: EKEvent) -> Bool {
        do {
            try client.delete(event)
            reload()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Data

    func reload() {
        guard authStatus == .fullAccess else { return }
        eventsByDay = client.events(
            forMonth: visibleMonth,
            hiddenCalendarIDs: PreferencesManager.shared.hiddenCalendarIDs
        )
    }

    // MARK: - Auto refresh

    private func startAutoRefresh() {
        stopAutoRefresh()

        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.calendars = self.client.allCalendars()
                self.reload()
            }
        }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                reload()
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
