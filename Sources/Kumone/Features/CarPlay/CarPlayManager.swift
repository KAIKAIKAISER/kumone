#if canImport(CarPlay) && os(iOS)
import CarPlay
import Combine
import UIKit

/// Central coordinator for the CarPlay session, managing navigation, templates, and state synchronization.
@MainActor
final class CarPlayManager: NSObject {
    static let shared = CarPlayManager()

    private(set) var interfaceController: CPInterfaceController?
    private(set) var window: CPWindow?

    private(set) var tabBarTemplate: CPTabBarTemplate?
    private(set) var recommendTemplate: CPListTemplate?
    private(set) var radioTemplate: CPListTemplate?
    private(set) var libraryTemplate: CPListTemplate?

    private(set) lazy var builder = CarPlayTemplateBuilder(manager: self)
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    // MARK: - Connection Lifecycle

    func attach(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window

        setupTemplates()
        setupObservers()
        CarPlayNowPlayingController.shared.attach(manager: self)

        // Bootstrap data if launched headlessly via CarPlay
        Task {
            if !AccountStore.shared.isBootstrapped {
                await AccountStore.shared.bootstrap()
            }
            refreshAllTabs()
        }
    }

    func detach() {
        cancellables.removeAll()
        interfaceController = nil
        window = nil
        tabBarTemplate = nil
        recommendTemplate = nil
        radioTemplate = nil
        libraryTemplate = nil
    }

    // MARK: - Template Setup

    private func setupTemplates() {
        let rec = builder.makeRecommendTemplate()
        let rad = builder.makeRadioTemplate()
        let lib = builder.makeLibraryTemplate()
        let nowPlaying = CPNowPlayingTemplate.shared

        self.recommendTemplate = rec
        self.radioTemplate = rad
        self.libraryTemplate = lib

        let tabBar = CPTabBarTemplate(templates: [rec, rad, lib, nowPlaying])
        self.tabBarTemplate = tabBar

        interfaceController?.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    // MARK: - State Observers

    private func setupObservers() {
        cancellables.removeAll()

        let player = PlayerService.shared
        let account = AccountStore.shared

        // Track and playback changes
        Publishers.CombineLatest(player.$currentTrack, player.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { _ in
                CarPlayNowPlayingController.shared.updateButtons()
            }
            .store(in: &cancellables)

        // FM, shuffle, repeat changes
        Publishers.CombineLatest3(player.$isFMMode, player.$shuffleEnabled, player.$repeatMode)
            .receive(on: RunLoop.main)
            .sink { _ in
                CarPlayNowPlayingController.shared.updateButtons()
            }
            .store(in: &cancellables)

        // User library changes
        Publishers.CombineLatest(account.$profile, account.$userPlaylists)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let lib = self.libraryTemplate else { return }
                self.builder.loadLibraryContent(for: lib)
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    func push(_ template: CPTemplate, animated: Bool = true) {
        interfaceController?.pushTemplate(template, animated: animated, completion: nil)
    }

    func pop(animated: Bool = true) {
        interfaceController?.popTemplate(animated: animated, completion: nil)
    }

    func popToRoot(animated: Bool = true) {
        interfaceController?.popToRootTemplate(animated: animated, completion: nil)
    }

    /// Transitions to the Now Playing screen.
    func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        guard let controller = interfaceController else { return }

        // If not already showing now playing, push it or select its tab
        if controller.topTemplate !== nowPlaying {
            controller.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }

    /// Pushes the live playback queue.
    func showQueue() {
        let queueTemplate = builder.makeQueueTemplate()
        push(queueTemplate, animated: true)
    }

    /// Navigates to the current song's album or artist.
    func showCurrentAlbumOrArtist() {
        guard let track = PlayerService.shared.currentTrack else { return }
        if track.album.id > 0 {
            if let dest = builder.makeAlbumDetailTemplate(
                albumID: track.album.id,
                title: track.album.name,
                artistName: track.artistNames,
                coverURL: track.album.picUrl
            ) {
                push(dest, animated: true)
            }
        } else if let firstArtist = track.artists.first, firstArtist.id > 0 {
            if let dest = builder.makeArtistDetailTemplate(
                artistID: firstArtist.id,
                title: firstArtist.name,
                coverURL: nil
            ) {
                push(dest, animated: true)
            }
        }
    }

    func refreshAllTabs() {
        if let rec = recommendTemplate {
            builder.loadRecommendContent(for: rec)
        }
        if let rad = radioTemplate {
            builder.loadRadioContent(for: rad)
        }
        if let lib = libraryTemplate {
            builder.loadLibraryContent(for: lib)
        }
    }
}
#endif
