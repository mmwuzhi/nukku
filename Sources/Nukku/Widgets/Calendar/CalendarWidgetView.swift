import SwiftUI
import EventKit

struct CalendarWidgetView: View {
    @Environment(CalendarViewModel.self) private var vm
    @State private var showFilter = false
    @State private var editing: EditingContext?

    private struct EditingContext: Identifiable {
        let id = UUID()
        let event: EKEvent
        let isNew: Bool
    }

    var body: some View {
        if vm.authStatus != .fullAccess {
            permissionPrompt
        } else {
            ZStack {
                VStack(spacing: 6) {
                    header
                    MonthGridView()
                    Divider().background(Color.nukkuSeparator)
                    dayList
                }
                if let editing {
                    EventEditView(event: editing.event, isNew: editing.isNew) {
                        self.editing = nil
                    }
                    .environment(vm)
                    .padding(10)
                    .background(Color.nukkuBackground, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addEvent() {
        editing = EditingContext(event: vm.makeNewEvent(on: vm.selectedDate), isNew: true)
    }

    private func edit(_ event: EKEvent) {
        editing = EditingContext(event: event, isNew: false)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(vm.monthTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button { showFilter.toggle() } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("选择显示的日历")
            .popover(isPresented: $showFilter, arrowEdge: .bottom) {
                CalendarFilterView().environment(vm)
            }
            navButton("chevron.left") { vm.goToPreviousMonth() }
            Button { vm.goToToday() } label: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("回到今天")
            navButton("chevron.right") { vm.goToNextMonth() }
            Button(action: addEvent) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("新建事件")
        }
    }

    private func navButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day list

    private var dayList: some View {
        Group {
            if vm.selectedDayEvents.isEmpty {
                Text("无日程")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.selectedDayEvents, id: \.eventIdentifier) { event in
                            EventRow(event: event)
                                .onTapGesture { edit(event) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission

    private var permissionPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("需要日历访问权限")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Month grid

private struct MonthGridView: View {
    @Environment(CalendarViewModel.self) private var vm

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(vm.gridDays, id: \.self) { day in
                    DayCell(
                        day: day,
                        inMonth: vm.isInVisibleMonth(day),
                        isToday: Calendar.current.isDateInToday(day),
                        isSelected: Calendar.current.isDate(day, inSameDayAs: vm.selectedDate),
                        hasEvents: vm.hasEvents(on: day)
                    )
                    .onTapGesture { vm.select(day) }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    private var numberColor: Color {
        if isToday { return .white }
        return inMonth ? .white.opacity(0.85) : .white.opacity(0.25)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(dayNumber)
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 22, height: 18)
                .background {
                    if isToday {
                        Circle().fill(Color.red)
                    } else if isSelected {
                        Circle().fill(Color.white.opacity(0.18))
                    }
                }
            Circle()
                .fill(hasEvents ? Color.white.opacity(0.55) : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(Rectangle())
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: EKEvent

    private var timeString: String {
        if event.isAllDay { return "全天" }
        return event.startDate.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "无标题")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
