import AppKit
import Testing
@testable import KumoneCore

@Suite("Now Playing Artwork Store Tests")
@MainActor
struct NowPlayingArtworkStoreTests {
    @Test func latestArtworkRequestWins() async {
        let firstArtwork = artwork(color: .systemRed)
        let secondArtwork = artwork(color: .systemBlue)
        let store = NowPlayingArtworkStore(player: nil) { url in
            if url.absoluteString.contains("first-artwork") {
                try? await Task.sleep(nanoseconds: 20_000_000)
                return firstArtwork
            }
            return secondArtwork
        }

        store.update(
            trackID: 1,
            artworkURL: "https://example.com/first-artwork.jpg"
        )
        store.update(
            trackID: 2,
            artworkURL: "https://example.com/second-artwork.jpg"
        )
        try? await Task.sleep(nanoseconds: 40_000_000)

        #expect(store.trackID == 2)
        #expect(store.artwork === secondArtwork)
    }

    @Test func missingArtworkImmediatelyUsesFallback() {
        let store = NowPlayingArtworkStore(player: nil) { _ in artwork(color: .systemRed) }

        store.update(trackID: 1, artworkURL: nil)

        #expect(store.trackID == 1)
        #expect(store.artwork == nil)
        #expect(store.colors == .fallback)
    }

    @Test func failedArtworkLoadUsesFallback() async {
        let store = NowPlayingArtworkStore(player: nil) { _ in nil }

        store.update(
            trackID: 1,
            artworkURL: "https://example.com/missing-artwork.jpg"
        )
        await Task.yield()
        await Task.yield()

        #expect(store.trackID == 1)
        #expect(store.artwork == nil)
        #expect(store.colors == .fallback)
    }

    private func artwork(color: NSColor) -> PlatformImage {
        let image = PlatformImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
    }
}
