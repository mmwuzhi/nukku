import Darwin
import Foundation

@MainActor
final class NetworkMonitor {
    private(set) var uploadBytesPerSec: Int64 = 0
    private(set) var downloadBytesPerSec: Int64 = 0
    private var prevUpload: Int64 = 0
    private var prevDownload: Int64 = 0

    func sample() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return }
        defer { freeifaddrs(head) }

        var up: Int64 = 0
        var down: Int64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = head

        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let isLoopback = flags & IFF_LOOPBACK != 0
            let isUp = flags & IFF_UP != 0
            let isLink = cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)

            if !isLoopback && isUp && isLink,
               let rawData = cur.pointee.ifa_data {
                let data = rawData.load(as: if_data.self)
                up   += Int64(data.ifi_obytes)
                down += Int64(data.ifi_ibytes)
            }
            ptr = cur.pointee.ifa_next
        }

        uploadBytesPerSec   = up   - prevUpload
        downloadBytesPerSec = down - prevDownload
        prevUpload   = up
        prevDownload = down
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let abs = Swift.abs(bytes)
        switch abs {
        case 0..<1_024:               return "\(abs) B/s"
        case 0..<1_048_576:           return String(format: "%.1f KB/s", Double(abs) / 1_024)
        default:                      return String(format: "%.1f MB/s", Double(abs) / 1_048_576)
        }
    }
}
