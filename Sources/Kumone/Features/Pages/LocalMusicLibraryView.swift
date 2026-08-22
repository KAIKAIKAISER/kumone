#if os(iOS)
import MediaPlayer
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LocalMusicLibrary {
    static let shared = LocalMusicLibrary()

    private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()
    private(set) var tracks: [Track] = []
    private(set) var unavailableTrackCount = 0
    private(set) var isLoading = false

    private init() {}

    func requestAccess() async {
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        if status == .authorized {
            reload()
        }
    }

    func reload() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        guard authorizationStatus == .authorized else {
            tracks = []
            unavailableTrackCount = 0
            return
        }

        isLoading = true
        let items = MPMediaQuery.songs().items ?? []
        unavailableTrackCount = items.reduce(into: 0) { count, item in
            if item.assetURL == nil { count += 1 }
        }
        tracks = items.compactMap(Self.track(from:)).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        isLoading = false
    }

    private static func track(from item: MPMediaItem) -> Track? {
        guard let assetURL = item.assetURL else { return nil }
        let unknownArtist = String(localized: "未知歌手")
        let unknownAlbum = String(localized: "未知专辑")
        return Track(
            localPersistentID: item.persistentID,
            name: item.title?.nilIfBlank ?? String(localized: "未知歌曲"),
            artist: item.artist?.nilIfBlank ?? unknownArtist,
            album: item.albumTitle?.nilIfBlank ?? unknownAlbum,
            duration: item.playbackDuration,
            assetURL: assetURL,
            trackNo: item.albumTrackNumber,
            disc: item.discNumber > 0 ? String(item.discNumber) : nil
        )
    }
}

struct LocalMusicLibraryView: View {
    @State private var library = LocalMusicLibrary.shared
    @Environment(PlayerService.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""

    private var visibleTracks: [Track] {
        guard !searchText.isEmpty else { return library.tracks }
        return library.tracks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.artistNames.localizedCaseInsensitiveContains(searchText)
                || $0.album.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            switch library.authorizationStatus {
            case .authorized:
                authorizedContent
            case .notDetermined:
                permissionView
            case .denied, .restricted:
                deniedView
            @unknown default:
                deniedView
            }
        }
        .navigationTitle("本地音乐")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            library.reload()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                library.reload()
            }
        }
    }

    private var authorizedContent: some View {
        List {
            if !library.tracks.isEmpty {
                Section {
                    Button {
                        player.play(tracks: visibleTracks, source: .localLibrary)
                    } label: {
                        Label("播放全部（\(visibleTracks.count) 首）", systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    .disabled(visibleTracks.isEmpty)
                }
            }

            Section {
                if library.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if visibleTracks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "没有可播放的本地音乐" : "未找到本地音乐",
                        systemImage: searchText.isEmpty ? "music.note.slash" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "请先用“音乐”App 将歌曲下载到这台设备。"
                            : "请尝试其他歌曲名、歌手或专辑名。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleTracks) { track in
                        Button {
                            player.play(tracks: visibleTracks, source: .localLibrary, startAt: track)
                        } label: {
                            LocalMusicRow(track: track, isCurrent: player.currentTrack?.id == track.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("歌曲（\(visibleTracks.count)）")
            } footer: {
                if library.unavailableTrackCount > 0 {
                    Text("另有 \(library.unavailableTrackCount) 首受保护或未下载的歌曲，iOS 未提供可播放地址。")
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索歌曲、歌手或专辑")
        .refreshable {
            library.reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新本地音乐")
            }
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("读取本地音乐", systemImage: "music.note.house")
        } description: {
            Text("允许 Kumone 读取设备音乐资料库，即可浏览和播放已下载的歌曲。")
        } actions: {
            Button("允许访问") {
                Task { await library.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("无法访问音乐资料库", systemImage: "lock.fill")
        } description: {
            Text("请在系统设置中允许 Kumone 访问“媒体与 Apple Music”。")
        } actions: {
            Button("打开系统设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct LocalMusicRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
                .overlay {
                    Image(systemName: isCurrent ? "waveform" : "music.note")
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                }
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                Text("\(track.artistNames) · \(track.album.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Formatters.duration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
#endif
