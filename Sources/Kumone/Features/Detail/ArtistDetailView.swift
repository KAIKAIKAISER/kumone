import SwiftUI

struct ArtistDetailView: View {
    let artistID: Int

    @State private var artist: ArtistSummary?
    @State private var songs: [Track] = []
    @State private var createdPlaylists: [PlaylistSummary] = []
    @State private var albums: [AlbumSummary] = []
    @State private var epsAndSingles: [AlbumSummary] = []
    @State private var similar: [ArtistSummary] = []
    @State private var isFollowed = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let player = PlayerService.shared
    @EnvironmentObject private var account: AccountStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool {
        #if os(iOS)
        return LayoutSizeClass.isCompact(horizontal: horizontalSizeClass, vertical: verticalSizeClass,
                                         fallback: UIDevice.current.userInterfaceIdiom == .phone)
        #else
        return false
        #endif
    }

    var body: some View {
        TrackListScrollView(trackIDs: songs.map(\.id), style: .compact, spacing: isCompact ? 16 : 26) {
            VStack(alignment: .leading, spacing: isCompact ? 16 : 26) {
                if let artist {
                    if isCompact {
                        compactHeader(artist).padding(.horizontal, 16).padding(.top, 12)
                    } else {
                        regularHeader(artist).padding(.horizontal, Theme.Layout.contentInset).padding(.top, 16)
                    }
                    if !songs.isEmpty {
                        SectionHeader(title: "热门单曲")
                            .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)
                    }
                } else if isLoading {
                    loadingHeader
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                        .frame(minHeight: 400)
                }
            }
        } rows: { layout in
            TrackListView(tracks: songs, style: .compact, source: .artist(artistID),
                          context: artist.map { .artist(id: artistID, name: $0.name) }, layout: layout)
                .padding(.horizontal, isCompact ? 6 : Theme.Layout.contentInset - 10)
        } footer: {
            VStack(alignment: .leading, spacing: isCompact ? 16 : 26) {
                if !createdPlaylists.isEmpty {
                    SectionHeader(title: "创建的歌单")
                        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                            ForEach(createdPlaylists) { playlist in
                                NavigationLink(value: Destination.playlist(playlist.id)) {
                                    CoverCardBody(
                                        coverURL: playlist.coverURL?.resizedImageURL(384),
                                        title: playlist.name,
                                        subtitle: "\(playlist.trackCount) 首",
                                        playCount: playlist.playCount
                                    )
                                }
                                .buttonStyle(.interactiveCard)
                            }
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                        }
                    }
                }

