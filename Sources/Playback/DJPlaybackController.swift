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
    private var activePlaybackSource = ""
    private var hardUserPauseActive = false
    private var resumeYouTubeAfterBackgroundTransition = false
    private var backgroundResumeGeneration = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var remoteCommandTaskID: UIBackgroundTaskIdentifier = .invalid
    private var remoteCommandGeneration = 0
    private var artworkTask: URLSessionDataTask?
    private var lastArtworkURL: String?
    private var lastNowPlayingTrackID: String?
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
        artworkTask?.cancel()
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
            if hardUserPauseActive || !youtubeWantsPlayback {
                isYouTubePlaying = false
                enforcePausedTransportAfterHumanPause(reason: "stale-video-play")
            } else {
                _ = configureAudioSession()
                isYouTubePlaying = true
                updateNativePlaybackState(isPlaying: true, payload: payload)
            }
        case "VideoPause":
            isYouTubePlaying = false
            updateNativePlaybackState(isPlaying: false, payload: payload)
        case "VideoIsPlaying":
            let reportedPlaying = (payload["paused"] as? Bool) == false
            let effectivePlaying = reportedPlaying && youtubeWantsPlayback && !hardUserPauseActive
            if effectivePlaying { _ = configureAudioSession() }
            if reportedPlaying && !effectivePlaying {
                enforcePausedTransportAfterHumanPause(reason: "stale-video-is-playing")
            }
            if isYouTubePlaying != effectivePlaying {
                isYouTubePlaying = effectivePlaying
                updateNativePlaybackState(isPlaying: effectivePlaying, payload: payload)
            }
        case "BackgroundIntent":
            // Intent messages may also be emitted by automatic lifecycle sync.
            // A hard system/user Pause is authoritative until a real explicit
            // Play/Next/Previous command or main-player handoff clears it.
            let shouldPlay = payload["shouldPlay"] as? Bool ?? youtubeWantsPlayback
            let reason = (payload["reason"] as? String ?? "").lowercased()
            if !shouldPlay {
                youtubeWantsPlayback = false
                hardUserPauseActive = reason.contains("explicit-pause") || reason.contains("human") || reason.contains("remote") || hardUserPauseActive
            } else if !hardUserPauseActive {
                youtubeWantsPlayback = true
            }
        case "BackgroundVideoPlaying":
            _ = configureAudioSession()
            // Observation is NOT intent. A delayed automatic recovery event
            // must never turn a human Pause back into Play.
            if youtubeWantsPlayback && !hardUserPauseActive {
                isYouTubePlaying = true
                updateNativePlaybackState(isPlaying: true, payload: payload)
            } else {
                isYouTubePlaying = false
                enforcePausedTransportAfterHumanPause(reason: "stale-background-playing")
            }
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
            // Pulse reports transport state only; it cannot create user intent.
            if (payload["paused"] as? Bool) == false {
                if youtubeWantsPlayback && !hardUserPauseActive {
                    _ = configureAudioSession()
                    isYouTubePlaying = true
                    updateNativePlaybackState(isPlaying: true, payload: payload)
                } else {
                    isYouTubePlaying = false
                    enforcePausedTransportAfterHumanPause(reason: "stale-background-pulse")
                }
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

    private func beginRemoteCommandTask() {
        guard remoteCommandTaskID == .invalid else { return }
        remoteCommandTaskID = UIApplication.shared.beginBackgroundTask(withName: "ROZZA.RemoteCommand") { [weak self] in
            Task { @MainActor in self?.endRemoteCommandTask() }
        }
    }

    private func endRemoteCommandTask() {
        guard remoteCommandTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(remoteCommandTaskID)
        remoteCommandTaskID = .invalid
    }

    private func registerExplicitPlaybackIntent(shouldPlay: Bool, reason: String) {
        youtubeWantsPlayback = shouldPlay
        if shouldPlay {
            hardUserPauseActive = false
            _ = configureAudioSession()
        } else {
            // Human/system Pause is a hard fence: cancel every lifecycle resume
            // generation and interruption resume captured before the button tap.
            hardUserPauseActive = true
            isYouTubePlaying = false
            resumeYouTubeAfterBackgroundTransition = false
            resumeYouTubeAfterInterruption = false
            backgroundResumeGeneration += 1
            endBackgroundTransitionTask()
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        print("[ROZZA INTENT] explicit \(shouldPlay ? "PLAY" : "PAUSE") reason=\(reason)")
    }

    private func enforcePausedTransportAfterHumanPause(reason: String) {
        guard hardUserPauseActive, !youtubeWantsPlayback else { return }
        evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.enforceHumanPause) window.ROZZANativeControls.enforceHumanPause('\(reason)');")
    }

    /// System controls (car, Bluetooth, AirPods, Lock Screen and Control Center)
    /// can arrive while the WKWebView is already backgrounded. Give each
    /// transport request a short native execution window and require a JS-side
    /// acknowledgement. A failed/delayed evaluateJavaScript gets only two
    /// bounded retries; commands are never turned into a permanent polling loop.
    private func dispatchRemoteCommand(_ action: String, value: Double? = nil, shouldPlay: Bool? = nil) {
        var resolvedAction = action
        var resolvedShouldPlay = shouldPlay
        // Some cars/accessories send only togglePlayPauseCommand. Resolve that
        // against explicit intent, not a possibly stale WebKit playerState.
        if action == "toggle", activePlaybackSource == "youtube" {
            let shouldPause = youtubeWantsPlayback || isYouTubePlaying
            resolvedAction = shouldPause ? "pause" : "play"
            resolvedShouldPlay = !shouldPause
        }
        remoteCommandGeneration += 1
        let generation = remoteCommandGeneration
        if let resolvedShouldPlay {
            registerExplicitPlaybackIntent(shouldPlay: resolvedShouldPlay, reason: "remote-\(resolvedAction)")
        }
        beginRemoteCommandTask()
        performRemoteCommand(resolvedAction, value: value, generation: generation, attempt: 0)
        if resolvedShouldPlay == false && activePlaybackSource == "youtube" {
            // Guard against a delayed lifecycle recovery that was already queued
            // before the human pressed Pause. Each check aborts instantly if the
            // person presses Play again, so this can never fight fresh intent.
            [0.06, 0.24, 0.72].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, generation == self.remoteCommandGeneration,
                          self.hardUserPauseActive, !self.youtubeWantsPlayback else { return }
                    self.enforcePausedTransportAfterHumanPause(reason: "native-human-pause-fence")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, generation == self.remoteCommandGeneration else { return }
            self.endRemoteCommandTask()
        }
    }

    private func performRemoteCommand(_ action: String, value: Double?, generation: Int, attempt: Int) {
        guard generation == remoteCommandGeneration else { return }
        let jsValue = value.map { String(format: "%.3f", $0) } ?? "null"
        evaluateYouTube("""
        (() => {
          if (!window.ROZZANativeControls || typeof window.ROZZANativeControls.remote !== 'function') {
            return { ok:false, reason:'remote-bridge-missing' };
          }
          const result = window.ROZZANativeControls.remote('\(action)', \(jsValue), \(generation));
          return JSON.stringify(result || { ok:false, reason:'empty-ack' });
        })()
        """) { [weak self] result, error in
            guard let self, generation == self.remoteCommandGeneration else { return }
            var ack: [String: Any]?
            if let json = result as? String, let data = json.data(using: .utf8) {
                ack = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let ok = error == nil && (ack?["ok"] as? Bool) == true
            if let wantsPlayback = ack?["wantsPlayback"] as? Bool {
                self.youtubeWantsPlayback = wantsPlayback
            }
            print("[ROZZA REMOTE] action=\(action) attempt=\(attempt + 1) ok=\(ok) result=", ack ?? [:], "error=", error?.localizedDescription ?? "none")
            if !ok && attempt < 2 {
                let delay = attempt == 0 ? 0.12 : 0.38
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.performRemoteCommand(action, value: value, generation: generation, attempt: attempt + 1)
                }
                return
            }

            // For a remote Play/Next/Previous while backgrounded, the JS
            // command switches the queue first. Then pulse the real iframe
            // video for that newly selected track so the vehicle action does
            // not depend on a stale outer YouTube player state.
            if ok,
               UIApplication.shared.applicationState != .active,
               self.youtubeWantsPlayback,
               action == "play" || action == "toggle" || action == "next" || action == "previous" || action == "dislike" {
                [0.08, 0.30, 0.82].forEach { delay in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, generation == self.remoteCommandGeneration, self.youtubeWantsPlayback else { return }
                        _ = self.configureAudioSession()
                        self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.backgroundResumeIfWanted('remote-native-\(action)');")
                    }
                }
            }
        }
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
        if (info["clear"] as? Bool) == true {
            artworkTask?.cancel()
            artworkTask = nil
            lastArtworkURL = nil
            lastNowPlayingTrackID = nil
            isYouTubePlaying = false
            youtubeWantsPlayback = false
            hardUserPauseActive = false
            activePlaybackSource = ""
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let trackID = info["trackID"] as? String, trackID != lastNowPlayingTrackID {
            // Never leave the previous song's cover art visible while the new
            // artwork is still downloading (or if that download fails).
            artworkTask?.cancel()
            artworkTask = nil
            lastArtworkURL = nil
            lastNowPlayingTrackID = trackID
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        if let title = info["title"] as? String {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        if let artist = info["artist"] as? String {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        if let duration = (info["duration"] as? NSNumber)?.doubleValue, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        } else if let duration = info["duration"] as? Double, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let elapsed = (info["elapsed"] as? NSNumber)?.doubleValue {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        } else if let elapsed = info["elapsed"] as? Double {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let queueIndex = (info["queueIndex"] as? NSNumber)?.intValue {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = max(0, queueIndex)
        }
        if let queueCount = (info["queueCount"] as? NSNumber)?.intValue, queueCount > 0 {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if let isPlaying = info["isPlaying"] as? Bool {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

            // Main ROZZA -> native playback state handoff. This remains the
            // authoritative source for lifecycle + remote-command intent.
            let source = (info["source"] as? String)?.lowercased()
            activePlaybackSource = source ?? activePlaybackSource
            if source == "youtube" {
                let reportedIntent = info["wantsPlayback"] as? Bool ?? isPlaying
                if !reportedIntent {
                    youtubeWantsPlayback = false
                    isYouTubePlaying = false
                } else if !hardUserPauseActive || UIApplication.shared.applicationState == .active {
                    // In foreground, a new main-player PLAY is a real user/app
                    // action and may clear a previous Lock Screen hard pause.
                    hardUserPauseActive = false
                    youtubeWantsPlayback = true
                    isYouTubePlaying = isPlaying
                } else {
                    // While backgrounded, stale recovery metadata is never
                    // allowed to clear a hard remote Pause.
                    youtubeWantsPlayback = false
                    isYouTubePlaying = false
                }
            } else if source != nil {
                isYouTubePlaying = false
                youtubeWantsPlayback = false
                hardUserPauseActive = false
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        let artworkURLs = (info["artworkCandidates"] as? [String]) ?? ((info["artworkURL"] as? String).map { [$0] } ?? [])
        if !artworkURLs.isEmpty {
            updateNowPlayingArtwork(urlStrings: artworkURLs)
        }
    }

    private func updateNowPlayingArtwork(urlStrings: [String]) {
        var seenArtworkURLs = Set<String>()
        let candidates = urlStrings.filter { !$0.isEmpty && seenArtworkURLs.insert($0).inserted }
        guard let first = candidates.first, first != lastArtworkURL else { return }
        lastArtworkURL = first
        artworkTask?.cancel()

        func attempt(_ index: Int) {
            guard index < candidates.count,
                  self.lastArtworkURL == first,
                  let url = URL(string: candidates[index]),
                  url.scheme?.lowercased() == "https" else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8
            self.artworkTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, status == 0 || (200..<300).contains(status), let image = UIImage(data: data), image.size.width >= 480 else {
                    DispatchQueue.main.async { attempt(index + 1) }
                    return
                }
                DispatchQueue.main.async {
                    guard self.lastArtworkURL == first else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
                        // iOS can request multiple sizes; returning the original
                        // high-resolution image avoids an early lossy resize.
                        image
                    }
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
            self.artworkTask?.resume()
        }
        attempt(0)
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

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("play", shouldPlay: true) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("pause", shouldPlay: false) }
            return .success
        }

        center.stopCommand.isEnabled = true
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("stop", shouldPlay: false) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("toggle") }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("next", shouldPlay: true) }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("previous", shouldPlay: true) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.dispatchRemoteCommand("seekTo", value: event.positionTime) }
            return .success
        }

        // Some vehicle and accessory surfaces expose feedback commands. When
        // available, Like teaches ROZZA Brain and Dislike advances immediately.
        center.likeCommand.isEnabled = true
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("like") }
            return .success
        }

        center.dislikeCommand.isEnabled = true
        center.dislikeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("dislike", shouldPlay: true) }
            return .success
        }
    }
}
