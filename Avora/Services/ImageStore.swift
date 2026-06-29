import UIKit
import CryptoKit

/// Caches remote images keyed by their stable storage `path`.
///
/// Signed URLs from `signedOutputURL` carry a fresh token on every call and
/// expire after an hour, so they can't be used as a cache key. The storage
/// path is the immutable identity of an image, and stored images never change
/// content, so we key memory + disk on the path (plus its source) and only
/// resolve a URL on a genuine miss.
actor ImageStore {
    static let shared = ImageStore()

    /// Which bucket a path lives in, and therefore how its URL is resolved.
    enum Source {
        /// Private per-user `outputs` bucket — resolved via short-lived signed URLs.
        case output
        /// Public `assets` bucket (e.g. style samples) — resolved via stable public URLs.
        case sample
    }

    enum Failure: Error { case decode }

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func image(for path: String, source: Source = .output) async throws -> UIImage {
        let cacheKey = "\(source):\(path)"
        let key = cacheKey as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let existing = inFlight[cacheKey] { return try await existing.value }

        let task = Task<UIImage, Error> { try await self.load(path: path, source: source) }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }

        let image = try await task.value
        memory.setObject(image, forKey: key)
        return image
    }

    private func load(path: String, source: Source) async throws -> UIImage {
        let fileURL = dir.appendingPathComponent(filename(for: "\(source):\(path)"))
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            return image
        }
        let url: URL
        switch source {
        case .output: url = try await AvoraAPI.shared.signedOutputURL(path)
        case .sample: url = try await AvoraAPI.shared.sampleURL(path)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw Failure.decode }
        try? data.write(to: fileURL, options: .atomic)
        return image
    }

    private func filename(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
