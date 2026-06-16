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
        VStack(spacing: 8) {
            HStack {
                Button("取消", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(isNew ? "新建事件" : "编辑事件")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("保存", action: commit)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSave ? .white : .white.opacity(0.3))
                    .disabled(!canSave)
            }

            TextField("标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Toggle("全天", isOn: $isAllDay)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .toggleStyle(.switch)
                .controlSize(.mini)

            DatePicker("开始", selection: $start,
                       displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
            DatePicker("结束", selection: $end,
                       displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))

            if !vm.writableCalendars.isEmpty {
                Picker("日历", selection: $calendar) {
                    ForEach(vm.writableCalendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal as EKCalendar?)
                    }
                }
                .font(.system(size: 11))
                .controlSize(.small)
            }

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
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .tint(.white)
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
