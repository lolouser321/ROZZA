import AVFoundation
import Foundation

@MainActor
class NativeAudioProvider: PlaybackProvider {
    let source: ContentSource
    let supportsNativeBackground = true
    let player = AVPlayer()
    init(source: ContentSource) { self.source = source }

    func load(_ track: Track) async throws {
        guard let url = track.playbackURL else { throw ROZZAError.unsupportedPlayback }
        try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
    func play() async throws {
        try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
        player.play()
        print("[ROZZA AVPlayer] play() called; rate:", player.rate, "volume:", player.volume)
    }
    func pause() { player.pause() }
    func seek(to seconds: TimeInterval) async { await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
    func stop() { player.pause(); player.replaceCurrentItem(with: nil) }
}

@MainActor final class LocalAudioProvider: NativeAudioProvider { init() { super.init(source: .local) } }
@MainActor final class LicensedCatalogProvider: NativeAudioProvider { init() { super.init(source: .licensed) } }
