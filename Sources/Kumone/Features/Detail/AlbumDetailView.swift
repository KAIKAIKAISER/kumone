import SwiftUI

struct AlbumDetailView: View {
    let albumID: Int

    @State private var album: AlbumDetail?
    @State private var tracks: [Track] = []
    @State private var otherAlbums: [AlbumSummary] = []
    @State private var isSubscribed = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullDescription = false

    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
                if let album {
                    if isCompact {
                        compactHeader(album)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    } else {
                        regularHeader(album)
                            .padding(.horizontal, Theme.Layout.contentInset)
                            .padding(.top, 16)
                    }

                    TrackListView(
                        tracks: tracks,
                        source: .album(albumID),
                        context: .album(id: albumID, name: album.name)
                    )
                    .padding(.horizontal, isCompact ? 6 : Theme.Layout.contentInset - 10)

                    if !otherAlbums.isEmpty {
                        SectionHeader(title: "该歌手的其他专辑")
                            .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)
                            .padding(.top, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                                ForEach(otherAlbums) { item in
                                    NavigationLink(value: Destination.album(item.id)) {
                                        CoverCardBody(
                                            coverURL: item.picUrl?.resizedImageURL(384),
                                            title: item.name,
                                            subtitle: Formatters.date(fromMS: item.publishTime)
                                        )
                                    }
                                    .buttonStyle(.interactiveCard)
                                }
                                Spacer().frame(width: (isCompact ? 16 : Theme.Layout.contentInset) - 16)
                            }
                        }
                    }
                } else if isLoading {
                    loadingHeader
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                    .frame(minHeight: 400)
                }

                PlayerClearanceSpacer()
            }
        }
        #if os(macOS)
        .navigationTitle(album?.name ?? String(localized: "专辑"))
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: albumID) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await NeteaseAPI.album(id: albumID)
            album = response.album
            tracks = response.songs
            isLoading = false
            if let dynamic = try? await NeteaseAPI.albumDynamic(id: albumID) {
                isSubscribed = dynamic.isSub ?? false
            }
            if let artistID = response.album.artist?.id,
               let albums = try? await NeteaseAPI.artistAlbums(id: artistID, limit: 12) {
                otherAlbums = albums.hotAlbums.filter { $0.id != albumID }
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Compact Header

    private func compactHeader(_ album: AlbumDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CachedAsyncImage(url: album.picUrl?.resizedImageURL(384))
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(album.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(3)

                    if let artist = album.artist {
                        NavigationLink(value: Destination.artist(artist.id)) {
                            Text(artist.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(tracks.count) 首 · \(Formatters.date(fromMS: album.publishTime))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let description = album.description, !description.isEmpty {
                descriptionCard(description, album: album)
            }

            // Compact Action Bar
            HStack(spacing: 10) {
                Button {
                    player.play(tracks: tracks, source: .album(albumID),
                                context: .album(id: albumID, name: album.name))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("播放全部 (\(tracks.count))")
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
                        toggleSubscribe()
                    } label: {
                        Image(systemName: isSubscribed ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSubscribed ? Theme.accent : .primary)
                            .frame(width: 38, height: 38)
                            .background(.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: - Regular Header

    private func regularHeader(_ album: AlbumDetail) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            CachedAsyncImage(url: album.picUrl?.resizedImageURL(512))
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.subType?.isEmpty == false ? album.subType! : String(localized: "专辑"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(album.name)
                    .font(.title.weight(.bold))
                    .lineLimit(2)

                if let artist = album.artist {
                    NavigationLink(value: Destination.artist(artist.id)) {
                        Text(artist.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(tracks.count) 首 · \(totalDuration) · \(Formatters.date(fromMS: album.publishTime))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)

                if let description = album.description, !description.isEmpty {
                    descriptionCard(description, album: album)
                }

                Spacer(minLength: 4)

                HStack(spacing: 10) {
                    Button {
                        player.play(tracks: tracks, source: .album(albumID),
                                context: .album(id: albumID, name: album.name))
                    } label: {
                        Label("播放", systemImage: "play.fill")
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
                            toggleSubscribe()
                        } label: {
                            Label(isSubscribed ? String(localized: "已收藏") : String(localized: "收藏"),
                                  systemImage: isSubscribed ? "checkmark" : "plus")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 210)
    }

    private func descriptionCard(_ description: String, album: AlbumDetail) -> some View {
        Button {
            showFullDescription = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: album.picUrl?.resizedImageURL(768), animated: false)
                    .scaleEffect(1.08)
                    .blur(radius: 12)
                    .overlay(.black.opacity(0.42))

                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                        Text("专辑简介")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.8)
                    }
                    .font(.system(size: isCompact ? 11 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                    Text(description)
                        .font(.system(size: isCompact ? 11.5 : 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(isCompact ? 3 : 2)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(isCompact ? 12 : 11)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 112 : 84,
                   maxHeight: isCompact ? 112 : 84)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sheet(isPresented: $showFullDescription) {
            NavigationStack {
                AlbumDescriptionView(album: album, description: description)
            }
        }
        #else
        .popover(isPresented: $showFullDescription, arrowEdge: .bottom) {
            AlbumDescriptionView(album: album, description: description)
                .frame(width: 430, height: 460)
        }
        #endif
    }

    private var totalDuration: String {
        let totalMS = tracks.reduce(into: 0) { $0 += $1.durationMS }
        return Formatters.longDuration(TimeInterval(totalMS) / 1000)
    }

    private func toggleSubscribe() {
        Task {
            do {
                try await NeteaseAPI.subscribeAlbum(id: albumID, subscribe: !isSubscribed)
                isSubscribed.toggle()
                ToastCenter.shared.show(isSubscribed ? String(localized: "已收藏专辑") : String(localized: "已取消收藏"))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private var loadingHeader: some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(.primary.opacity(0.05))
                .frame(width: isCompact ? 120 : 200, height: isCompact ? 120 : 200)
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)).frame(width: 60, height: 14)
                RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.1)).frame(width: 180, height: 24)
                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.06)).frame(width: 120, height: 14)
            }
            Spacer()
        }
        .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)
        .padding(.top, 16)
    }
}

private struct AlbumDescriptionView: View {
    let album: AlbumDetail
    let description: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CachedAsyncImage(url: album.picUrl?.resizedImageURL(1024), animated: false)
                .scaleEffect(1.2)
                .blur(radius: 28)

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.84),
                    .black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("专辑简介", systemImage: "text.quote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))

                        Text(album.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)

                        if let artist = album.artist {
                            Text(artist.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent.opacity(0.95))
                        }
                    }

                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 1)

                    Text(description)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)

                    if let company = album.company, !company.isEmpty {
                        Text(company)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
        }
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("完成") { dismiss() }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .navigationTitle("专辑简介")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .navigationTitle("专辑简介")
        #endif
    }
}
