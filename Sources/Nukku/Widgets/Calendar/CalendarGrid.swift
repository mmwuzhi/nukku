import Foundation

/// Pure date math for the itsycal-style month grid. No EventKit / AppKit, so it
/// is unit-testable on any platform.
enum CalendarGrid {
    /// Number of cells in the month grid: 6 weeks × 7 days.
    static let cellCount = 42

    /// The 42 start-of-day dates for the grid containing `date`'s month, starting
    /// from the first weekday of the week that contains the 1st of the month.
    static func days(forMonthOf date: Date, calendar: Calendar = .current) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -leading,
            to: calendar.startOfDay(for: firstOfMonth)
        ) ?? firstOfMonth
        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Localized one-letter-ish weekday symbols ordered to match `firstWeekday`.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + offset) % 7] }
    }

    static func isSameMonth(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    /// Start-of-day values an event covers, clamped to `[gridStart, gridLast]`.
    /// `end` is treated as exclusive (EventKit's convention), so an event ending
    /// exactly at a midnight boundary does not include that day. Zero-length
    /// events keep their start day.
    static func coveredDays(
        start: Date,
        end: Date,
        gridStart: Date,
        gridLast: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let endRef = end > start ? end.addingTimeInterval(-1) : end
        var day = max(calendar.startOfDay(for: start), gridStart)
        let lastDay = min(calendar.startOfDay(for: endRef), gridLast)
        var result: [Date] = []
        while day <= lastDay {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
