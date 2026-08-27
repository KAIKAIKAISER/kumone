import Combine
import Foundation

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

    struct DownloadedTrack: Identifiable {
        let track: Track
        let url: URL
        let fileSize: Int64

        var id: Int { track.id }
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
    private let fileManager = FileManager.default

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
        Task { [weak self] in
            await self?.performDownload(track)
        }
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
        downloadedIDs.removeAll()
        downloadedTracks.removeAll()
        try? fileManager.removeItem(at: Self.downloadDirectory)
        saveIndex()
    }

    private func performDownload(_ track: Track) async {
        defer { downloadingIDs.remove(track.id) }

        do {
            let source = try await resolveSource(for: track)
            let (temporaryURL, response) = try await URLSession.shared.download(from: source.url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                throw DownloadError.invalidResponse
            }

            let directory = Self.downloadDirectory
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(
                "\(track.id).\(source.fileExtension)", isDirectory: false
            )
            if let previous = downloadedFiles[track.id], previous != destination {
                try? fileManager.removeItem(at: previous)
            }
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporaryURL, to: destination)

            downloadedFiles[track.id] = destination
            downloadedTrackMetadata[track.id] = track
            downloadedIDs.insert(track.id)
            rebuildDownloadedTracks()
            saveIndex()
            ToastCenter.shared.show(String(localized: "歌曲下载完成"))
        } catch {
            ToastCenter.shared.show("\(String(localized: "歌曲下载失败"))：\(error.localizedDescription)")
        }
    }

    private func resolveSource(for track: Track) async throws -> ResolvedSource {
        let quality = SettingsManager.shared.audioQuality.rawValue
        var data = try? await NeteaseAPI.songURL(ids: [track.id], level: quality).first
        if data?.url == nil, quality != AudioQuality.standard.rawValue {
            data = try? await NeteaseAPI.songURL(ids: [track.id], level: AudioQuality.standard.rawValue).first
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
