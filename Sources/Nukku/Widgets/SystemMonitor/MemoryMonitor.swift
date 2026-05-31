import Darwin
import Foundation

struct MemoryMonitor {
    struct Info {
        let usedBytes: UInt64
        let totalBytes: UInt64
        var ratio: Double { Double(usedBytes) / Double(max(totalBytes, 1)) }
    }

    func currentInfo() -> Info {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let page = UInt64(pageSize)
            used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        }
        return Info(usedBytes: used, totalBytes: total)
    }
}