                if !albums.isEmpty {
                    SectionHeader(title: "专辑")
                        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                            ForEach(albums) { album in
                                albumCard(album)
                            }
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                        }
                    }
                }

                if !epsAndSingles.isEmpty {
                    SectionHeader(title: "EP 与单曲")
                        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                            ForEach(epsAndSingles) { album in
                                albumCard(album)
                            }
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                        }
                    }
                }

                if !similar.isEmpty {
                    SectionHeader(title: "相似歌手")
                        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                            ForEach(similar) { sim in
                                NavigationLink(value: Destination.artist(sim.id)) {
                                    VStack(spacing: 8) {
                                        CachedAsyncImage(url: sim.picUrl?.resizedImageURL(256))
                                            .frame(width: isCompact ? 80 : 100, height: isCompact ? 80 : 100)
                                            .clipShape(Circle())
                                        Text(sim.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .frame(width: isCompact ? 80 : 100)
                                }
                                .buttonStyle(.interactiveCard)
                            }
                            Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                        }
                    }
                }
                PlayerClearanceSpacer()
            }
        }
        #if os(macOS)
        .navigationTitle(artist?.name ?? String(localized: "歌手"))
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: artistID) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await MusicAPI.artist(id: artistID)
            artist = response.artist
            songs = response.hotSongs
            isFollowed = response.artist.followed
            isLoading = false

            async let songsResult = try? MusicAPI.artistSongs(id: artistID, limit: 100)
            async let albumsResult = try? MusicAPI.artistAlbums(id: artistID, limit: 60)
            async let playlistsResult = try? MusicAPI.artistCreatedPlaylists(name: response.artist.name)

            if let loadedSongs = await songsResult?.songs, !loadedSongs.isEmpty {
                songs = loadedSongs
            }
            if let result = await albumsResult {
                albums = result.hotAlbums.filter { $0.size > 1 }
                epsAndSingles = result.hotAlbums.filter { $0.size <= 1 }
            }
            createdPlaylists = await playlistsResult ?? []
            if account.isLoggedIn {
                similar = (try? await MusicAPI.similarArtists(id: artistID)) ?? []
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Compact Header

    private func compactHeader(_ artist: ArtistSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                CachedAsyncImage(url: artist.picUrl?.resizedImageURL(384))
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(artist.name)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(2)
                    if !artist.alias.isEmpty {
                        Text(artist.alias.joined(separator: " / "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(artist.musicSize) 首歌曲 · \(artist.albumSize) 张专辑")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Compact Action Bar
            HStack(spacing: 10) {
                Button {
                    player.play(tracks: songs, source: .artist(artistID),
                                context: .artist(id: artistID, name: artist.name))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("播放歌曲")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.accentGradient, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.pressable)

                if account.isLoggedIn {
                    Button {
                        toggleFollow()
                    } label: {
                        Image(systemName: isFollowed ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isFollowed ? Theme.accent : .primary)
                            .frame(width: 38, height: 38)
                            .background(.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    blacklistMenu
                }
            }
        }
    }

    // MARK: - Regular Header

    private func regularHeader(_ artist: ArtistSummary) -> some View {
        HStack(alignment: .center, spacing: 28) {
            CachedAsyncImage(url: artist.picUrl?.resizedImageURL(512))
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("歌手")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(artist.name)
                    .font(.largeTitle.weight(.bold))
                if !artist.alias.isEmpty {
                    Text(artist.alias.joined(separator: " / "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Text("\(artist.musicSize) 首歌曲 · \(artist.albumSize) 张专辑")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 6)

                HStack(spacing: 10) {
                    Button {
                        player.play(tracks: songs, source: .artist(artistID),
                                    context: .artist(id: artistID, name: artist.name))
                    } label: {
                        Label("播放歌曲", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Theme.accentGradient, in: Capsule())
                            .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
                    }
                    .buttonStyle(.pressable)

                    if account.isLoggedIn {
                        Button {
                            toggleFollow()
                        } label: {
                            Label(isFollowed ? String(localized: "已关注") : String(localized: "关注"),
                                  systemImage: isFollowed ? "checkmark" : "plus")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        blacklistMenu
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var blacklistMenu: some View {
        if account.authenticatedAccountID != nil, artistID > 0 {
            Menu {
                MusicBlacklistButton(target: .artist(artistID), title: "减少推荐")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .fixedSize()
            .accessibilityLabel("更多操作")
        }
    }

    private func albumCard(_ album: AlbumSummary) -> some View {
        NavigationLink(value: Destination.album(album.id)) {
            CoverCardBody(
                coverURL: album.picUrl?.resizedImageURL(384),
                title: album.name,
                subtitle: album.publishYear
            )
        }
        .buttonStyle(.interactiveCard)
    }

    private func toggleFollow() {
        Task {
            do {
                try await MusicAPI.subscribeArtist(id: artistID, subscribe: !isFollowed)
                isFollowed.toggle()
                ToastCenter.shared.show(isFollowed ? String(localized: "已关注歌手") : String(localized: "已取消关注"))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private var loadingHeader: some View {
        HStack(alignment: .center, spacing: isCompact ? 14 : 24) {
            SkeletonView(cornerRadius: isCompact ? 50 : 90)
                .clipShape(Circle())
                .frame(width: isCompact ? 100 : 180, height: isCompact ? 100 : 180)

            VStack(alignment: .leading, spacing: 10) {
                SkeletonView(cornerRadius: 4).frame(maxWidth: isCompact ? 150 : 180, minHeight: 14, maxHeight: 14)
                SkeletonView(cornerRadius: 4).frame(width: 100, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)
        .padding(.top, isCompact ? 12 : 16)
    }
}
