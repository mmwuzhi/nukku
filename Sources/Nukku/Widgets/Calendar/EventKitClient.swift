import EventKit
import Observation

@Observable
@MainActor
final class EventKitClient {
    private let store = EKEventStore()

    var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    func requestAccessIfNeeded() async {
        guard authStatus == .notDetermined else { return }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authStatus = granted ? .fullAccess : .denied
    }

    /// Fetch every event intersecting the 6×7 grid for `month`, grouped by
    /// start-of-day. A multi-day event appears under every grid day it spans.
    func events(forMonth month: Date, hiddenCalendarIDs: Set<String> = []) -> [Date: [EKEvent]] {
        let cal = Calendar.current
        let days = CalendarGrid.days(forMonthOf: month, calendar: cal)
        guard let gridStart = days.first,
              let gridLast = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: gridLast) else {
            return [:]
        }

        let calendars = visibleCalendars(hiddenCalendarIDs: hiddenCalendarIDs)
        // An empty selection means "show nothing"; nil would mean "show all".
        if calendars?.isEmpty == true { return [:] }

        let predicate = store.predicateForEvents(withStart: gridStart, end: end, calendars: calendars)
        var grouped: [Date: [EKEvent]] = [:]
        for event in store.events(matching: predicate) {
            let rawEnd: Date = event.endDate ?? event.startDate
            let days = CalendarGrid.coveredDays(
                start: event.startDate,
                end: rawEnd,
                gridStart: gridStart,
                gridLast: gridLast,
                calendar: cal
            )
            for day in days {
                grouped[day, default: []].append(event)
            }
        }
        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
        }
        return grouped
    }

    /// All event calendars known to macOS, including synced accounts (Google, etc.).
    func allCalendars() -> [EKCalendar] {
        store.calendars(for: .event).sorted { $0.nukkuDisplayTitle < $1.nukkuDisplayTitle }
    }

    /// Calendars that accept new/edited events (excludes read-only subscriptions).
    func writableCalendars() -> [EKCalendar] {
        allCalendars().filter { $0.allowsContentModifications }
    }

    func defaultCalendar() -> EKCalendar? {
        store.defaultCalendarForNewEvents
    }

    func makeEvent() -> EKEvent {
        EKEvent(eventStore: store)
    }

    func save(_ event: EKEvent) throws {
        try store.save(event, span: .thisEvent, commit: true)
    }

    func delete(_ event: EKEvent) throws {
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func visibleCalendars(hiddenCalendarIDs: Set<String>) -> [EKCalendar]? {
        guard !hiddenCalendarIDs.isEmpty else { return nil }
        return allCalendars().filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }
}

extension EKCalendar {
    /// `true` when the raw title is a usable name. Some local "On My Mac"
    /// calendars carry a bare UUID as their title; those are not readable.
    var hasReadableTitle: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && UUID(uuidString: t) == nil
    }

    /// Human-readable title for display. Falls back to the account/source name,
    /// then a generic label, when the raw title is empty or a bare UUID.
    var nukkuDisplayTitle: String {
        if hasReadableTitle { return title.trimmingCharacters(in: .whitespacesAndNewlines) }
        let src = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return src.isEmpty ? L10n.tr("calendar.localCalendar", "本地日历") : src
    }

    /// The account this calendar belongs to (iCloud / a Google address / 本地 …),
    /// so the user can tell which calendars come from which connected account.
    var nukkuSourceLabel: String {
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source.sourceType {
        case .local:      return L10n.tr("calendar.local", "本地")
        case .birthdays:  return L10n.tr("calendar.birthdays", "通讯录")
        case .subscribed: return title.isEmpty ? L10n.tr("calendar.subscribed", "订阅") : title
        default:          return title.isEmpty ? L10n.tr("calendar.other", "其他") : title
        }
    }
}
