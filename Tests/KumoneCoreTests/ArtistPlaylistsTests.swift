import Foundation
import Testing
@testable import KumoneCore

@Suite("Artist playlists")
struct ArtistPlaylistsTests {
    @Test("Keeps only playlists created by the artist account")
    func filtersByCreatorName() throws {
        let data = Data(#"""
        {
          "playlist": [
            {
              "id": 1,
              "name": "Official",
              "creator": {"userId": 10, "nickname": "Example Artist"}
            },
            {
              "id": 2,
              "name": "Fan Collection",
              "creator": {"userId": 20, "nickname": "Example Artist Fans"}
            },
            {
              "id": 3,
              "name": "Alternate Case",
              "creator": {"userId": 30, "nickname": "example artist"}
            }
          ]
        }
        """#.utf8)
        let response = try JSONDecoder().decode(NeteaseAPI.UserPlaylistsResponse.self, from: data)

        let result = NeteaseAPI.playlistsCreated(
            by: "Example Artist", from: response.playlist
        )

        #expect(result.map(\.id) == [1, 3])
    }

    @Test("Decodes the complete artist songs response")
    func decodesArtistSongs() throws {
        let data = Data(#"""
        {
          "songs": [
            {"id": 7, "name": "Song", "ar": [{"id": 8, "name": "Artist"}],
             "al": {"id": 9, "name": "Album"}, "dt": 123000}
          ],
          "more": true,
          "total": 250
        }
        """#.utf8)

        let response = try JSONDecoder().decode(NeteaseAPI.ArtistSongsResponse.self, from: data)

        #expect(response.songs.first?.name == "Song")
        #expect(response.more == true)
        #expect(response.total == 250)
    }
}
