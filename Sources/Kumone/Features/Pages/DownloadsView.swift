import SwiftUI

/// A local library for songs downloaded by Kumone.
struct DownloadsView: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @EnvironmentObject private var player: PlayerService
    @State private var showClearConfirmation = false

    private var tracks: [Track] {
        let activeTracks = downloads.activeProgress.values
            .map(\.track)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let activeIDs = Set(activeTracks.map(\.id))
        return activeTracks + downloads.downloadedTracks
            .map(\.track)
            .filter { !activeIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if tracks.isEmpty {
                    EmptyStateView(
                        icon: "arrow.down.circle",
                        title: "暂无下载歌曲",
                        subtitle: "在歌曲列表中点击下载按钮即可离线播放"
                    )
                    .frame(minHeight: 300)
                } else {
                    header

                    TrackListView(
                        tracks: tracks,
                        style: .full,
                        downloadAction: .removeOnly,
                        source: .none,
                        context: nil
                    )
                    .padding(.horizontal, Theme.Layout.contentInset - 10)
                }

                PlayerClearanceSpacer()
            }
        }
        .navigationTitle("下载管理")
        .toolbar {
            if !downloads.downloadedTracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label("清空下载", systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "清空下载歌曲？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空下载", role: .destructive) {
                downloads.removeAll()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(downloads.activeProgress.isEmpty ? "已下载歌曲" : "下载中")
                    .font(.system(size: 15, weight: .semibold))
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                player.play(tracks: tracks, source: .none, context: nil)
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accentGradient, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Theme.Layout.contentInset)
        .padding(.top, 12)
    }

    private var summary: String {
        let count = downloads.downloadedTracks.count
        let size = ByteCountFormatter.string(
            fromByteCount: downloads.downloadedFileSize,
            countStyle: .file
        )
        let completed = String(format: String(localized: "已下载 %lld 首 · %@"), count, size)
        guard !downloads.activeProgress.isEmpty else { return completed }
        let active = String(format: String(localized: "正在下载 %lld 首"), downloads.activeProgress.count)
        return "\(completed) · \(active)"
    }
}
