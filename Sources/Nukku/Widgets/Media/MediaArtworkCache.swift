import AppKit
import CryptoKit
import Foundation

@MainActor
final class MediaArtworkCache {
    static let shared = MediaArtworkCache()

    private let maxImageBytes = 10_000_000
    private let cacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = base
            .appendingPathComponent("Nukku", isDirectory: true)
            .appendingPathComponent("MediaArtwork", isDirectory: true)
    }

    func image(from urlString: String?) async -> NSImage? {
        guard let urlString,
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }

        let fileURL = cacheDirectory.appendingPathComponent(cacheKey(for: urlString))
        if let cached = NSImage(contentsOf: fileURL) {
            return cached
        }

        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: request)
            guard data.count <= maxImageBytes, let image = NSImage(data: data) else {
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func cacheKey(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }
}
