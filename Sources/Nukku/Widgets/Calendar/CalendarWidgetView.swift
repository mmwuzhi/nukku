import SwiftUI
import EventKit

struct CalendarWidgetView: View {
    @Environment(CalendarViewModel.self) private var vm

    var body: some View {
        if vm.authStatus != .fullAccess && vm.authStatus != .authorized {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("需要日历访问权限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("今日无日程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.events, id: \.eventIdentifier) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

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
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "无标题")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
