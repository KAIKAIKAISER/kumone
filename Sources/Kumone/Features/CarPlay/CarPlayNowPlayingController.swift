#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// Manages CPNowPlayingTemplate configuration, buttons, up-next queue, and real-time state sync.
@MainActor
final class CarPlayNowPlayingController: NSObject {
    static let shared = CarPlayNowPlayingController()

    private weak var manager: CarPlayManager?

    private override init() {
        super.init()
    }

    func attach(manager: CarPlayManager) {
        self.manager = manager
        setupNowPlayingTemplate()
        updateButtons()
    }

    func setupNowPlayingTemplate() {
        let template = CPNowPlayingTemplate.shared
        template.add(self)
        template.isUpNextButtonEnabled = true
        template.upNextTitle = String(localized: "播放队列")
    }

    // MARK: - Buttons Update

    /// Recomputes and updates the action buttons on the Now Playing screen.
    func updateButtons() {
        let player = PlayerService.shared
        let account = AccountStore.shared
        var buttons: [CPNowPlayingButton] = []

        // 1. Like / Heart button
        if let track = player.currentTrack {
            let isLiked = account.isLiked(track.id)
            let heartSymbol = isLiked ? "heart.fill" : "heart"
            let heartTint: UIColor = isLiked ? .systemRed : .label

            let heartConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            let heartImage = UIImage(systemName: heartSymbol, withConfiguration: heartConfig)?
                .withTintColor(heartTint, renderingMode: .alwaysOriginal) ?? UIImage()

            let likeButton = CPNowPlayingImageButton(image: heartImage) { [weak self] _ in
                Task { @MainActor in
                    guard let current = PlayerService.shared.currentTrack else { return }
                    await AccountStore.shared.toggleLike(trackID: current.id)
                    self?.updateButtons()
                }
            }
            buttons.append(likeButton)
        }

        // 2. Mode specific controls: FM mode vs normal playlist
        if player.isFMMode {
            // FM Dislike / Trash button
            let trashConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            let trashImage = UIImage(systemName: "trash", withConfiguration: trashConfig)?
                .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) ?? UIImage()

            let trashButton = CPNowPlayingImageButton(image: trashImage) { _ in
                Task { @MainActor in
                    PlayerService.shared.fmTrash()
                }
            }
            buttons.append(trashButton)
        } else {
            // Shuffle button
            let shuffleConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: player.shuffleEnabled ? .bold : .regular)
            let shuffleTint: UIColor = player.shuffleEnabled ? .systemRed : .secondaryLabel
            let shuffleImage = UIImage(systemName: "shuffle", withConfiguration: shuffleConfig)?
                .withTintColor(shuffleTint, renderingMode: .alwaysOriginal) ?? UIImage()

            let shuffleButton = CPNowPlayingImageButton(image: shuffleImage) { [weak self] _ in
                Task { @MainActor in
                    PlayerService.shared.toggleShuffle()
                    self?.updateButtons()
                }
            }
            buttons.append(shuffleButton)

            // Repeat button
            let repeatSymbol: String
            let repeatTint: UIColor
            switch player.repeatMode {
            case .off:
                repeatSymbol = "repeat"
                repeatTint = .secondaryLabel
            case .all:
                repeatSymbol = "repeat"
                repeatTint = .systemRed
            case .one:
                repeatSymbol = "repeat.1"
                repeatTint = .systemRed
            }

            let repeatConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: player.repeatMode == .off ? .regular : .bold)
            let repeatImage = UIImage(systemName: repeatSymbol, withConfiguration: repeatConfig)?
                .withTintColor(repeatTint, renderingMode: .alwaysOriginal) ?? UIImage()

            let repeatButton = CPNowPlayingImageButton(image: repeatImage) { [weak self] _ in
                Task { @MainActor in
                    PlayerService.shared.cycleRepeatMode()
                    self?.updateButtons()
                }
            }
            buttons.append(repeatButton)
        }

        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }
}

extension CarPlayNowPlayingController: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in
            self.manager?.showQueue()
        }
    }

    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in
            self.manager?.showCurrentAlbumOrArtist()
        }
    }
}
#endif
