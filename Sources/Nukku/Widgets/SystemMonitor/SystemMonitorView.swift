import SwiftUI

struct SystemMonitorView: View {
    @Environment(SystemMonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                StatBlock(label: "CPU", value: String(format: "%.0f%%", vm.cpuUsage * 100), history: vm.cpuHistory)
                StatBlock(label: "内存", value: String(format: "%.0f%%", vm.memoryInfo.ratio * 100), history: vm.memHistory)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(NetworkMonitor.formatBytes(vm.uploadBytesPerSec))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(NetworkMonitor.formatBytes(vm.downloadBytesPerSec))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatBlock: View {
    let label: String
    let value: String
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            SparklineView(data: history)
                .frame(height: 28)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SparklineView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = w / CGFloat(max(data.count - 1, 1))

            Path { path in
                for (i, v) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - CGFloat(v) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.nukkuAccent, lineWidth: 1.5)
        }
    }
}
