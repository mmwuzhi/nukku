import SwiftUI
import EventKit

struct EventEditView: View {
    @Environment(CalendarViewModel.self) private var vm

    let event: EKEvent
    let isNew: Bool
    let onClose: () -> Void

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var calendar: EKCalendar?
    @State private var saveFailed = false
    @State private var showCalendarPicker = false

    /// Shared width for the leading label column so every row's control starts
    /// at the same x. One value, not per-row magic numbers.
    private let labelWidth: CGFloat = 40

    init(event: EKEvent, isNew: Bool, onClose: @escaping () -> Void) {
        self.event = event
        self.isNew = isNew
        self.onClose = onClose
        _title = State(initialValue: event.title ?? "")
        _isAllDay = State(initialValue: event.isAllDay)
        _start = State(initialValue: event.startDate ?? .now)
        // EK stores all-day endDate as the exclusive next-midnight; show the
        // inclusive last day in the UI.
        let rawEnd = event.endDate ?? event.startDate ?? .now
        if event.isAllDay {
            _end = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: rawEnd) ?? rawEnd)
        } else {
            _end = State(initialValue: rawEnd)
        }
        _calendar = State(initialValue: event.calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            TextField("标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

            // One grouped card for all event attributes, so the controls read
            // as a single block instead of three center-floated rows.
            VStack(spacing: 12) {
                row("全天") {
                    Toggle("", isOn: $isAllDay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                rowDivider
                row("开始") {
                    DateChip(date: $start, includesTime: !isAllDay)
                }
                row("结束") {
                    DateChip(date: $end, includesTime: !isAllDay)
                }
                if !vm.writableCalendars.isEmpty {
                    rowDivider
                    row("日历") {
                        calendarSelector
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if saveFailed {
                Text("保存失败，该日历可能只读")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.9))
            }

            if !isNew {
                Button(role: .destructive) {
                    if vm.delete(event) { onClose() }
                } label: {
                    Text("删除事件")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .tint(.white)
    }

    private var header: some View {
        HStack {
            Button("取消", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button(action: commit) {
                Text("保存")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSave ? .black : .white.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(canSave ? 1.0 : 0.07)))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        // Overlay-center the title so it stays dead-center regardless of the
        // differing widths of the cancel link and the save pill.
        .overlay(
            Text(isNew ? "新建事件" : "编辑事件")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
    }

    /// Dark calendar picker: a themed chip showing the calendar's color dot and
    /// readable title, opening a dark popover list. Replaces the native menu,
    /// which rendered light against the dark form and showed a raw UUID title.
    private var calendarSelector: some View {
        Button { showCalendarPicker.toggle() } label: {
            HStack(spacing: 7) {
                if let calendar {
                    Circle()
                        .fill(Color(cgColor: calendar.cgColor))
                        .frame(width: 8, height: 8)
                    Text(calendar.nukkuDisplayTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("选择日历")
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCalendarPicker, arrowEdge: .bottom) {
            calendarPickerList
        }
    }

    private var calendarPickerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(vm.writableCalendars, id: \.calendarIdentifier) { cal in
                Button {
                    calendar = cal
                    showCalendarPicker = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: 8, height: 8)
                        Text(cal.nukkuDisplayTitle)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        if cal.calendarIdentifier == calendar?.calendarIdentifier {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .background(Color(white: 0.13))
        .environment(\.colorScheme, .dark)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && calendar != nil && end >= start
    }

    private func commit() {
        guard let calendar else { return }
        let cal = Calendar.current
        // Snapshot so a failed save (e.g. read-only calendar) does not leave the
        // shared EKEvent mutated in the visible list.
        let original = (event.title, event.isAllDay, event.startDate, event.endDate, event.calendar)

        event.title = title
        event.isAllDay = isAllDay
        event.calendar = calendar
        if isAllDay {
            event.startDate = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: end)
            event.endDate = cal.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        } else {
            event.startDate = start
            event.endDate = end
        }

        if vm.save(event) {
            onClose()
        } else {
            event.title = original.0
            event.isAllDay = original.1
            event.startDate = original.2
            event.endDate = original.3
            event.calendar = original.4
            saveFailed = true
        }
    }
}

/// A dark, theme-matching date/time control. Shows a compact pill; tapping opens
/// a graphical calendar popover. Replaces the raw gray macOS stepper field that
/// looked dropped-in against the dark form.
private struct DateChip: View {
    @Binding var date: Date
    let includesTime: Bool
    @State private var open = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: date))
                    .foregroundStyle(.white)
                if includesTime {
                    Text(Self.timeFormatter.string(from: date))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DatePicker("", selection: $date,
                       displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.white)
                .padding(12)
                .frame(width: 260)
                .background(Color(white: 0.13))
                .environment(\.colorScheme, .dark)
        }
    }
}
