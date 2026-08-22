import Foundation
import Testing
@testable import KumoneCore

@Suite("Local music tracks")
struct LocalTrackTests {
    @Test("Uses a separate stable ID namespace")
    func stableLocalID() {
        #expect(Track.localTrackID(for: 123_456) == -123_456)
        #expect(Track.localTrackID(for: 0) == -1)
        #expect(Track.localTrackID(for: 123_456) == Track.localTrackID(for: 123_456))
    }

    @Test("Persists local playback metadata")
    func localTrackCodingRoundTrip() throws {
        let url = URL(string: "ipod-library://item/item.m4a?id=42")!
        let track = Track(
            localPersistentID: 42,
            name: "Local Song",
            artist: "Local Artist",
            album: "Local Album",
            duration: 185.25,
            assetURL: url,
            trackNo: 3,
            disc: "1"
        )

        let data = try JSONEncoder().encode(track)
        let restored = try JSONDecoder().decode(Track.self, from: data)

        #expect(restored.isLocal)
        #expect(restored.localPersistentID == 42)
        #expect(restored.localAssetURL == url)
        #expect(restored.name == "Local Song")
        #expect(restored.artistNames == "Local Artist")
        #expect(restored.album.name == "Local Album")
        #expect(restored.durationMS == 185_250)
    }
}
