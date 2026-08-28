#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// Maps core music models to CarPlay list items with async artwork loading and play status.
@MainActor
enum CarPlayItemMapper {
    /// Maps a Track to a CPListItem with live playing indicator and artwork.
    static func mapTrack(
        _ track: Track,
        isPlaying: Bool = false,
        action: @escaping () -> Void
    ) -> CPListItem {
        var detail = track.artistNames
        if !track.album.name.isEmpty && track.album.name != track.name {
            detail += " · " + track.album.name
        }

        let item = CPListItem(
            text: track.name,
            detailText: detail,
            image: CarPlayImageHelper.trackPlaceholder,
            accessoryImage: nil,
            accessoryType: .none
        )

        item.isPlaying = isPlaying
        item.playingIndicatorLocation = .leading

        item.handler = { _, completion in
            action()
            completion()
        }

        if let picUrl = track.album.picUrl?.resizedImageURL(128) {
            Task {
                if let rawImage = await ImageCache.shared.image(for: picUrl) {
                    let formatted = CarPlayImageHelper.formatArtwork(rawImage)
                    item.setImage(formatted)
                }
            }
        }

        return item
    }

    /// Maps playlist information to a CPListItem.
    static func mapPlaylist(
        id: Int,
        title: String,
        coverURL: String?,
        trackCount: Int,
        creatorName: String? = nil,
        action: @escaping () -> Void
    ) -> CPListItem {
        var detail = trackCount > 0 ? "\(trackCount) 首" : ""
        if let creatorName, !creatorName.isEmpty {
            detail += (detail.isEmpty ? "" : " · ") + creatorName
        }

        let item = CPListItem(
            text: title,
            detailText: detail.isEmpty ? nil : detail,
            image: CarPlayImageHelper.playlistPlaceholder,
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )

        item.handler = { _, completion in
            action()
            completion()
        }

        if let cover = coverURL?.resizedImageURL(128) {
            Task {
                if let rawImage = await ImageCache.shared.image(for: cover) {
                    let formatted = CarPlayImageHelper.formatArtwork(rawImage)
                    item.setImage(formatted)
                }
            }
        }

        return item
    }

    /// Maps a PlaylistSummary to a CPListItem navigating to the playlist detail.
    static func mapPlaylist(
        _ playlist: PlaylistSummary,
        action: @escaping () -> Void
    ) -> CPListItem {
        mapPlaylist(
            id: playlist.id,
            title: playlist.name,
            coverURL: playlist.coverURL,
            trackCount: playlist.trackCount,
            creatorName: playlist.creator?.nickname,
            action: action
        )
    }

    /// Maps album information to a CPListItem.
    static func mapAlbum(
        id: Int,
        title: String,
        artistName: String,
        coverURL: String?,
        trackCount: Int = 0,
        action: @escaping () -> Void
    ) -> CPListItem {
        var detail = artistName
        if trackCount > 0 {
            detail += (detail.isEmpty ? "" : " · ") + "\(trackCount) 首"
        }

        let item = CPListItem(
            text: title,
            detailText: detail.isEmpty ? nil : detail,
            image: CarPlayImageHelper.albumPlaceholder,
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )

        item.handler = { _, completion in
            action()
            completion()
        }

        if let picUrl = coverURL?.resizedImageURL(128) {
            Task {
                if let rawImage = await ImageCache.shared.image(for: picUrl) {
                    let formatted = CarPlayImageHelper.formatArtwork(rawImage)
                    item.setImage(formatted)
                }
            }
        }

        return item
    }

    /// Maps an AlbumSummary to a CPListItem navigating to the album detail.
    static func mapAlbum(
        _ album: AlbumSummary,
        action: @escaping () -> Void
    ) -> CPListItem {
        mapAlbum(
            id: album.id,
            title: album.name,
            artistName: album.artistName,
            coverURL: album.picUrl,
            trackCount: album.size,
            action: action
        )
    }

    /// Maps artist information to a CPListItem.
    static func mapArtist(
        id: Int,
        title: String,
        avatarURL: String?,
        musicCount: Int = 0,
        action: @escaping () -> Void
    ) -> CPListItem {
        let detail = musicCount > 0 ? "\(musicCount) 首单曲" : nil

        let item = CPListItem(
            text: title,
            detailText: detail,
            image: CarPlayImageHelper.artistPlaceholder,
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )

        item.handler = { _, completion in
            action()
            completion()
        }

        if let picUrl = avatarURL?.resizedImageURL(128) {
            Task {
                if let rawImage = await ImageCache.shared.image(for: picUrl) {
                    let formatted = CarPlayImageHelper.formatAvatar(rawImage)
                    item.setImage(formatted)
                }
            }
        }

        return item
    }

    /// Maps an ArtistSummary to a CPListItem navigating to the artist detail.
    static func mapArtist(
        _ artist: ArtistSummary,
        action: @escaping () -> Void
    ) -> CPListItem {
        mapArtist(
            id: artist.id,
            title: artist.name,
            avatarURL: artist.picUrl,
            musicCount: artist.musicSize,
            action: action
        )
    }

    /// Creates an action/shortcut list item with custom title, subtitle, and badge icon.
    static func mapActionItem(
        title: String,
        subtitle: String? = nil,
        systemName: String,
        tint: UIColor = .systemRed,
        showsDisclosure: Bool = false,
        action: @escaping () -> Void
    ) -> CPListItem {
        let icon = CarPlayImageHelper.symbolBadge(systemName: systemName, tint: tint)
        let item = CPListItem(
            text: title,
            detailText: subtitle,
            image: icon,
            accessoryImage: nil,
            accessoryType: showsDisclosure ? .disclosureIndicator : .none
        )

        item.handler = { _, completion in
            action()
            completion()
        }

        return item
    }
}
#endif
