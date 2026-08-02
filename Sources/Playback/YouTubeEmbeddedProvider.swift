import Foundation

@MainActor
final class YouTubeEmbeddedProvider: PlaybackProvider {
    let source: ContentSource = .youtube
    let supportsNativeBackground = false
    weak var bridge: YouTubePlayerBridge?
    private(set) var loadedVideoID: String?
    func load(_ track: Track) async throws { guard let id = track.videoID else { throw ROZZAError.unsupportedPlayback }; loadedVideoID = id; bridge?.load(videoID: id) }
    func play() async throws { bridge?.play() }
    func pause() { bridge?.pause() }
    func seek(to seconds: TimeInterval) async { bridge?.seek(to: seconds) }
    func stop() { bridge?.stop() }
}

@MainActor protocol YouTubePlayerBridge: AnyObject {
    func load(videoID: String)
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func stop()
}

