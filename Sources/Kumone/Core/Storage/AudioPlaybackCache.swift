import CryptoKit
import Foundation

/// Persistent cache for audio heard through the online player.
///
/// This cache is intentionally separate from `DownloadManager`: cached online
/// playback is an implementation detail and is never shown as an offline
/// download in the user's library.
actor AudioPlaybackCache {
    static let shared = AudioPlaybackCache()

    private let fileManager = FileManager.default
    private let directory: URL
    private var tasks: [String: Task<Void, Never>] = [:]
    private var tokens: [String: UUID] = [:]
    private var generation = 0

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("im.missuo.Kumone/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedFile(for trackID: Int, variant: String, fileExtension: String) -> URL? {
        let url = fileURL(for: trackID, variant: variant, fileExtension: fileExtension)
        guard fileManager.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0
        else { return nil }
        return url
    }

    /// Starts caching without delaying playback. The current player continues
    /// streaming from `sourceURL` while this task writes a separate cache file.
    func cache(sourceURL: URL, for trackID: Int, variant: String, fileExtension: String) {
        let key = Self.cacheKey(trackID: trackID, variant: variant)
        guard tasks[key] == nil else { return }

        let destination = fileURL(
            for: trackID,
            variant: variant,
            fileExtension: fileExtension
        )
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let token = UUID()
        let cacheGeneration = self.generation
        tokens[key] = token
        tasks[key] = Task { [weak self] in
            await self?.download(
                sourceURL: sourceURL,
                destination: destination,
                key: key,
                token: token,
                generation: cacheGeneration
            )
        }
    }

    func size() -> Int64 {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )) ?? []
        return urls.reduce(into: Int64(0)) { result, url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { return }
            result += Int64(values.fileSize ?? 0)
        }
    }

    func clear() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        tokens.removeAll()
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func download(
        sourceURL: URL,
        destination: URL,
        key: String,
        token: UUID,
        generation: Int
    ) async {
        var temporaryURL: URL?
        defer {
            if let temporaryURL {
                try? fileManager.removeItem(at: temporaryURL)
            }
            if tokens[key] == token {
                tokens.removeValue(forKey: key)
                tasks.removeValue(forKey: key)
            }
        }

        do {
            let (url, response) = try await URLSession.shared.download(from: sourceURL)
            temporaryURL = url
            guard !Task.isCancelled, generation == self.generation,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }

            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: url, to: destination)
            temporaryURL = nil
        } catch {
            // Online playback must never fail just because its optional cache
            // request failed or was cancelled.
        }
    }

    private func fileURL(for trackID: Int, variant: String, fileExtension: String) -> URL {
        let key = Self.cacheKey(trackID: trackID, variant: variant)
        let ext = Self.sanitizedExtension(fileExtension)
        return directory.appendingPathComponent("\(key).\(ext)", isDirectory: false)
    }

    private static func cacheKey(trackID: Int, variant: String) -> String {
        let digest = SHA256.hash(data: Data("\(trackID)|\(variant)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitizedExtension(_ value: String) -> String {
        let extensionValue = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return extensionValue.isEmpty ? "audio" : extensionValue
    }
}
