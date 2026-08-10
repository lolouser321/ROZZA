import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit
import WebKit

@MainActor
final class DJPlaybackController: NSObject, ObservableObject {
    @Published var isPresented = false
    @Published var youtubeReady = false
    @Published var isYouTubePlaying = false
    @Published var youtubeDeckVolume: Float = 1
    @Published var youtubeRequestedVolume: Float = 0.707
    @Published var youtubeReportedVolume: Float = 0
    @Published var isAVPlayerPlaying = false
    @Published var avDeckVolume: Float = 1
    @Published var avRequestedVolume: Float = 0.707
    @Published var avActualVolume: Float = 0
    @Published var crossfader: Float = 0.5
    @Published var outputRoute = "Unavailable"
    @Published var systemOutputVolume: Float = 0
    @Published var deckBName = "No audio loaded"
    @Published var lastError: String?

    let avPlayer = AVPlayer()
    private(set) var persistentWebView: WKWebView?
    private var latestYouTubeVolume: Float = 0.707
    private var wasYouTubeReady = false
    private var resumeAVAfterInterruption = false
    private var resumeYouTubeAfterInterruption = false
    // Authoritative foreground playback intent mirrored from rozza2.html.
    // This must not depend on the background iframe bridge because that bridge
    // is intentionally inert while the app is on screen.
    private var youtubeWantsPlayback = false
    private var resumeYouTubeAfterBackgroundTransition = false
    private var backgroundResumeGeneration = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var statusTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        configureAudioSession()
        observeAudioEvents()
        configureRemoteCommands()
        applyCrossfader()
        // Debug-deck polling used to cross the WKWebView bridge every 0.6 s
        // even when the DJ diagnostics UI was closed. Core playback state now
        // arrives through the main Now Playing handoff, so keep this expensive
        // status poll strictly for the debug deck.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                self.refreshDebugState()
            }
        }
    }

    deinit {
        statusTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(webView: WKWebView) {
        guard persistentWebView == nil else { return }
        persistentWebView = webView
        refreshDebugState()
    }

    /// Receives play-state callbacks from the bundled YouTube frame messenger.
    /// These events keep native audio state and Lock Screen playback state in
    /// sync even when WebKit's normal page callbacks are throttled.
    func handleYouTubeMessengerEvent(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }

        switch event {
        case "VideoPlay":
            _ = configureAudioSession()
            isYouTubePlaying = true
            updateNativePlaybackState(isPlaying: true, payload: payload)
        case "VideoPause":
            isYouTubePlaying = false
            updateNativePlaybackState(isPlaying: false, payload: payload)
        case "VideoIsPlaying":
            let isPlaying = (payload["paused"] as? Bool) == false
            if isPlaying { _ = configureAudioSession() }
            if isYouTubePlaying != isPlaying {
                isYouTubePlaying = isPlaying
                updateNativePlaybackState(isPlaying: isPlaying, payload: payload)
            }
        case "BackgroundIntent":
            // The iframe bridge mirrors the JS user's explicit Play/Pause
            // intent. Keep a native copy so Home/lock transition decisions do
            // not wait on evaluateJavaScript after WebKit starts suspending.
            youtubeWantsPlayback = payload["shouldPlay"] as? Bool ?? youtubeWantsPlayback
        case "BackgroundVideoPlaying":
            _ = configureAudioSession()
            youtubeWantsPlayback = true
            isYouTubePlaying = true
            updateNativePlaybackState(isPlaying: true, payload: payload)
        case "BackgroundVideoPause":
            // Do not immediately mark the Lock Screen as paused when the
            // bridge says playback intent is still PLAY; a bounded recovery
            // is already in flight. A user Pause changes shouldPlay=false.
            let shouldPlay = payload["shouldPlay"] as? Bool ?? false
            if !shouldPlay {
                youtubeWantsPlayback = false
                isYouTubePlaying = false
                updateNativePlaybackState(isPlaying: false, payload: payload)
            }
        case "BackgroundPulse":
            // A native transition kick asks the iframe bridge to inspect the
            // real <video>, not just the outer YouTube widget state.
            if (payload["paused"] as? Bool) == false {
                _ = configureAudioSession()
                youtubeWantsPlayback = true
                isYouTubePlaying = true
                updateNativePlaybackState(isPlaying: true, payload: payload)
            }
        case "YouTubeFullscreen":
            if let state = payload["state"] as? String {
                print("[ROZZA YouTube messenger] fullscreen:", state)
            }
        default:
            print("[ROZZA YouTube messenger] event:", event)
        }
    }

    func setYouTubeDeckVolume(_ value: Float) {
        youtubeDeckVolume = clamp(value)
        applyCrossfader()
    }

    func setAVDeckVolume(_ value: Float) {
        avDeckVolume = clamp(value)
        applyCrossfader()
    }

    func setCrossfader(_ value: Float) {
        crossfader = clamp(value)
        applyCrossfader()
    }

    func playYouTube() {
        print("[ROZZA NATIVE] playYouTube()")
        evaluateYouTube("""
        if (window.player && typeof window.player.playVideo === 'function') {
            window.player.playVideo();
        }
        """)
    }

    func pauseYouTube(reason: String = "Deck A Pause button") {
        print("[ROZZA NATIVE] pauseYouTube reason:", reason)
        evaluateYouTube("""
        if (window.player && typeof window.player.pauseVideo === 'function') {
            window.player.pauseVideo();
        }
        """)
    }

    func playAVPlayer() {
        guard avPlayer.currentItem != nil else {
            lastError = "Import an MP3/M4A or load a direct audio URL for Deck B first."
            return
        }
        avPlayer.play()
    }

    func pauseAVPlayer(reason: String = "Deck B Pause button") {
        print("AVPlayer pause requested by:", reason)
        avPlayer.pause()
    }

    func loadDirectURL(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            lastError = "Enter a valid direct HTTP/HTTPS audio URL."
            return
        }
        loadDeckB(url: url, name: url.lastPathComponent.isEmpty ? url.host ?? "Direct audio" : url.lastPathComponent)
    }

    func importLocalFile(_ sourceURL: URL) {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DJDeckB", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            loadDeckB(url: destination, name: sourceURL.lastPathComponent)
        } catch {
            lastError = "Could not import Deck B audio: \(error.localizedDescription)"
        }
    }

    private func loadDeckB(url: URL, name: String) {
        guard configureAudioSession() else { return }
        avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        deckBName = name
        lastError = nil
        applyAVPlayerVolume(avRequestedVolume)
    }

    private func applyCrossfader() {
        let x = clamp(crossfader)
        let youtubeGain = cosf(x * .pi / 2)
        let avGain = sinf(x * .pi / 2)
        applyYouTubeVolume(youtubeDeckVolume * youtubeGain)
        applyAVPlayerVolume(avDeckVolume * avGain)
    }

    private func applyYouTubeVolume(_ value: Float) {
        let normalized = clamp(value)
        latestYouTubeVolume = normalized
        youtubeRequestedVolume = normalized
        let percent = Int((normalized * 100).rounded())
        print("DJ YouTube requested volume:", percent, "ready:", youtubeReady)
        guard youtubeReady else { return }
        let script = """
        (() => {
          if (!window.player || typeof window.player.setVolume !== 'function') return false;
          window.player.setVolume(\(percent));
          if (\(percent) > 0) window.player.unMute();
          return { applied: true, reported: window.player.getVolume() };
        })()
        """
        evaluateYouTube(script) { result, error in
            print("DJ YouTube applied volume:", percent,
                  "result:", result ?? "nil",
                  "error:", error?.localizedDescription ?? "none")
        }
    }

    private func applyAVPlayerVolume(_ value: Float) {
        let normalized = clamp(value)
        avRequestedVolume = normalized
        avPlayer.isMuted = normalized == 0
        avPlayer.volume = normalized
        avActualVolume = avPlayer.volume
        print("DJ AVPlayer requested volume:", normalized, "applied:", avPlayer.volume)
    }

    private func evaluateYouTube(
        _ script: String,
        completion: ((Any?, Error?) -> Void)? = nil
    ) {
        guard let webView = persistentWebView else {
            completion?(nil, NSError(domain: "ROZZA.DJ", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView unavailable"]))
            return
        }
        webView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async { completion?(result, error) }
        }
    }

    private func refreshDebugState() {
        let session = AVAudioSession.sharedInstance()
        outputRoute = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        systemOutputVolume = session.outputVolume
        avActualVolume = avPlayer.volume
        isAVPlayerPlaying = avPlayer.timeControlStatus == .playing
        evaluateYouTube("window.rozzaDJ?.status()") { [weak self] result, _ in
            guard let self, let status = result as? [String: Any] else { return }
            let ready = status["ready"] as? Bool ?? false
            self.youtubeReady = ready
            self.isYouTubePlaying = status["playing"] as? Bool ?? false
            if let volume = status["reportedVolume"] as? NSNumber {
                self.youtubeReportedVolume = volume.floatValue / 100
            }
            if ready && !self.wasYouTubeReady {
                self.applyYouTubeVolume(self.latestYouTubeVolume)
            }
            self.wasYouTubeReady = ready
        }
    }

    @discardableResult
    private func configureAudioSession() -> Bool {
        do {
            try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
            let session = AVAudioSession.sharedInstance()
            outputRoute = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            systemOutputVolume = session.outputVolume
            return true
        } catch {
            let nsError = error as NSError
            lastError = "Audio session failed (OSStatus \(nsError.code)): \(nsError.localizedDescription)"
            return false
        }
    }

    private func beginBackgroundTransitionTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ROZZA.YouTubeBackgroundTransition") { [weak self] in
            Task { @MainActor in self?.endBackgroundTransitionTask() }
        }
    }

    private func endBackgroundTransitionTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Replays the same explicit PLAY route that already works from Control
    /// Center, but does it automatically during the short Home/lock transition.
    /// The JS side re-checks current source + user intent on every attempt, so
    /// a real user Pause always wins and a stale native callback cannot restart it.
    private func scheduleBackgroundYouTubeResumeKicks(generation: Int) {
        let delays: [Double] = [0.05, 0.18, 0.45, 0.90, 1.50, 2.40, 3.60]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      generation == self.backgroundResumeGeneration,
                      self.resumeYouTubeAfterBackgroundTransition else { return }
                self.configureAudioSession()
                let reason = "native-background-kick-\(index + 1)"
                self.evaluateYouTube("""
                (() => {
                  if (!window.ROZZANativeControls || typeof window.ROZZANativeControls.backgroundResumeIfWanted !== 'function') return { requested:false, reason:'bridge-missing' };
                  return window.ROZZANativeControls.backgroundResumeIfWanted('\(reason)');
                })()
                """) { result, error in
                    print("[ROZZA NATIVE] Background auto-resume \(reason) result=", result ?? "nil", "error=", error?.localizedDescription ?? "none")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) { [weak self] in
            guard let self, generation == self.backgroundResumeGeneration else { return }
            self.endBackgroundTransitionTask()
        }
    }

    private func observeAudioEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDebugState() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleSilenceHint(note) }
        })
        // Arm the background-only iframe bridge BEFORE WebKit receives its
        // normal hidden/blur transition. The bridge is inert in foreground
        // and never becomes a second foreground playback controller.
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            print("[ROZZA NATIVE] App inactive — preparing background bridge")
            Task { @MainActor in
                guard let self else { return }
                // Capture PLAY intent before WebKit gets a chance to report the
                // lifecycle PAUSE. This is intentionally a separate native flag;
                // isYouTubePlaying may flip false milliseconds later.
                // Build 21 used only isYouTubePlaying here. That flag was fed
                // by the background-only iframe bridge, which is deliberately
                // inert during ordinary foreground playback, so it could still
                // be false even while ROZZA was audibly playing YouTube. That
                // prevented the automatic background resume kicks from being
                // scheduled. Use the main player's mirrored user intent first.
                self.resumeYouTubeAfterBackgroundTransition = self.youtubeWantsPlayback || self.isYouTubePlaying
                print("[ROZZA NATIVE] Background capture wantsPlayback=", self.youtubeWantsPlayback, "isPlaying=", self.isYouTubePlaying, "resume=", self.resumeYouTubeAfterBackgroundTransition)
                self.backgroundResumeGeneration += 1
                let generation = self.backgroundResumeGeneration
                self.beginBackgroundTransitionTask()
                try? ROZZAAudioSession.shared.configureAndActivateIfNeeded()
                let nativeIntentWasPlaying = self.resumeYouTubeAfterBackgroundTransition
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.backgroundPrepare();") { result, _ in
                    let jsIntent = (result as? Bool) == true
                    if jsIntent && !self.resumeYouTubeAfterBackgroundTransition {
                        self.resumeYouTubeAfterBackgroundTransition = true
                        self.scheduleBackgroundYouTubeResumeKicks(generation: generation)
                    } else if !jsIntent && !nativeIntentWasPlaying {
                        self.endBackgroundTransitionTask()
                    }
                }
                if nativeIntentWasPlaying {
                    self.scheduleBackgroundYouTubeResumeKicks(generation: generation)
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            print("[ROZZA NATIVE] App background")
            Task { @MainActor in
                guard let self else { return }
                try? ROZZAAudioSession.shared.configureAndActivateIfNeeded()
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.background();")
                // If willResignActive captured a playing YouTube session, make
                // one immediate native kick too. The later bounded kicks are
                // only transition insurance; JS user intent is checked each time.
                if self.resumeYouTubeAfterBackgroundTransition {
                    self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.backgroundResumeIfWanted('did-enter-background');")
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            print("[ROZZA NATIVE] App will enter foreground")
            Task { @MainActor in
                guard let self else { return }
                self.resumeYouTubeAfterBackgroundTransition = false
                self.backgroundResumeGeneration += 1
                self.endBackgroundTransitionTask()
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.foreground();")
            }
        })
        // A second foreground signal is intentional: depending on when WebKit
        // is thawed, an evaluateJavaScript issued at willEnterForeground can be
        // delayed. didBecomeActive makes bridge teardown idempotent.
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            print("[ROZZA NATIVE] App active")
            Task { @MainActor in
                guard let self else { return }
                self.resumeYouTubeAfterBackgroundTransition = false
                self.backgroundResumeGeneration += 1
                self.endBackgroundTransitionTask()
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.foreground();")
            }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            print("[ROZZA NATIVE] Interruption began")
            // Told to JS first, before anything is paused: a PAUSED that
            // arrives while a real interruption is active must never be
            // read as "unexpected" and fought with a recovery attempt.
            evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.interruptionBegan();")
            ROZZAAudioSession.shared.markInterrupted()
            resumeAVAfterInterruption = avPlayer.timeControlStatus == .playing
            // Captured before pausing — YouTube's own isYouTubePlaying already
            // reflects rozza2.html's real state via the nowPlaying bridge, not
            // a guess.
            resumeYouTubeAfterInterruption = isYouTubePlaying
            pauseAVPlayer(reason: "iOS audio interruption began")
            pauseYouTube(reason: "iOS audio interruption began")
        } else {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            print("[ROZZA NATIVE] Interruption ended shouldResume=\(shouldResume) resumeAV=\(resumeAVAfterInterruption) resumeYouTube=\(resumeYouTubeAfterInterruption)")
            // Cleared before any resume is attempted, so a hiccup on resume is
            // free to be classified as a genuine unexpectedForegroundPause
            // rather than being permanently attributed to the interruption.
            evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.interruptionEnded();")
            do { try ROZZAAudioSession.shared.reactivateAfterInterruption() }
            catch { lastError = "Audio session reactivation failed: \(error.localizedDescription)" }
            guard shouldResume else { return }
            if resumeAVAfterInterruption {
                avPlayer.play()
            }
            // Only restore YouTube if it was genuinely playing before the
            // interruption — never as an unconditional force-resume.
            if resumeYouTubeAfterInterruption {
                playYouTube()
            }
        }
    }

    private func handleSilenceHint(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw) else { return }
        if type == .begin {
            avPlayer.isMuted = true
            evaluateYouTube("window.rozzaDJ?.setVolume(0)")
        } else {
            applyAVPlayerVolume(avRequestedVolume)
            applyYouTubeVolume(latestYouTubeVolume)
        }
    }

    private func clamp(_ value: Float) -> Float { min(1, max(0, value)) }

    func updateNowPlaying(info: [String: Any]) {
        var nowPlayingInfo = [String: Any]()
        if let title = info["title"] as? String {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        if let artist = info["artist"] as? String {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        if let duration = info["duration"] as? Double, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let elapsed = info["elapsed"] as? Double {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let isPlaying = info["isPlaying"] as? Bool {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

            // Main ROZZA -> native playback state handoff. The old Build 21
            // updated Lock Screen metadata here but never updated
            // isYouTubePlaying/youtubeWantsPlayback, leaving native lifecycle
            // code blind until the background-only bridge woke up.
            let source = (info["source"] as? String)?.lowercased()
            if source == "youtube" {
                isYouTubePlaying = isPlaying
                youtubeWantsPlayback = info["wantsPlayback"] as? Bool ?? isPlaying
            } else if source != nil {
                isYouTubePlaying = false
                youtubeWantsPlayback = false
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNativePlaybackState(isPlaying: Bool, payload: [String: Any]) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let elapsed = (payload["currentTime"] as? NSNumber)?.doubleValue {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // PLAY must explicitly play; PAUSE must explicitly pause. Both used to
        // call Coordinator.toggle() — if native and JS state disagreed even
        // briefly, "Play" could issue a pause and vice versa. Only the actual
        // togglePlayPauseCommand below uses toggle semantics.
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            print("[ROZZA NATIVE] Remote command: play")
            Task { @MainActor in
                self?.youtubeWantsPlayback = true
                self?.configureAudioSession()
                self?.evaluateYouTube("if(window.ROZZANativeControls) { window.ROZZANativeControls.play(); }")
                if self?.avPlayer.currentItem != nil { self?.playAVPlayer() }
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            print("[ROZZA NATIVE] Remote command: pause")
            Task { @MainActor in
                self?.youtubeWantsPlayback = false
                self?.evaluateYouTube("if(window.ROZZANativeControls) { window.ROZZANativeControls.pause(); }")
                self?.pauseAVPlayer(reason: "Lockscreen pause")
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            print("[ROZZA NATIVE] Remote command: togglePlayPause")
            Task { @MainActor in
                self?.configureAudioSession()
                self?.evaluateYouTube("if(window.Coordinator && typeof window.Coordinator.toggle === 'function') { window.Coordinator.toggle(); }")
                if let isPlaying = self?.isAVPlayerPlaying, isPlaying {
                    self?.pauseAVPlayer(reason: "Lockscreen toggle")
                } else if self?.avPlayer.currentItem != nil {
                    self?.playAVPlayer()
                }
            }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            print("[ROZZA NATIVE] Remote command: next")
            Task { @MainActor in
                self?.evaluateYouTube("if(window.Coordinator && typeof window.Coordinator.next === 'function') window.Coordinator.next(false);")
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            print("[ROZZA NATIVE] Remote command: previous")
            Task { @MainActor in
                self?.evaluateYouTube("if(window.Coordinator && typeof window.Coordinator.prev === 'function') window.Coordinator.prev();")
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = posEvent.positionTime
            Task { @MainActor in
                self?.evaluateYouTube("if(window.Coordinator && typeof window.Coordinator.seek === 'function') window.Coordinator.seek(\(seconds));")
                await self?.avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            }
            return .success
        }
    }
}
