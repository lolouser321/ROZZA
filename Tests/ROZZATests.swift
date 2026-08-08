import XCTest
@testable import ROZZA

final class ROZZATests: XCTestCase {
    func testYouTubeNeverClaimsBackgroundPlayback() {
        XCTAssertFalse(PlaybackCapabilities.youtube.canBackgroundPlay)
        XCTAssertFalse(PlaybackCapabilities.youtube.supportsLockScreen)
        XCTAssertFalse(PlaybackCapabilities.youtube.canDownload)
    }
    func testLocalPlaybackCapabilities() {
        XCTAssertTrue(PlaybackCapabilities.local.canBackgroundPlay)
        XCTAssertTrue(PlaybackCapabilities.local.canOfflinePlay)
        XCTAssertTrue(PlaybackCapabilities.local.supportsControlCenter)
    }
}

