import SwiftUI
import EventKit

struct CalendarFilterView: View {
    @Environment(CalendarViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("显示的日历")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.calendars, id: \.calendarIdentifier) { calendar in
                        row(calendar)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: 280)
    }

    private func row(_ calendar: EKCalendar) -> some View {
        Button {
            vm.toggleCalendar(calendar)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: vm.isHidden(calendar) ? "square" : "checkmark.square.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(vm.isHidden(calendar) ? Color.secondary : Color.accentColor)
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 8, height: 8)
                Text(calendar.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}
