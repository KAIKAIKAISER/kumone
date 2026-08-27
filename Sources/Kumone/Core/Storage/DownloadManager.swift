import Combine
import Foundation

private struct DownloadTaskResult {
    let url: URL
    let response: URLResponse
}

/// Bridges URLSession's delegate-based download task to async/await. The
/// system download task writes network data directly to disk and reports
/// progress in chunks, avoiding the per-byte overhead of AsyncBytes.
private final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    let onProgress: (Int64, Int64) -> Void

    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<DownloadTaskResult, Error>?
    private var finishedURL: URL?
    private var failure: Error?

    init(destinationURL: URL, onProgress: @escaping (Int64, Int64) -> Void) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
    }

    deinit {
        try? FileManager.default.removeItem(at: destinationURL)
    }

    func start(session: URLSession, url: URL) async throws -> DownloadTaskResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finishedURL = destinationURL
        } catch {
            failure = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let finishedURL, let response = self.downloadTask?.response {
            continuation.resume(returning: DownloadTaskResult(url: finishedURL, response: response))
        } else {
            let error = NSError(
                domain: "Kumone.Download",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Download did not produce a file"]
            )
            continuation.resume(throwing: error)
        }
    }
}

/// Downloads online tracks into the app's sandbox so they can be played again
/// without resolving a new network URL. The files are intentionally kept
/// private to the app; iOS does not allow third-party apps to write into the
/// user's Apple Music library.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloadedIDs: Set<Int> = []
    @Published private(set) var downloadingIDs: Set<Int> = []
    @Published private(set) var downloadedTracks: [DownloadedTrack] = []
    @Published private(set) var activeProgress: [Int: DownloadProgress] = [:]

    struct DownloadedTrack: Identifiable {
        let track: Track
        let url: URL
        let fileSize: Int64

        var id: Int { track.id }
    }

    struct DownloadProgress: Identifiable {
        let track: Track
        let downloadedBytes: Int64
        let totalBytes: Int64?
        let speedBytesPerSecond: Double

        var id: Int { track.id }

        var fractionCompleted: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
        }

        var statusText: String {
            let speed = ByteCountFormatter.string(
                fromByteCount: Int64(max(0, speedBytesPerSecond)),
                countStyle: .file
            )
            if let totalBytes, totalBytes > 0 {
                let percent = Int((Double(downloadedBytes) / Double(totalBytes) * 100).rounded())
                return "\(percent)% · \(speed)/s"
            }
            let downloaded = ByteCountFormatter.string(
                fromByteCount: downloadedBytes,
                countStyle: .file
            )
            return "\(downloaded) · \(speed)/s"
        }
    }

    private struct ResolvedSource {
        let url: URL
        let fileExtension: String
    }

    private enum DownloadError: LocalizedError {
        case sourceUnavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable:
                return String(localized: "无法获取歌曲下载地址")
            case .invalidResponse:
                return String(localized: "歌曲下载响应无效")
            }
        }
    }

    private var downloadedFiles: [Int: URL] = [:]
    private var downloadedTrackMetadata: [Int: Track] = [:]
    private var downloadTasks: [Int: Task<Void, Never>] = [:]
    private var downloadTokens: [Int: UUID] = [:]
    private var progressSamples: [Int: ProgressSample] = [:]
    private let fileManager = FileManager.default

    private struct ProgressSample {
        var date: Date
        var bytes: Int64
        var smoothedSpeed: Double
    }

    private init() {
        loadIndex()
    }

    func isDownloaded(_ track: Track) -> Bool {
        guard !track.isLocal,
              let url = downloadedFiles[track.id]
        else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func isDownloading(_ track: Track) -> Bool {
        downloadingIDs.contains(track.id)
    }

    func progress(for track: Track) -> DownloadProgress? {
        activeProgress[track.id]
    }

    func cancel(_ track: Track) {
        guard let task = downloadTasks[track.id] else { return }
        task.cancel()
        ToastCenter.shared.show(String(localized: "已取消下载"))
    }

    func fileURL(for track: Track) -> URL? {
        guard !track.isLocal,
              let url = downloadedFiles[track.id],
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    var downloadedFileSize: Int64 {
        downloadedTracks.reduce(into: Int64(0)) { result, item in
            result += item.fileSize
        }
    }

    func download(_ track: Track) {
        guard !track.isLocal,
              !isDownloaded(track),
              !downloadingIDs.contains(track.id)
        else { return }

        downloadingIDs.insert(track.id)
        let token = UUID()
        downloadTokens[track.id] = token
        progressSamples[track.id] = ProgressSample(date: Date(), bytes: 0, smoothedSpeed: 0)
        activeProgress[track.id] = DownloadProgress(
            track: track,
            downloadedBytes: 0,
            totalBytes: nil,
            speedBytesPerSecond: 0
        )
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(track, token: token)
        }
        downloadTasks[track.id] = task
    }

    func remove(_ track: Track) {
        guard !track.isLocal else { return }
        if let url = downloadedFiles.removeValue(forKey: track.id) {
            try? fileManager.removeItem(at: url)
        }
        downloadedTrackMetadata.removeValue(forKey: track.id)
        downloadedIDs.remove(track.id)
        rebuildDownloadedTracks()
        saveIndex()
    }

    func removeAll() {
        downloadedFiles.removeAll()
        downloadedTrackMetadata.removeAll()
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        downloadTokens.removeAll()
        progressSamples.removeAll()
        activeProgress.removeAll()
        downloadingIDs.removeAll()
        downloadedIDs.removeAll()
        downloadedTracks.removeAll()
        try? fileManager.removeItem(at: Self.downloadDirectory)
        saveIndex()
    }

    private func performDownload(_ track: Track, token: UUID) async {
        defer {
            if downloadTokens[track.id] == token {
                downloadingIDs.remove(track.id)
                activeProgress.removeValue(forKey: track.id)
                progressSamples.removeValue(forKey: track.id)
                downloadTokens.removeValue(forKey: track.id)
                downloadTasks.removeValue(forKey: track.id)
            }
        }

        do {
            try Task.checkCancellation()
            let source = try await resolveSource(for: track)
            let result = try await downloadSource(from: source.url, for: track, token: token)
            try Task.checkCancellation()
            guard let http = result.response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                throw DownloadError.invalidResponse
            }

            guard downloadTokens[track.id] == token else { return }

            let directory = Self.downloadDirectory
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(
                "\(track.id).\(source.fileExtension)", isDirectory: false
            )
            if let previous = downloadedFiles[track.id], previous != destination {
                try? fileManager.removeItem(at: previous)
            }
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: result.url, to: destination)

            downloadedFiles[track.id] = destination
            downloadedTrackMetadata[track.id] = track
            downloadedIDs.insert(track.id)
            rebuildDownloadedTracks()
            saveIndex()
            ToastCenter.shared.show(String(localized: "歌曲下载完成"))
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            ToastCenter.shared.show("\(String(localized: "歌曲下载失败"))：\(error.localizedDescription)")
        }
    }

    private func downloadSource(
        from url: URL,
        for track: Track,
        token: UUID
    ) async throws -> DownloadTaskResult {
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Kumone-\(track.id)-\(UUID().uuidString).download")
        let delegate = DownloadTaskDelegate(destinationURL: temporaryURL) { [weak self] written, expected in
            Task { @MainActor [weak self] in
                guard let self, self.downloadTokens[track.id] == token else { return }
                self.updateProgress(
                    for: track,
                    downloadedBytes: written,
                    totalBytes: expected > 0 ? expected : nil
                )
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withTaskCancellationHandler(operation: {
            try await delegate.start(session: session, url: url)
        }, onCancel: {
            delegate.cancel()
        })
    }

    private func resolveSource(for track: Track) async throws -> ResolvedSource {
        // Downloads start at the highest quality and fall back only when the
        // account or the song cannot provide that level.
        var data: SongURLData?
        for quality in AudioQuality.allCases.reversed() {
            data = try? await NeteaseAPI.songURL(ids: [track.id], level: quality.rawValue).first
            if data?.url != nil { break }
        }

        if let data, let urlString = data.url,
           let url = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://")) {
            return ResolvedSource(
                url: url,
                fileExtension: Self.fileExtension(for: data, url: url)
            )
        }

        if SettingsManager.shared.enableUnblock,
           let unblocked = await UnblockService.resolve(track) {
            return ResolvedSource(url: unblocked.url, fileExtension: "mp3")
        }
        throw DownloadError.sourceUnavailable
    }

    private func updateProgress(
        for track: Track,
        downloadedBytes: Int64,
        totalBytes: Int64?
    ) {
        guard downloadTokens[track.id] != nil else { return }
        let now = Date()
        guard var sample = progressSamples[track.id] else { return }
        let elapsed = now.timeIntervalSince(sample.date)
        let isComplete = totalBytes.map { downloadedBytes >= $0 } ?? false
        guard elapsed >= 0.1 || isComplete else { return }

        let delta = max(0, downloadedBytes - sample.bytes)
        let instantSpeed = elapsed > 0 ? Double(delta) / elapsed : 0
        if instantSpeed > 0 {
            sample.smoothedSpeed = sample.smoothedSpeed == 0
                ? instantSpeed
                : sample.smoothedSpeed * 0.7 + instantSpeed * 0.3
        }
        activeProgress[track.id] = DownloadProgress(
            track: track,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: sample.smoothedSpeed
        )
        sample.date = now
        sample.bytes = downloadedBytes
        progressSamples[track.id] = sample
    }

    private static func fileExtension(for data: SongURLData, url: URL) -> String {
        let candidate = data.type?.lowercased() ?? url.pathExtension.lowercased()
        let sanitized = candidate.filter { $0.isLetter || $0.isNumber }
        return sanitized.isEmpty ? "audio" : sanitized
    }

    private static var downloadDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kumone", isDirectory: true)
        return support.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static var indexURL: URL {
        downloadDirectory.appendingPathComponent("index.json", isDirectory: false)
    }

    private static var metadataURL: URL {
        downloadDirectory.appendingPathComponent("metadata.json", isDirectory: false)
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: Self.indexURL),
           let paths = try? JSONDecoder().decode([String: String].self, from: data) {
            for (idString, path) in paths {
                guard let id = Int(idString) else { continue }
                let url = URL(fileURLWithPath: path)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                downloadedFiles[id] = url
            }
        }

        if let data = try? Data(contentsOf: Self.metadataURL),
           let metadata = try? JSONDecoder().decode([String: Track].self, from: data) {
            for (idString, track) in metadata {
                guard let id = Int(idString), downloadedFiles[id] != nil else { continue }
                downloadedTrackMetadata[id] = track
            }
        }

        rebuildDownloadedTracks()
    }

    private func saveIndex() {
        let paths = downloadedFiles.reduce(into: [String: String]()) { result, item in
            result[String(item.key)] = item.value.path
        }
        let metadata = downloadedTrackMetadata.reduce(into: [String: Track]()) { result, item in
            result[String(item.key)] = item.value
        }
        guard let indexData = try? JSONEncoder().encode(paths),
              let metadataData = try? JSONEncoder().encode(metadata)
        else { return }
        let url = Self.indexURL
        let metadataURL = Self.metadataURL
        let directory = Self.downloadDirectory
        Task.detached {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? indexData.write(to: url, options: .atomic)
            try? metadataData.write(to: metadataURL, options: .atomic)
        }
    }

    private func rebuildDownloadedTracks() {
        downloadedTracks = downloadedTrackMetadata.compactMap { id, track in
            guard let url = downloadedFiles[id], fileManager.fileExists(atPath: url.path) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return DownloadedTrack(
                track: track,
                url: url,
                fileSize: Int64(values?.fileSize ?? 0)
            )
        }
        .sorted {
            $0.track.name.localizedCaseInsensitiveCompare($1.track.name) == .orderedAscending
        }
        downloadedIDs = Set(downloadedFiles.keys)
    }
}
