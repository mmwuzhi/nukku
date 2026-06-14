import Foundation

enum MediaDiagnosticsLogger {
    static let logURL = URL(fileURLWithPath: "/tmp/nukku-media-diagnostics.log")

    static func write(_ message: @autoclosure () -> String) {
        let line = "\(iso8601()) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) == false {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore diagnostic logging failures.
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: logURL)
    }

    private static func iso8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
