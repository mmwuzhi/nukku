import SwiftUI

struct ClockWidgetView: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeString: String {
        now.formatted(date: .omitted, time: .shortened)
    }

    private var dateString: String {
        now.formatted(.dateTime.month(.wide).day().weekday(.wide))
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(timeString)
                .font(.system(size: 36, weight: .thin, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(dateString)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { now = $0 }
    }
}
