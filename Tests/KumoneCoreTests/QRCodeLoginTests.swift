import Foundation
import Testing
@testable import KumoneCore

@Suite("QR code login")
struct QRCodeLoginTests {
    @Test("Parses the cookie string returned by a successful QR login")
    func parsesSuccessfulLoginCookies() throws {
        let raw = "MUSIC_U=music-token; Path=/; HttpOnly;; __csrf=csrf-token; Path=/"

        let cookies = NeteaseClient.parseCookieString(raw)

        #expect(cookies["MUSIC_U"] == "music-token")
        #expect(cookies["__csrf"] == "csrf-token")
        #expect(cookies["Path"] == nil)
    }

    @Test("Decodes the cookie field from the 803 response")
    func decodesSuccessfulLoginResponse() throws {
        let data = Data(#"{"code":803,"message":"授权登录成功","cookie":"MUSIC_U=token;; __csrf=csrf"}"#.utf8)

        let response = try JSONDecoder().decode(NeteaseAPI.QRCheckResponse.self, from: data)

        #expect(response.code == 803)
        #expect(response.cookie == "MUSIC_U=token;; __csrf=csrf")
    }

    @Test("Allows polling responses without cookies")
    func decodesWaitingResponse() throws {
        let data = Data(#"{"code":801,"message":"等待扫码"}"#.utf8)

        let response = try JSONDecoder().decode(NeteaseAPI.QRCheckResponse.self, from: data)

        #expect(response.code == 801)
        #expect(response.cookie == nil)
    }
}
