import Testing
@testable import KumoneCore

@Suite("Release version comparison")
struct ReleaseCheckerTests {
    @Test("Ignores the iOS suffix when comparing versions")
    func comparesCoreVersion() {
        #expect(!ReleaseChecker.isNewer("0.3.8-ios.1", than: "0.3.8"))
        #expect(ReleaseChecker.isNewer("0.3.9-ios.1", than: "0.3.8"))
        #expect(!ReleaseChecker.isNewer("0.3.8-ios.2", than: "0.3.8-ios.1"))
    }
}
