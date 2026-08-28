#if canImport(CarPlay) && os(iOS)
import Testing
import CarPlay
import UIKit
@testable import KumoneIOSFeature
@testable import KumoneCore

@Suite("CarPlay Integration Tests")
struct CarPlayTests {

    @Test("CarPlay image helper renders square artwork and circle avatars")
    @MainActor
    func testImageHelperRendering() {
        let testImage = UIImage(systemName: "music.note") ?? UIImage()

        let artwork = CarPlayImageHelper.formatArtwork(testImage, size: CGSize(width: 48, height: 48), cornerRadius: 8)
        #expect(artwork.size.width == 48)
        #expect(artwork.size.height == 48)

        let avatar = CarPlayImageHelper.formatAvatar(testImage, diameter: 48)
        #expect(avatar.size.width == 48)
        #expect(avatar.size.height == 48)

        let badge = CarPlayImageHelper.symbolBadge(systemName: "heart.fill", tint: .systemRed)
        #expect(badge.size.width == 48)
        #expect(badge.size.height == 48)

        #expect(CarPlayImageHelper.trackPlaceholder.size.width == 48)
        #expect(CarPlayImageHelper.playlistPlaceholder.size.width == 48)
        #expect(CarPlayImageHelper.albumPlaceholder.size.width == 48)
        #expect(CarPlayImageHelper.artistPlaceholder.size.width == 48)
    }

    @Test("CarPlayItemMapper maps Track to CPListItem accurately")
    @MainActor
    func testTrackMapping() {
        let json = """
        {
            "id": 12345,
            "name": "夜曲",
            "artists": [{"id": 1, "name": "周杰伦"}],
            "album": {"id": 10, "name": "十一月的萧邦", "picUrl": "https://example.com/pic.jpg"},
            "duration": 226000
        }
        """.data(using: .utf8)!

        let track = try! JSONDecoder().decode(Track.self, from: json)
        var tapped = false

        let item = CarPlayItemMapper.mapTrack(track, isPlaying: true) {
            tapped = true
        }

        #expect(item.text == "夜曲")
        #expect(item.detailText == "周杰伦 · 十一月的萧邦")
        #expect(item.isPlaying == true)
        #expect(item.playingIndicatorLocation == .leading)

        item.handler?(item, {})
        #expect(tapped == true)
    }

    @Test("CarPlayItemMapper maps Playlist to CPListItem")
    @MainActor
    func testPlaylistMapping() {
        var tapped = false
        let item = CarPlayItemMapper.mapPlaylist(
            id: 999,
            title: "华语经典",
            coverURL: "https://example.com/cover.jpg",
            trackCount: 50,
            creatorName: "云音乐官方"
        ) {
            tapped = true
        }

        #expect(item.text == "华语经典")
        #expect(item.detailText == "50 首 · 云音乐官方")
        #expect(item.accessoryType == .disclosureIndicator)

        item.handler?(item, {})
        #expect(tapped == true)
    }

    @Test("CarPlayItemMapper maps Album and Artist")
    @MainActor
    func testAlbumAndArtistMapping() {
        let albumItem = CarPlayItemMapper.mapAlbum(
            id: 200,
            title: "范特西",
            artistName: "周杰伦",
            coverURL: nil,
            trackCount: 10
        ) {}

        #expect(albumItem.text == "范特西")
        #expect(albumItem.detailText == "周杰伦 · 10 首")
        #expect(albumItem.accessoryType == .disclosureIndicator)

        let artistItem = CarPlayItemMapper.mapArtist(
            id: 300,
            title: "周杰伦",
            avatarURL: nil,
            musicCount: 300
        ) {}

        #expect(artistItem.text == "周杰伦")
        #expect(artistItem.detailText == "300 首单曲")
        #expect(artistItem.accessoryType == .disclosureIndicator)
    }

    @Test("CarPlayItemMapper maps Action item")
    @MainActor
    func testActionItemMapping() {
        var tapped = false
        let actionItem = CarPlayItemMapper.mapActionItem(
            title: "每日推荐",
            subtitle: "30 首单曲",
            systemName: "calendar",
            tint: .systemOrange,
            showsDisclosure: true
        ) {
            tapped = true
        }

        #expect(actionItem.text == "每日推荐")
        #expect(actionItem.detailText == "30 首单曲")
        #expect(actionItem.accessoryType == .disclosureIndicator)

        actionItem.handler?(actionItem, {})
        #expect(tapped == true)
    }

    @Test("CarPlayNowPlayingController updates buttons correctly")
    @MainActor
    func testNowPlayingControllerButtons() {
        let manager = CarPlayManager.shared
        CarPlayNowPlayingController.shared.attach(manager: manager)
        CarPlayNowPlayingController.shared.updateButtons()

        let template = CPNowPlayingTemplate.shared
        #expect(template.isUpNextButtonEnabled == true)
        #expect(template.upNextTitle == "播放队列")
    }

    @Test("CarPlayTemplateBuilder constructs all main templates")
    @MainActor
    func testTemplateBuilder() {
        let manager = CarPlayManager.shared
        let builder = CarPlayTemplateBuilder(manager: manager)

        let recommendTemplate = builder.makeRecommendTemplate()
        #expect(recommendTemplate.title == "推荐")
        #expect(recommendTemplate.trailingNavigationBarButtons.count >= 1)

        let radioTemplate = builder.makeRadioTemplate()
        #expect(radioTemplate.title == "漫游")

        let libraryTemplate = builder.makeLibraryTemplate()
        #expect(libraryTemplate.title == "我的")

        let queueTemplate = builder.makeQueueTemplate()
        #expect(queueTemplate.title == "播放队列")

        let nowPlayingBarBtn = builder.makeNowPlayingBarButton()
        #expect(nowPlayingBarBtn.image != nil)

        let playAllBtn = builder.makePlayAllBarButton {}
        #expect(playAllBtn.image != nil)

        let shuffleBtn = builder.makeShuffleBarButton {}
        #expect(shuffleBtn.image != nil)
    }
}
#endif
