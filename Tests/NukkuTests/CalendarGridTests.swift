import Testing
import Foundation
@testable import Nukku

@Suite("Calendar grid")
struct CalendarGridTests {
    private func gregorian(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = firstWeekday
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Grid always has 42 cells")
    func cellCount() {
        let cal = gregorian(firstWeekday: 1)
        let days = CalendarGrid.days(forMonthOf: date(2026, 6, 15, cal), calendar: cal)
        #expect(days.count == 42)
    }

    @Test("First cell matches firstWeekday (Sunday start)")
    func sundayStart() {
        let cal = gregorian(firstWeekday: 1) // Sunday
        // June 2026: the 1st is a Monday, so the grid starts on Sunday May 31.
        let days = CalendarGrid.days(forMonthOf: date(2026, 6, 10, cal), calendar: cal)
        #expect(cal.component(.weekday, from: days[0]) == 1)
        #expect(cal.isDate(days[0], inSameDayAs: date(2026, 5, 31, cal)))
    }

    @Test("First cell matches firstWeekday (Monday start)")
    func mondayStart() {
        let cal = gregorian(firstWeekday: 2) // Monday
        let days = CalendarGrid.days(forMonthOf: date(2026, 6, 10, cal), calendar: cal)
        #expect(cal.component(.weekday, from: days[0]) == 2)
        // June 1 2026 is a Monday, so the grid begins exactly on June 1.
        #expect(cal.isDate(days[0], inSameDayAs: date(2026, 6, 1, cal)))
    }

    @Test("Grid contains every day of the target month")
    func containsAllDays() {
        let cal = gregorian(firstWeekday: 1)
        let days = CalendarGrid.days(forMonthOf: date(2026, 2, 15, cal), calendar: cal)
        for d in 1...28 {
            let target = date(2026, 2, d, cal)
            #expect(days.contains { cal.isDate($0, inSameDayAs: target) })
        }
    }

    @Test("Year boundary: December grid includes January days")
    func yearBoundary() {
        let cal = gregorian(firstWeekday: 1)
        let days = CalendarGrid.days(forMonthOf: date(2026, 12, 15, cal), calendar: cal)
        #expect(days.contains { cal.isDate($0, inSameDayAs: date(2027, 1, 1, cal)) })
    }

    @Test("isSameMonth distinguishes adjacent months")
    func sameMonth() {
        let cal = gregorian(firstWeekday: 1)
        #expect(CalendarGrid.isSameMonth(date(2026, 6, 1, cal), date(2026, 6, 30, cal), calendar: cal))
        #expect(!CalendarGrid.isSameMonth(date(2026, 6, 30, cal), date(2026, 7, 1, cal), calendar: cal))
    }

    private func dateTime(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test("coveredDays: timed event ending at midnight stays on its start day")
    func endsAtMidnight() {
        let cal = gregorian(firstWeekday: 1)
        let start = dateTime(2026, 6, 10, 21, 0, cal)
        let end = date(2026, 6, 11, cal) // next midnight, exclusive
        let days = CalendarGrid.coveredDays(
            start: start, end: end,
            gridStart: date(2026, 5, 31, cal), gridLast: date(2027, 1, 1, cal),
            calendar: cal
        )
        #expect(days.count == 1)
        #expect(cal.isDate(days[0], inSameDayAs: date(2026, 6, 10, cal)))
    }

    @Test("coveredDays: multi-day event spans each covered day")
    func multiDaySpan() {
        let cal = gregorian(firstWeekday: 1)
        let days = CalendarGrid.coveredDays(
            start: dateTime(2026, 6, 10, 9, 0, cal),
            end: dateTime(2026, 6, 12, 17, 0, cal),
            gridStart: date(2026, 5, 31, cal), gridLast: date(2027, 1, 1, cal),
            calendar: cal
        )
        #expect(days.count == 3)
    }

    @Test("coveredDays: zero-length event keeps its start day")
    func zeroLength() {
        let cal = gregorian(firstWeekday: 1)
        let instant = dateTime(2026, 6, 10, 9, 0, cal)
        let days = CalendarGrid.coveredDays(
            start: instant, end: instant,
            gridStart: date(2026, 5, 31, cal), gridLast: date(2027, 1, 1, cal),
            calendar: cal
        )
        #expect(days.count == 1)
        #expect(cal.isDate(days[0], inSameDayAs: date(2026, 6, 10, cal)))
    }

    @Test("coveredDays: clamps a years-spanning event to the grid window")
    func clampsToGrid() {
        let cal = gregorian(firstWeekday: 1)
        let gridStart = date(2026, 5, 31, cal)
        let gridLast = date(2026, 7, 11, cal)
        let days = CalendarGrid.coveredDays(
            start: date(2020, 1, 1, cal),
            end: date(2030, 1, 1, cal),
            gridStart: gridStart, gridLast: gridLast,
            calendar: cal
        )
        #expect(days.first == gridStart)
        #expect(days.last == gridLast)
        #expect(days.count == 42)
    }
}
