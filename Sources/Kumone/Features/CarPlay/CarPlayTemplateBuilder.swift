#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// Factory creating rich, responsive, and beautiful CarPlay templates for Kumone.
@MainActor
final class CarPlayTemplateBuilder {
    private weak var manager: CarPlayManager?

    init(manager: CarPlayManager) {
        self.manager = manager
    }

    // MARK: - Navigation Bar Buttons

    /// Creates a universal "Now Playing" bar button that jumps straight to the playback screen.
    func makeNowPlayingBarButton() -> CPBarButton {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "waveform", withConfiguration: config) ?? UIImage()
        return CPBarButton(image: icon) { [weak self] _ in
            self?.manager?.showNowPlaying()
        }
    }

    /// Creates a "Play All" bar button for playlists and albums.
    func makePlayAllBarButton(action: @escaping () -> Void) -> CPBarButton {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config) ?? UIImage()
        return CPBarButton(image: icon) { _ in
            action()
        }
    }

    /// Creates a "Shuffle" bar button for playlists and albums.
    func makeShuffleBarButton(action: @escaping () -> Void) -> CPBarButton {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "shuffle", withConfiguration: config) ?? UIImage()
        return CPBarButton(image: icon) { _ in
            action()
        }
    }

    // MARK: - 1. Recommended Tab (推荐)

    func makeRecommendTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "推荐"), sections: [])
        template.tabImage = UIImage(systemName: "sparkles")
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载推荐...")]

        loadRecommendContent(for: template)
        return template
    }

    func loadRecommendContent(for template: CPListTemplate) {
        let account = AccountStore.shared

        // Initial quick play section
        var quickItems: [CPListItem] = []

        // Daily Songs shortcut
        quickItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "每日推荐"),
            subtitle: String(localized: "今日专属 30 首推荐单曲"),
            systemName: "calendar",
            tint: .systemOrange,
            showsDisclosure: true
        ) { [weak self] in
            guard let self, let dest = self.makeDailySongsTemplate() else { return }
            self.manager?.push(dest)
        })

        // Personal FM 1-tap Play
        quickItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "私人漫游"),
            subtitle: String(localized: "根据你的口味即刻漫游好音乐"),
            systemName: "wave.3.right",
            tint: .systemPink
        ) { [weak self] in
            PlayerService.shared.startFM()
            self?.manager?.showNowPlaying()
        })

        // Liked Songs Heartbeat Mode
        quickItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "心动模式"),
            subtitle: String(localized: "智能推荐你可能喜欢的歌曲"),
            systemName: "heart.text.square.fill",
            tint: .systemRed
        ) { [weak self] in
            guard let liked = account.likedSongsPlaylist else {
                ToastCenter.shared.show(String(localized: "请先收藏歌曲"))
                return
            }
            Task {
                if let detail = try? await NeteaseAPI.playlistDetail(id: liked.id),
                   let firstTrack = detail.playlist.tracks.first,
                   let tracks = try? await NeteaseAPI.intelligenceList(songID: firstTrack.id, playlistID: liked.id),
                   !tracks.isEmpty {
                    PlayerService.shared.play(tracks: tracks, source: .playlist(liked.id), startAt: tracks.first, context: .heartbeat)
                    self?.manager?.showNowPlaying()
                }
            }
        })

        let sections: [CPListSection] = [
            CPListSection(items: quickItems, header: String(localized: "快捷播放"), sectionIndexTitle: nil as String?)
        ]
        template.updateSections(sections)

        // Asynchronously load Radar Playlists, Recommended Playlists, and New Releases
        Task { [weak self, weak template] in
            guard let self, let template else { return }
            let loggedIn = account.hasAuthCookie

            // 1. Radar playlists
            var radarItems: [CPListItem] = []
            for radarID in HomeViewModel.radarPlaylistIDs {
                if let brief = try? await NeteaseAPI.playlistBrief(id: radarID) {
                    let title = brief.name ?? String(localized: "私人雷达")
                    let item = CarPlayItemMapper.mapPlaylist(
                        id: brief.id,
                        title: title,
                        coverURL: brief.coverImgUrl,
                        trackCount: 0
                    ) { [weak self] in
                        guard let self, let dest = self.makePlaylistDetailTemplate(
                            playlistID: brief.id,
                            title: title,
                            coverURL: brief.coverImgUrl
                        ) else { return }
                        self.manager?.push(dest)
                    }
                    radarItems.append(item)
                }
            }

            // 2. Recommended playlists
            var recPlaylists: [PlaylistSummary] = []
            if loggedIn {
                recPlaylists = (try? await NeteaseAPI.recommendResource()) ?? []
            }
            if recPlaylists.isEmpty {
                recPlaylists = (try? await NeteaseAPI.personalizedPlaylists(limit: 12)) ?? []
            }

            let recItems: [CPListItem] = recPlaylists.prefix(12).map { playlist in
                CarPlayItemMapper.mapPlaylist(playlist) { [weak self] in
                    guard let self, let dest = self.makePlaylistDetailTemplate(
                        playlistID: playlist.id,
                        title: playlist.name,
                        coverURL: playlist.coverURL
                    ) else { return }
                    self.manager?.push(dest)
                }
            }

            // 3. New Albums
            let newAlbums = (try? await NeteaseAPI.newAlbums(limit: 10)) ?? []
            let albumItems: [CPListItem] = newAlbums.map { album in
                CarPlayItemMapper.mapAlbum(album) { [weak self] in
                    guard let self, let dest = self.makeAlbumDetailTemplate(
                        albumID: album.id,
                        title: album.name,
                        artistName: album.artistName,
                        coverURL: album.picUrl
                    ) else { return }
                    self.manager?.push(dest)
                }
            }

            var updatedSections = sections
            if !radarItems.isEmpty {
                updatedSections.append(CPListSection(items: radarItems, header: String(localized: "雷达歌单"), sectionIndexTitle: nil as String?))
            }
            if !recItems.isEmpty {
                updatedSections.append(CPListSection(items: recItems, header: String(localized: "推荐歌单"), sectionIndexTitle: nil as String?))
            }
            if !albumItems.isEmpty {
                updatedSections.append(CPListSection(items: albumItems, header: String(localized: "新碟上架"), sectionIndexTitle: nil as String?))
            }

            template.updateSections(updatedSections)
        }
    }

    // MARK: - 2. Radio & FM Tab (漫游)

    func makeRadioTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "漫游"), sections: [])
        template.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]

        loadRadioContent(for: template)
        return template
    }

    func loadRadioContent(for template: CPListTemplate) {
        let account = AccountStore.shared

        // FM Mode Items
        let fmItem = CarPlayItemMapper.mapActionItem(
            title: String(localized: "私人漫游"),
            subtitle: String(localized: "个性化无限音乐流"),
            systemName: "wave.3.right.circle.fill",
            tint: .systemPink
        ) { [weak self] in
            PlayerService.shared.startFM()
            self?.manager?.showNowPlaying()
        }

        let heartbeatItem = CarPlayItemMapper.mapActionItem(
            title: String(localized: "我喜欢的音乐 · 心动模式"),
            subtitle: String(localized: "基于红心收藏的智能漫游"),
            systemName: "heart.circle.fill",
            tint: .systemRed
        ) { [weak self] in
            guard let liked = account.likedSongsPlaylist else { return }
            Task {
                if let detail = try? await NeteaseAPI.playlistDetail(id: liked.id),
                   let firstTrack = detail.playlist.tracks.first,
                   let tracks = try? await NeteaseAPI.intelligenceList(songID: firstTrack.id, playlistID: liked.id),
                   !tracks.isEmpty {
                    PlayerService.shared.play(tracks: tracks, source: .playlist(liked.id), startAt: tracks.first, context: .heartbeat)
                    self?.manager?.showNowPlaying()
                }
            }
        }

        var sections = [
            CPListSection(items: [fmItem, heartbeatItem], header: String(localized: "漫游模式"), sectionIndexTitle: nil as String?)
        ]
        template.updateSections(sections)

        // Load Official Top Charts
        Task { [weak self, weak template] in
            guard let self, let template else { return }
            if let toplists = try? await NeteaseAPI.toplists() {
                let filtered = toplists.filter { [19_723_756, 3_779_629, 2_884_035, 3_778_678, 60198].contains($0.id) }
                let chartItems: [CPListItem] = filtered.map { chart in
                    CarPlayItemMapper.mapPlaylist(
                        id: chart.id,
                        title: chart.name,
                        coverURL: chart.coverImgUrl,
                        trackCount: 0
                    ) { [weak self] in
                        guard let self, let dest = self.makePlaylistDetailTemplate(
                            playlistID: chart.id,
                            title: chart.name,
                            coverURL: chart.coverImgUrl
                        ) else { return }
                        self.manager?.push(dest)
                    }
                }

                if !chartItems.isEmpty {
                    sections.append(CPListSection(items: chartItems, header: String(localized: "官方排行榜"), sectionIndexTitle: nil as String?))
                    template.updateSections(sections)
                }
            }
        }
    }

    // MARK: - 3. Library Tab (我的)

    func makeLibraryTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "我的"), sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]

        loadLibraryContent(for: template)
        return template
    }

    func loadLibraryContent(for template: CPListTemplate) {
        let account = AccountStore.shared
        var sections: [CPListSection] = []

        if !account.hasAuthCookie {
            let loginItem = CarPlayItemMapper.mapActionItem(
                title: String(localized: "未登录网易云音乐"),
                subtitle: String(localized: "请在 iPhone 上打开 Kumone 登录后使用完整曲库"),
                systemName: "person.crop.circle.badge.exclamationmark",
                tint: .systemYellow
            ) {}
            sections.append(CPListSection(items: [loginItem], header: nil as String?, sectionIndexTitle: nil as String?))
            template.updateSections(sections)
            return
        }

        // Section 1: My Music Quick Links
        var myMusicItems: [CPListItem] = []

        if let liked = account.likedSongsPlaylist {
            let countText = liked.trackCount > 0 ? "\(liked.trackCount) 首单曲" : nil
            myMusicItems.append(CarPlayItemMapper.mapActionItem(
                title: String(localized: "我喜欢的音乐"),
                subtitle: countText,
                systemName: "heart.fill",
                tint: .systemRed,
                showsDisclosure: true
            ) { [weak self] in
                guard let self, let dest = self.makePlaylistDetailTemplate(
                    playlistID: liked.id,
                    title: liked.name,
                    coverURL: liked.coverURL
                ) else { return }
                self.manager?.push(dest)
            })
        }

        myMusicItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "最近播放"),
            subtitle: String(localized: "近期播放历史"),
            systemName: "clock.fill",
            tint: .systemBlue,
            showsDisclosure: true
        ) { [weak self] in
            guard let self, let dest = self.makeRecentsTemplate() else { return }
            self.manager?.push(dest)
        })

        myMusicItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "音乐云盘"),
            subtitle: String(localized: "云端收藏与上传的歌曲"),
            systemName: "icloud.fill",
            tint: .systemCyan,
            showsDisclosure: true
        ) { [weak self] in
            guard let self, let dest = self.makeCloudSongsTemplate() else { return }
            self.manager?.push(dest)
        })

        myMusicItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "收藏的专辑"),
            subtitle: "\(account.likedAlbums.count) 张专辑",
            systemName: "opticaldisc",
            tint: .systemOrange,
            showsDisclosure: true
        ) { [weak self] in
            guard let self, let dest = self.makeLikedAlbumsTemplate() else { return }
            self.manager?.push(dest)
        })

        myMusicItems.append(CarPlayItemMapper.mapActionItem(
            title: String(localized: "收藏的歌手"),
            subtitle: "\(account.likedArtists.count) 位歌手",
            systemName: "music.mic",
            tint: .systemIndigo,
            showsDisclosure: true
        ) { [weak self] in
            guard let self, let dest = self.makeLikedArtistsTemplate() else { return }
            self.manager?.push(dest)
        })

        sections.append(CPListSection(items: myMusicItems, header: String(localized: "我的音乐"), sectionIndexTitle: nil as String?))

        // Section 2: Created Playlists
        let created = account.createdPlaylists
        if !created.isEmpty {
            let createdItems = created.map { playlist in
                CarPlayItemMapper.mapPlaylist(playlist) { [weak self] in
                    guard let self, let dest = self.makePlaylistDetailTemplate(
                        playlistID: playlist.id,
                        title: playlist.name,
                        coverURL: playlist.coverURL
                    ) else { return }
                    self.manager?.push(dest)
                }
            }
            sections.append(CPListSection(items: createdItems, header: String(localized: "创建的歌单"), sectionIndexTitle: nil as String?))
        }

        // Section 3: Subscribed Playlists
        let subscribed = account.subscribedPlaylists
        if !subscribed.isEmpty {
            let subscribedItems = subscribed.map { playlist in
                CarPlayItemMapper.mapPlaylist(playlist) { [weak self] in
                    guard let self, let dest = self.makePlaylistDetailTemplate(
                        playlistID: playlist.id,
                        title: playlist.name,
                        coverURL: playlist.coverURL
                    ) else { return }
                    self.manager?.push(dest)
                }
            }
            sections.append(CPListSection(items: subscribedItems, header: String(localized: "收藏的歌单"), sectionIndexTitle: nil as String?))
        }

        template.updateSections(sections)
    }

    // MARK: - 4. Playlist Detail Template

    func makePlaylistDetailTemplate(playlistID: Int, title: String, coverURL: String?) -> CPListTemplate? {
        let template = CPListTemplate(title: title, sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载歌单...")]

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let response = try await NeteaseAPI.playlistDetail(id: playlistID)
                let tracks = response.playlist.tracks

                guard !tracks.isEmpty else {
                    template.emptyViewTitleVariants = [String(localized: "歌单内暂无歌曲")]
                    template.updateSections([])
                    return
                }

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .playlist(playlistID),
                            startAt: track,
                            context: .playlist(id: playlistID, name: title)
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                // Play all and Shuffle buttons in navigation bar
                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .playlist(playlistID),
                        startAt: tracks.first,
                        context: .playlist(id: playlistID, name: title)
                    )
                    self?.manager?.showNowPlaying()
                }

                let shuffleBtn = self.makeShuffleBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .playlist(playlistID),
                        startAt: tracks.randomElement() ?? tracks.first,
                        context: .playlist(id: playlistID, name: title)
                    )
                    if !PlayerService.shared.shuffleEnabled {
                        PlayerService.shared.toggleShuffle()
                    }
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, shuffleBtn, self.makeNowPlayingBarButton()]
                template.updateSections([
                    CPListSection(items: trackItems, header: "\(tracks.count) 首单曲", sectionIndexTitle: nil as String?)
                ])
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载失败，请重试")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 5. Daily Songs Template

    func makeDailySongsTemplate() -> CPListTemplate? {
        let template = CPListTemplate(title: String(localized: "每日推荐"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在生成今日推荐...")]

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let tracks = try await NeteaseAPI.dailyRecommendSongs()
                guard !tracks.isEmpty else {
                    template.emptyViewTitleVariants = [String(localized: "暂无推荐歌曲")]
                    template.updateSections([])
                    return
                }

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .daily,
                            startAt: track,
                            context: .daily
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .daily,
                        startAt: tracks.first,
                        context: .daily
                    )
                    self?.manager?.showNowPlaying()
                }

                let shuffleBtn = self.makeShuffleBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .daily,
                        startAt: tracks.randomElement() ?? tracks.first,
                        context: .daily
                    )
                    if !PlayerService.shared.shuffleEnabled {
                        PlayerService.shared.toggleShuffle()
                    }
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, shuffleBtn, self.makeNowPlayingBarButton()]
                template.updateSections([
                    CPListSection(items: trackItems, header: String(localized: "今日推荐 30 首"), sectionIndexTitle: nil as String?)
                ])
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载推荐失败")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 6. Recents Template

    func makeRecentsTemplate() -> CPListTemplate? {
        let template = CPListTemplate(title: String(localized: "最近播放"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载播放历史...")]

        guard let uid = AccountStore.shared.profile?.userId else {
            template.emptyViewTitleVariants = [String(localized: "未登录")]
            return template
        }

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let records = try await NeteaseAPI.playRecords(uid: uid, week: false)
                let tracks = records.map(\.song)

                guard !tracks.isEmpty else {
                    template.emptyViewTitleVariants = [String(localized: "暂无播放记录")]
                    template.updateSections([])
                    return
                }

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .none,
                            startAt: track,
                            context: .recents
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .none,
                        startAt: tracks.first,
                        context: .recents
                    )
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, self.makeNowPlayingBarButton()]
                template.updateSections([
                    CPListSection(items: trackItems, header: "\(tracks.count) 条记录", sectionIndexTitle: nil as String?)
                ])
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载失败")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 7. Cloud Songs Template

    func makeCloudSongsTemplate() -> CPListTemplate? {
        let template = CPListTemplate(title: String(localized: "音乐云盘"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载云盘歌曲...")]

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let response = try await NeteaseAPI.cloudSongs(limit: 500)
                let tracks = (response.data ?? []).compactMap(\.simpleSong)

                guard !tracks.isEmpty else {
                    template.emptyViewTitleVariants = [String(localized: "云盘暂无歌曲")]
                    template.updateSections([])
                    return
                }

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .cloud,
                            startAt: track,
                            context: .cloud
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .cloud,
                        startAt: tracks.first,
                        context: .cloud
                    )
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, self.makeNowPlayingBarButton()]
                template.updateSections([
                    CPListSection(items: trackItems, header: "\(tracks.count) 首云盘歌曲", sectionIndexTitle: nil as String?)
                ])
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载失败")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 8. Album Detail Template

    func makeAlbumDetailTemplate(albumID: Int, title: String, artistName: String?, coverURL: String?) -> CPListTemplate? {
        let template = CPListTemplate(title: title, sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载专辑...")]

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let response = try await NeteaseAPI.album(id: albumID)
                let tracks = response.songs

                guard !tracks.isEmpty else {
                    template.emptyViewTitleVariants = [String(localized: "专辑内暂无歌曲")]
                    template.updateSections([])
                    return
                }

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .album(albumID),
                            startAt: track,
                            context: .album(id: albumID, name: title)
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .album(albumID),
                        startAt: tracks.first,
                        context: .album(id: albumID, name: title)
                    )
                    self?.manager?.showNowPlaying()
                }

                let shuffleBtn = self.makeShuffleBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .album(albumID),
                        startAt: tracks.randomElement() ?? tracks.first,
                        context: .album(id: albumID, name: title)
                    )
                    if !PlayerService.shared.shuffleEnabled {
                        PlayerService.shared.toggleShuffle()
                    }
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, shuffleBtn, self.makeNowPlayingBarButton()]
                let headerText = (artistName != nil && !artistName!.isEmpty) ? "\(tracks.count) 首歌曲 · \(artistName!)" : "\(tracks.count) 首歌曲"
                template.updateSections([
                    CPListSection(items: trackItems, header: headerText, sectionIndexTitle: nil as String?)
                ])
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载专辑失败")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 9. Artist Detail Template

    func makeArtistDetailTemplate(artistID: Int, title: String, coverURL: String?) -> CPListTemplate? {
        let template = CPListTemplate(title: title, sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        template.emptyViewTitleVariants = [String(localized: "正在加载歌手信息...")]

        Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let response = try await NeteaseAPI.artist(id: artistID)
                let tracks = response.hotSongs

                let currentID = PlayerService.shared.currentTrack?.id
                let isPlaying = PlayerService.shared.isPlaying

                let trackItems = tracks.map { track in
                    let isCurrent = (track.id == currentID && isPlaying)
                    return CarPlayItemMapper.mapTrack(track, isPlaying: isCurrent) { [weak self] in
                        PlayerService.shared.play(
                            tracks: tracks,
                            source: .artist(artistID),
                            startAt: track,
                            context: .artist(id: artistID, name: title)
                        )
                        self?.manager?.showNowPlaying()
                    }
                }

                var sections = [
                    CPListSection(items: trackItems, header: String(localized: "热门单曲 TOP 50"), sectionIndexTitle: nil as String?)
                ]

                // Also load albums
                if let albumsResp = try? await NeteaseAPI.artistAlbums(id: artistID, limit: 20) {
                    let albumItems = albumsResp.hotAlbums.map { album in
                        CarPlayItemMapper.mapAlbum(album) { [weak self] in
                            guard let self, let dest = self.makeAlbumDetailTemplate(
                                albumID: album.id,
                                title: album.name,
                                artistName: album.artistName,
                                coverURL: album.picUrl
                            ) else { return }
                            self.manager?.push(dest)
                        }
                    }
                    if !albumItems.isEmpty {
                        sections.append(CPListSection(items: albumItems, header: String(localized: "歌手专辑"), sectionIndexTitle: nil as String?))
                    }
                }

                let playAllBtn = self.makePlayAllBarButton { [weak self] in
                    PlayerService.shared.play(
                        tracks: tracks,
                        source: .artist(artistID),
                        startAt: tracks.first,
                        context: .artist(id: artistID, name: title)
                    )
                    self?.manager?.showNowPlaying()
                }

                template.trailingNavigationBarButtons = [playAllBtn, self.makeNowPlayingBarButton()]
                template.updateSections(sections)
            } catch {
                template.emptyViewTitleVariants = [String(localized: "加载歌手失败")]
                template.updateSections([])
            }
        }

        return template
    }

    // MARK: - 10. Queue Template (播放队列)

    func makeQueueTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "播放队列"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]

        let player = PlayerService.shared
        var sections: [CPListSection] = []

        if let current = player.currentTrack {
            let currentItem = CarPlayItemMapper.mapTrack(current, isPlaying: player.isPlaying) { [weak self] in
                self?.manager?.showNowPlaying()
            }
            sections.append(CPListSection(items: [currentItem], header: String(localized: "正在播放"), sectionIndexTitle: nil as String?))
        }

        let upcoming = player.upcomingTracks
        if !upcoming.isEmpty {
            let upcomingItems = upcoming.prefix(80).map { track in
                CarPlayItemMapper.mapTrack(track, isPlaying: false) { [weak self] in
                    PlayerService.shared.jumpTo(track)
                    self?.manager?.showNowPlaying()
                }
            }
            sections.append(CPListSection(items: Array(upcomingItems), header: String(localized: "即将播放 (\(upcoming.count) 首)"), sectionIndexTitle: nil as String?))
        }

        if sections.isEmpty {
            template.emptyViewTitleVariants = [String(localized: "当前无播放歌曲")]
        } else {
            template.updateSections(sections)
        }

        return template
    }

    // MARK: - 11. Saved Albums & Artists

    func makeLikedAlbumsTemplate() -> CPListTemplate? {
        let template = CPListTemplate(title: String(localized: "收藏的专辑"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]

        let albums = AccountStore.shared.likedAlbums
        guard !albums.isEmpty else {
            template.emptyViewTitleVariants = [String(localized: "暂无收藏专辑")]
            return template
        }

        let items = albums.map { album in
            CarPlayItemMapper.mapAlbum(album) { [weak self] in
                guard let self, let dest = self.makeAlbumDetailTemplate(
                    albumID: album.id,
                    title: album.name,
                    artistName: album.artistName,
                    coverURL: album.picUrl
                ) else { return }
                self.manager?.push(dest)
            }
        }

        template.updateSections([
            CPListSection(items: items, header: "\(items.count) 张专辑", sectionIndexTitle: nil as String?)
        ])
        return template
    }

    func makeLikedArtistsTemplate() -> CPListTemplate? {
        let template = CPListTemplate(title: String(localized: "收藏的歌手"), sections: [])
        template.trailingNavigationBarButtons = [makeNowPlayingBarButton()]

        let artists = AccountStore.shared.likedArtists
        guard !artists.isEmpty else {
            template.emptyViewTitleVariants = [String(localized: "暂无收藏歌手")]
            return template
        }

        let items = artists.map { artist in
            CarPlayItemMapper.mapArtist(artist) { [weak self] in
                guard let self, let dest = self.makeArtistDetailTemplate(
                    artistID: artist.id,
                    title: artist.name,
                    coverURL: artist.picUrl
                ) else { return }
                self.manager?.push(dest)
            }
        }

        template.updateSections([
            CPListSection(items: items, header: "\(items.count) 位歌手", sectionIndexTitle: nil as String?)
        ])
        return template
    }
}
#endif
