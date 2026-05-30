import Foundation
import Observation

@Observable
@MainActor
final class SystemMonitorViewModel {
    var cpuUsage: Double = 0
    var memoryInfo = MemoryMonitor.Info(usedBytes: 0, totalBytes: 1)
    var uploadBytesPerSec: Int64 = 0
    var downloadBytesPerSec: Int64 = 0

    // Rolling history for sparkline charts (last 60 samples)
    var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    var memHistory: [Double] = Array(repeating: 0, count: 60)

    private let cpu = CPUMonitor()
    private let mem = MemoryMonitor()
    private let net = NetworkMonitor()
    private var samplerTask: Task<Void, Never>?

    func start() {
        guard samplerTask == nil else { return }
        samplerTask = Task {
            while !Task.isCancelled {
                sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
    }

    private func sample() {
        cpuUsage = cpu.currentUsage()
        memoryInfo = mem.currentInfo()
        net.sample()
        uploadBytesPerSec = net.uploadBytesPerSec
        downloadBytesPerSec = net.downloadBytesPerSec

        cpuHistory.removeFirst()
        cpuHistory.append(cpuUsage)
        memHistory.removeFirst()
        memHistory.append(memoryInfo.ratio)
    }
}
