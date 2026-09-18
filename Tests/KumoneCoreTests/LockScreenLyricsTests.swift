import Foundation
import Testing
@testable import KumoneCore

@Suite("Lock-screen lyrics")
struct LockScreenLyricsTests {
    @Test("Uses the active lyric while retaining song information")
    func activeLineMetadata() throws {
        let track = try localTrack()
        let lyrics = ParsedLyrics(lines: [
            LyricLine(id: 0, time: 0, text: "First line"),
            LyricLine(id: 1, time: 10, text: "Second line"),
        ])

        let metadata = LockScreenLyricsFormatter.metadata(
            for: track, lyrics: lyrics, elapsed: 10
        )

        #expect(metadata?.lineID == 1)
        #expect(metadata?.lyric == "Second line")
        #expect(metadata?.songAndArtist == "Local Song — Local Artist")
    }

    @Test("Does not replace the song title with a blank lyric")
    func blankLineMetadata() throws {
        let track = try localTrack()
        let lyrics = ParsedLyrics(lines: [
            LyricLine(id: 0, time: 0, text: "   "),
        ])

        #expect(LockScreenLyricsFormatter.metadata(
            for: track, lyrics: lyrics, elapsed: 1
        ) == nil)
    }

    private func localTrack() throws -> Track {
        let url = try #require(URL(string: "ipod-library://item/item.m4a?id=7"))
        return Track(
            localPersistentID: 7,
            name: "Local Song",
            artist: "Local Artist",
            album: "Local Album",
            duration: 120,
            assetURL: url
        )
    }
}
