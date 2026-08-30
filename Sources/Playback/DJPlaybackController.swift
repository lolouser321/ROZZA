import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit
import WebKit

private enum PlaybackControlPhase: String {
    case playing = "PLAYING"
    case userPaused = "USER_PAUSED"
    case systemInterrupted = "SYSTEM_INTERRUPTED"
    case backgroundSuspended = "BACKGROUND_SUSPENDED"
    case resuming = "RESUMING"
}

private enum RemoteCommandSourceChannel: String {
    case mpRemoteCommandCenter = "mp-remote-command-center"
    case responderChain = "responder-chain"
    case webKitMediaSession = "webkit-media-session"
}

private struct AcceptedRemoteCommand {
    let action: String
    let sourceChannel: RemoteCommandSourceChannel
    let receivedAt: TimeInterval
    let commandID: Int
}

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
    private var scheduledBackgroundKickGeneration: Int?
    private var scheduledBackgroundKickWorkItems: [DispatchWorkItem] = []
    private var scheduledRemoteRecoveryWorkItems: [DispatchWorkItem] = []
    private var backgroundRecoverySucceededAt: TimeInterval = 0
    private let backgroundRecoveryCooldown: TimeInterval = 2.5
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var remoteCommandTaskID: UIBackgroundTaskIdentifier = .invalid
    private var remoteCommandGeneration = 0
    private var remoteCommandSequence = 0
    private var lastAcceptedRemoteCommand: AcceptedRemoteCommand?
    private let crossChannelRemoteDedupeWindow: TimeInterval = 0.55
    private var artworkTask: URLSessionDataTask?
    private var lastArtworkURL: String?
    private var lastNowPlayingTrackID: String?
    private var genuineInterruptionActive = false
    private var playbackControlPhase: PlaybackControlPhase = .userPaused
    private var interruptedPlaybackSessionID: String?
    private var activePlaybackSessionID: String?
    private var ignoredStartupInterruptionCount = 0
    // Real-device Build 36 diagnostics showed WebKit can emit an AVAudioSession
    // interruption within ~0.5s of an explicit YouTube Play, even after a very
    // brief PLAYING -> PAUSED report. Keep monotonic timestamps so that startup
    // ownership handoff can be classified without mutating user intent or using
    // an arbitrary "clear interruption later" timer.
    private var lastExplicitYouTubePlayIntentAt: TimeInterval = 0
    private var lastYouTubeTransportPlayingAt: TimeInterval = 0
    private let youtubeStartupInterruptionGrace: TimeInterval = 1.5
    private let youtubePostPlayingHandoffGrace: TimeInterval = 0.9
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
        UIApplication.shared.endReceivingRemoteControlEvents()
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
            // Transport observation is allowed to refresh isYouTubePlaying, but
            // it must never invent user intent. The Build 28 regression gated
            // this event on youtubeWantsPlayback; during the Home/lock race the
            // mirror can still be false for a few milliseconds, so the native
            // layer immediately paused a recovery that was actually correct.
            if hardUserPauseActive {
                isYouTubePlaying = false
                enforcePausedTransportAfterHumanPause(reason: "stale-video-play")
            } else {
                _ = configureAudioSession()
                isYouTubePlaying = true
                lastYouTubeTransportPlayingAt = ProcessInfo.processInfo.systemUptime
                if youtubeWantsPlayback && !genuineInterruptionActive { playbackControlPhase = .playing }
                updateNativePlaybackState(isPlaying: true, payload: payload)
                markBackgroundRecoverySucceeded(reason: "video-play")
            }
        case "VideoPause":
            isYouTubePlaying = false
            updateNativePlaybackState(isPlaying: false, payload: payload)
        case "VideoIsPlaying":
            let reportedPlaying = (payload["paused"] as? Bool) == false
            let effectivePlaying = reportedPlaying && !hardUserPauseActive
            if effectivePlaying { _ = configureAudioSession() }
            if reportedPlaying && hardUserPauseActive {
                enforcePausedTransportAfterHumanPause(reason: "stale-video-is-playing")
            }
            if isYouTubePlaying != effectivePlaying {
                isYouTubePlaying = effectivePlaying
                updateNativePlaybackState(isPlaying: effectivePlaying, payload: payload)
            }
        case "BackgroundIntent":
            // Transport-side mirror only. Build 29 still allowed this iframe
            // message to mutate native user intent, which left multiple sources
            // of truth competing with the main-frame playbackIntent channel.
            // Build 30 deliberately ignores it for intent decisions.
            let shouldPlay = payload["shouldPlay"] as? Bool ?? false
            let reason = payload["reason"] as? String ?? ""
            print("[ROZZA BRIDGE] background intent observation shouldPlay=\(shouldPlay) reason=\(reason)")
        case "BackgroundVideoPlaying":
            _ = configureAudioSession()
            // Observation is NOT intent. Accept the transport observation unless
            // a real human/system Pause fence is active. Crucially, do not require
            // the native intent mirror to already be true here: the iframe bridge
            // can beat the main-frame handoff during willResignActive.
            if hardUserPauseActive {
                isYouTubePlaying = false
                enforcePausedTransportAfterHumanPause(reason: "stale-background-playing")
            } else {
                isYouTubePlaying = true
                lastYouTubeTransportPlayingAt = ProcessInfo.processInfo.systemUptime
                if youtubeWantsPlayback && !genuineInterruptionActive { playbackControlPhase = .playing }
                updateNativePlaybackState(isPlaying: true, payload: payload)
                markBackgroundRecoverySucceeded(reason: "background-video-playing")
            }
        case "BackgroundVideoPause":
            // Transport observation only. User intent is owned exclusively by
            // playbackIntent / MPRemoteCommandCenter, never by iframe timing.
            let shouldPlay = payload["shouldPlay"] as? Bool ?? false
            if !shouldPlay || hardUserPauseActive {
                isYouTubePlaying = false
                updateNativePlaybackState(isPlaying: false, payload: payload)
            }
        case "BackgroundPulse":
            // Pulse reports transport state only; it cannot create user intent.
            if (payload["paused"] as? Bool) == false {
                if hardUserPauseActive {
                    isYouTubePlaying = false
                    enforcePausedTransportAfterHumanPause(reason: "stale-background-pulse")
                } else {
                    _ = configureAudioSession()
                    isYouTubePlaying = true
                    lastYouTubeTransportPlayingAt = ProcessInfo.processInfo.systemUptime
                    playbackControlPhase = .playing
                    updateNativePlaybackState(isPlaying: true, payload: payload)
                    markBackgroundRecoverySucceeded(reason: "background-pulse-playing")
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

    /// Explicit transport intent from the main ROZZA player. Unlike iframe
    /// play/pause observations, this message is sent only when the app/user
    /// intentionally changes whether playback should be running.
    func handlePlaybackIntent(_ payload: [String: Any]) {
        guard (payload["source"] as? String)?.lowercased() == "youtube",
              let shouldPlay = payload["shouldPlay"] as? Bool else { return }
        let reason = payload["reason"] as? String ?? "main-player"
        activePlaybackSource = "youtube"
        if shouldPlay {
            registerExplicitPlaybackIntent(shouldPlay: true, reason: "main-player-\(reason)")
        } else {
            registerExplicitPlaybackIntent(shouldPlay: false, reason: "main-player-\(reason)")
        }
    }

    /// WebKit MediaSession is a fallback receiver only. It must never operate
    /// the JavaScript player directly in the native shell, because doing so
    /// bypasses the authoritative native human-pause latch and generations.
    func handleWebKitRemoteCommand(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String,
              ["play", "pause", "stop", "toggle", "next", "previous"].contains(action) else { return }
        let value = (payload["value"] as? NSNumber)?.doubleValue
        let shouldPlay: Bool?
        switch action {
        case "play", "next", "previous": shouldPlay = true
        case "pause", "stop": shouldPlay = false
        default: shouldPlay = nil
        }
        dispatchRemoteCommand(
            action,
            value: value,
            shouldPlay: shouldPlay,
            sourceChannel: .webKitMediaSession
        )
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
        guard activateNativePlaybackSession() else { return }
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
        guard activateNativePlaybackSession() else { return }
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

    /// Native WebKit media suspension is the immediate transport fence for a
    /// human Pause or real iOS interruption. It does not alter JS intent, so
    /// system interruptions can still resume while a user Pause remains hard.
    private func suspendAllWebMedia(reason: String) {
        guard let webView = persistentWebView else { return }
        print("[ROZZA WEB MEDIA] SUSPEND reason=\(reason)")
        webView.setAllMediaPlaybackSuspended(true) {
            print("[ROZZA WEB MEDIA] SUSPENDED reason=\(reason)")
        }
    }

    private func resumeAllWebMediaIfAllowed(reason: String) {
        guard youtubeWantsPlayback,
              !hardUserPauseActive,
              !genuineInterruptionActive,
              let webView = persistentWebView else { return }
        print("[ROZZA WEB MEDIA] UNSUSPEND reason=\(reason)")
        webView.setAllMediaPlaybackSuspended(false) {
            print("[ROZZA WEB MEDIA] UNSUSPENDED reason=\(reason)")
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

    /// WebKit media path: configure the category but do not force native
    /// activation. YouTube/HTMLAudio is the audio owner and will activate the
    /// process media session as needed.
    @discardableResult
    private func configureAudioSession() -> Bool {
        do {
            try ROZZAAudioSession.shared.configureCategoryIfNeeded()
            let session = AVAudioSession.sharedInstance()
            outputRoute = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            systemOutputVolume = session.outputVolume
            return true
        } catch {
            let nsError = error as NSError
            lastError = "Audio category failed (OSStatus \(nsError.code)): \(nsError.localizedDescription)"
            return false
        }
    }

    /// Native-only AVPlayer path. This is the only regular playback path that
    /// explicitly calls setActive(true).
    @discardableResult
    private func activateNativePlaybackSession() -> Bool {
        do {
            try ROZZAAudioSession.shared.activateForNativePlaybackIfNeeded()
            let session = AVAudioSession.sharedInstance()
            outputRoute = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            systemOutputVolume = session.outputVolume
            return true
        } catch {
            let nsError = error as NSError
            lastError = "Native audio activation failed (OSStatus \(nsError.code)): \(nsError.localizedDescription)"
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

    private func cancelScheduledBackgroundKicks(reason: String) {
        scheduledBackgroundKickWorkItems.forEach { $0.cancel() }
        scheduledBackgroundKickWorkItems.removeAll()
        scheduledBackgroundKickGeneration = nil
        print("[ROZZA NATIVE] Background kicks cancelled reason=\(reason)")
    }

    private func cancelScheduledRemoteRecovery(reason: String) {
        scheduledRemoteRecoveryWorkItems.forEach { $0.cancel() }
        scheduledRemoteRecoveryWorkItems.removeAll()
        print("[ROZZA NATIVE] Remote recovery callbacks cancelled reason=\(reason)")
    }

    private func markBackgroundRecoverySucceeded(reason: String) {
        guard UIApplication.shared.applicationState != .active,
              youtubeWantsPlayback,
              !hardUserPauseActive,
              !genuineInterruptionActive,
              resumeYouTubeAfterBackgroundTransition || !scheduledRemoteRecoveryWorkItems.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        if now - backgroundRecoverySucceededAt < backgroundRecoveryCooldown { return }
        backgroundRecoverySucceededAt = now
        resumeYouTubeAfterBackgroundTransition = false
        backgroundResumeGeneration += 1
        cancelScheduledBackgroundKicks(reason: reason)
        cancelScheduledRemoteRecovery(reason: reason)
        endBackgroundTransitionTask()
        evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.backgroundRecoveryConfirmed) window.ROZZANativeControls.backgroundRecoveryConfirmed('\(reason)');")
        print("[ROZZA NATIVE] Background recovery succeeded at=\(now) cooldown=\(backgroundRecoveryCooldown)s reason=\(reason)")
    }

    private func registerExplicitPlaybackIntent(shouldPlay: Bool, reason: String) {
        // Any fresh human intent invalidates delayed work created for the
        // preceding transport command. Remote commands capture the new value
        // after this method returns; in-app commands simply invalidate it.
        remoteCommandGeneration += 1
        youtubeWantsPlayback = shouldPlay
        if shouldPlay {
            hardUserPauseActive = false
            lastExplicitYouTubePlayIntentAt = ProcessInfo.processInfo.systemUptime
            // Explicit Play means the transport is trying to start. Only a
            // confirmed VideoPlay/BackgroundVideoPlaying observation promotes
            // the state to PLAYING. This distinction is what lets the native
            // interruption handler identify WebKit's startup audio handoff
            // without relying on a fragile time window.
            playbackControlPhase = genuineInterruptionActive ? .systemInterrupted : .resuming
            if genuineInterruptionActive {
                resumeYouTubeAfterInterruption = true
                if interruptedPlaybackSessionID == nil {
                    interruptedPlaybackSessionID = activePlaybackSessionID
                }
            }
            _ = configureAudioSession()
            resumeAllWebMediaIfAllowed(reason: reason)
        } else {
            // Human/system Pause is a hard fence: cancel every lifecycle resume
            // generation and interruption resume captured before the button tap.
            hardUserPauseActive = true
            playbackControlPhase = .userPaused
            isYouTubePlaying = false
            resumeYouTubeAfterBackgroundTransition = false
            resumeYouTubeAfterInterruption = false
            backgroundResumeGeneration += 1
            cancelScheduledBackgroundKicks(reason: "human-pause")
            cancelScheduledRemoteRecovery(reason: "human-pause")
            endBackgroundTransitionTask()
            endRemoteCommandTask()
            suspendAllWebMedia(reason: reason)
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
    private func dispatchRemoteCommand(
        _ action: String,
        value: Double? = nil,
        shouldPlay: Bool? = nil,
        sourceChannel: RemoteCommandSourceChannel
    ) {
        let requestedAction = action
        var resolvedAction = action
        var resolvedShouldPlay = shouldPlay
        // Some cars/accessories send only togglePlayPauseCommand. Resolve that
        // against explicit intent, not a possibly stale WebKit playerState.
        if action == "toggle", activePlaybackSource == "youtube" {
            let shouldPause = youtubeWantsPlayback
            resolvedAction = shouldPause ? "pause" : "play"
            resolvedShouldPlay = !shouldPause
        }
        remoteCommandSequence += 1
        let commandID = remoteCommandSequence
        let receivedAt = ProcessInfo.processInfo.systemUptime
        let nowPlaying = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let beforeIndex = (nowPlaying[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? NSNumber)?.intValue ?? -1
        let beforeVideoID = activePlaybackSessionID ?? "none"
        let foreground = UIApplication.shared.applicationState == .active

        // iOS may deliver one physical press through MPRemoteCommandCenter and
        // either the responder chain or WebKit MediaSession. Dedupe here,
        // before explicit intent or queue mutation, so every fallback still
        // enters one authoritative native path without executing twice.
        let togglePair = lastAcceptedRemoteCommand.map { last in
            (last.action == "toggle" && ["play", "pause"].contains(requestedAction)) ||
            (requestedAction == "toggle" && ["play", "pause"].contains(last.action))
        } ?? false
        if let last = lastAcceptedRemoteCommand,
           (last.action == requestedAction || togglePair),
           last.sourceChannel != sourceChannel,
           receivedAt - last.receivedAt < crossChannelRemoteDedupeWindow {
            print("[ROZZA REMOTE] \(requestedAction.uppercased()) sourceChannel=\(sourceChannel.rawValue) commandID=\(commandID) queueIndexBefore=\(beforeIndex) queueIndexAfter=\(beforeIndex) videoId=\(beforeVideoID) wantPlay=\(youtubeWantsPlayback) humanPauseActive=\(hardUserPauseActive) accepted=false rejectionReason=duplicate-of-\(last.sourceChannel.rawValue)-command-\(last.commandID)")
            return
        }
        lastAcceptedRemoteCommand = AcceptedRemoteCommand(
            action: requestedAction,
            sourceChannel: sourceChannel,
            receivedAt: receivedAt,
            commandID: commandID
        )

        // Keep the process declared as a playback app for Lock Screen / vehicle
        // routing, but never force native AVAudioSession activation for YouTube.
        _ = configureAudioSession()
        if let resolvedShouldPlay {
            registerExplicitPlaybackIntent(
                shouldPlay: resolvedShouldPlay,
                reason: "remote-\(sourceChannel.rawValue)-\(resolvedAction)"
            )
        } else {
            remoteCommandGeneration += 1
        }
        let generation = remoteCommandGeneration
        let label = requestedAction.uppercased()
        print("[ROZZA REMOTE] \(label) sourceChannel=\(sourceChannel.rawValue) commandID=\(commandID) queueIndexBefore=\(beforeIndex) queueIndexAfter=pending videoId=\(beforeVideoID) wantPlay=\(youtubeWantsPlayback) humanPauseActive=\(hardUserPauseActive) accepted=pending rejectionReason=none foreground=\(foreground) phase=\(playbackControlPhase.rawValue)")
        beginRemoteCommandTask()
        performRemoteCommand(
            resolvedAction,
            value: value,
            generation: generation,
            commandID: commandID,
            attempt: 0,
            beforeIndex: beforeIndex,
            beforeVideoID: beforeVideoID,
            logAction: requestedAction,
            sourceChannel: sourceChannel
        )
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

    private func performRemoteCommand(
        _ action: String,
        value: Double?,
        generation: Int,
        commandID: Int,
        attempt: Int,
        beforeIndex: Int,
        beforeVideoID: String,
        logAction: String,
        sourceChannel: RemoteCommandSourceChannel
    ) {
        guard generation == remoteCommandGeneration else { return }
        let jsValue = value.map { String(format: "%.3f", $0) } ?? "null"
        evaluateYouTube("""
        (() => {
          if (!window.ROZZANativeControls || typeof window.ROZZANativeControls.remote !== 'function') {
            return { ok:false, reason:'remote-bridge-missing' };
          }
          const result = window.ROZZANativeControls.remote('\(action)', \(jsValue), \(generation), '\(sourceChannel.rawValue)');
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
            let afterIndex = (ack?["index"] as? NSNumber)?.intValue ?? beforeIndex
            let afterVideoID = (ack?["trackID"] as? String) ?? self.activePlaybackSessionID ?? "none"
            let rejectionReason = (ack?["reason"] as? String) ?? error?.localizedDescription ?? (ok ? "none" : "unknown")
            let foreground = UIApplication.shared.applicationState == .active
            print("[ROZZA REMOTE] \(logAction.uppercased()) sourceChannel=\(sourceChannel.rawValue) commandID=\(commandID) queueIndexBefore=\(beforeIndex) queueIndexAfter=\(afterIndex) videoId=\(afterVideoID) previousVideoId=\(beforeVideoID) wantPlay=\(self.youtubeWantsPlayback) humanPauseActive=\(self.hardUserPauseActive) accepted=\(ok) rejectionReason=\(rejectionReason) foreground=\(foreground) phase=\(self.playbackControlPhase.rawValue) attempt=\(attempt + 1)")
            if !ok && attempt < 2 {
                let delay = attempt == 0 ? 0.12 : 0.38
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.performRemoteCommand(
                        action,
                        value: value,
                        generation: generation,
                        commandID: commandID,
                        attempt: attempt + 1,
                        beforeIndex: beforeIndex,
                        beforeVideoID: beforeVideoID,
                        logAction: logAction,
                        sourceChannel: sourceChannel
                    )
                }
                return
            }

            // A remote Next/Previous already autoplays inside Coordinator's
            // track switch. Only an explicit remote Play gets bounded native
            // recovery callbacks; sending another Play after a track switch
            // can double-advance some accessory/control paths.
            if ok,
               UIApplication.shared.applicationState != .active,
               self.youtubeWantsPlayback,
               !self.hardUserPauseActive,
               !self.genuineInterruptionActive,
               action == "play" {
                self.cancelScheduledRemoteRecovery(reason: "new-remote-play")
                [0.08, 0.30, 0.82].forEach { delay in
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self,
                              generation == self.remoteCommandGeneration,
                              self.youtubeWantsPlayback,
                              !self.hardUserPauseActive,
                              !self.genuineInterruptionActive else { return }
                        _ = self.configureAudioSession()
                        self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.backgroundResumeIfWanted('remote-native-\(action)');")
                    }
                    self.scheduledRemoteRecoveryWorkItems.append(workItem)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                }
            }
        }
    }

    /// Replays the same explicit PLAY route that already works from Control
    /// Center, but does it automatically during the short Home/lock transition.
    /// The JS side re-checks current source + user intent on every attempt, so
    /// a real user Pause always wins and a stale native callback cannot restart it.
    private func scheduleBackgroundYouTubeResumeKicks(generation: Int) {
        guard scheduledBackgroundKickGeneration != generation else { return }
        cancelScheduledBackgroundKicks(reason: "new-transition")
        scheduledBackgroundKickGeneration = generation
        let delays: [Double] = [0.05, 0.18, 0.45, 0.90, 1.50, 2.40, 3.60]
        for (index, delay) in delays.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      generation == self.backgroundResumeGeneration,
                      self.resumeYouTubeAfterBackgroundTransition,
                      self.youtubeWantsPlayback,
                      !self.hardUserPauseActive,
                      !self.genuineInterruptionActive else { return }
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
            scheduledBackgroundKickWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        let completionWorkItem = DispatchWorkItem { [weak self] in
            guard let self, generation == self.backgroundResumeGeneration else { return }
            self.endBackgroundTransitionTask()
        }
        scheduledBackgroundKickWorkItems.append(completionWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8, execute: completionWorkItem)
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
                if self.resumeYouTubeAfterBackgroundTransition && !self.genuineInterruptionActive {
                    self.playbackControlPhase = .backgroundSuspended
                }
                print("[ROZZA NATIVE] Background capture wantsPlayback=", self.youtubeWantsPlayback, "isPlaying=", self.isYouTubePlaying, "resume=", self.resumeYouTubeAfterBackgroundTransition)
                self.cancelScheduledBackgroundKicks(reason: "will-resign-active")
                self.backgroundRecoverySucceededAt = 0
                self.backgroundResumeGeneration += 1
                let generation = self.backgroundResumeGeneration
                self.beginBackgroundTransitionTask()
                _ = self.configureAudioSession()
                let nativeIntentWasPlaying = self.resumeYouTubeAfterBackgroundTransition
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.backgroundPrepare();") { result, _ in
                    guard generation == self.backgroundResumeGeneration else { return }
                    let jsIntent = (result as? Bool) == true
                    // backgroundPrepare() reads YT.wantPlay from the main player,
                    // so this is genuine intent, not a transport observation.
                    if jsIntent && !self.hardUserPauseActive {
                        self.youtubeWantsPlayback = true
                        if !self.resumeYouTubeAfterBackgroundTransition {
                            self.resumeYouTubeAfterBackgroundTransition = true
                            self.scheduleBackgroundYouTubeResumeKicks(generation: generation)
                        }
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
                _ = self.configureAudioSession()
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.background();")
                // If willResignActive captured a playing YouTube session, make
                // one immediate native kick too. The later bounded kicks are
                // only transition insurance; JS user intent is checked each time.
                if self.resumeYouTubeAfterBackgroundTransition &&
                    self.youtubeWantsPlayback &&
                    !self.hardUserPauseActive &&
                    !self.genuineInterruptionActive {
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
                self.cancelScheduledBackgroundKicks(reason: "will-enter-foreground")
                self.cancelScheduledRemoteRecovery(reason: "will-enter-foreground")
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
                self.cancelScheduledBackgroundKicks(reason: "did-become-active")
                self.cancelScheduledRemoteRecovery(reason: "did-become-active")
                self.endBackgroundTransitionTask()
                self.evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.foreground();")
            }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        let reasonRaw = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.uintValue
        let reasonText = reasonRaw.map { String($0) } ?? "nil"
        let reason = reasonRaw.flatMap { AVAudioSession.InterruptionReason(rawValue: $0) }
        let wasSuspended = (notification.userInfo?[AVAudioSessionInterruptionWasSuspendedKey] as? NSNumber)?.boolValue ?? false
        let appState = UIApplication.shared.applicationState
        let foreground = appState == .active
        let source = activePlaybackSource.isEmpty ? "none" : activePlaybackSource
        let videoID = activePlaybackSessionID ?? "none"
        let context = "source=\(source) foreground=\(foreground) wantPlay=\(youtubeWantsPlayback) humanPauseActive=\(hardUserPauseActive) videoID=\(videoID) session=\(videoID) bgGeneration=\(backgroundResumeGeneration) remoteGeneration=\(remoteCommandGeneration) phase=\(playbackControlPhase.rawValue) reasonRaw=\(reasonText) wasSuspended=\(wasSuspended)"

        if type == .began {
            print("[ROZZA INTERRUPT] BEGIN \(context)")

            // `.began` does not identify phone/Siri by itself. WebKit emits
            // the same notification while taking audio ownership during
            // BUFFERING/UNSTARTED, and iOS can deliver lifecycle deactivation
            // notifications after suspending the app. Classify those using
            // the transport state and documented reason/suspension metadata,
            // never an elapsed-time guess.
            let isYouTube = activePlaybackSource == "youtube"
            let nowUptime = ProcessInfo.processInfo.systemUptime
            let explicitPlayAge = lastExplicitYouTubePlayIntentAt > 0
                ? nowUptime - lastExplicitYouTubePlayIntentAt
                : .greatestFiniteMagnitude
            let transportPlayingAge = lastYouTubeTransportPlayingAt > 0
                ? nowUptime - lastYouTubeTransportPlayingAt
                : .greatestFiniteMagnitude

            // Real iPhones can report WebKit's audio ownership handoff as an
            // AVAudioSession interruption immediately after Play. The transport
            // can even flash PLAYING -> PAUSED before this notification arrives,
            // which means `playbackControlPhase == .resuming` alone is too weak.
            // Classify only the narrow startup/just-started window while the app
            // is foregrounded and user intent is still PLAY. A phone/Siri
            // interruption after stable playback falls outside this window and
            // continues through the genuine-interruption path below.
            let youtubeStartupHandoff =
                isYouTube &&
                foreground &&
                youtubeWantsPlayback &&
                !hardUserPauseActive &&
                !wasSuspended &&
                reason != .appWasSuspended &&
                (playbackControlPhase == .resuming ||
                 explicitPlayAge <= youtubeStartupInterruptionGrace ||
                 transportPlayingAge <= youtubePostPlayingHandoffGrace)

            let youtubeLifecycleDeactivation =
                isYouTube &&
                (wasSuspended || reason == .appWasSuspended)

            if youtubeStartupHandoff || youtubeLifecycleDeactivation {
                ignoredStartupInterruptionCount += 1
                genuineInterruptionActive = false
                let classification = youtubeStartupHandoff ? "webkit-startup-handoff" : "lifecycle-deactivation"
                print("[ROZZA INTERRUPT] IGNORED_YOUTUBE_STARTUP count=\(ignoredStartupInterruptionCount) classification=\(classification) explicitPlayAge=\(String(format: "%.3f", explicitPlayAge)) transportPlayingAge=\(String(format: "%.3f", transportPlayingAge)) \(context)")
                // Never suspend WebKit and never create JS interruption state for
                // this ownership handoff. If an older callback set the flag,
                // clear it idempotently so background recovery cannot be blocked.
                evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.clearInterruptionFlag) window.ROZZANativeControls.clearInterruptionFlag('ignored-youtube-startup');")
                if youtubeWantsPlayback && !hardUserPauseActive {
                    playbackControlPhase = .resuming
                    resumeAllWebMediaIfAllowed(reason: "ignored-youtube-startup")
                }
                return
            }

            // A notification while the YouTube transport is intentionally
            // paused has no playback to interrupt and must not create a future
            // resume entitlement.
            if isYouTube && (!youtubeWantsPlayback || hardUserPauseActive) {
                print("[ROZZA INTERRUPT] IGNORED_INACTIVE_YOUTUBE \(context)")
                return
            }

            if genuineInterruptionActive {
                print("[ROZZA INTERRUPT] GENUINE_EXTERNAL duplicate=true \(context)")
                ROZZAAudioSession.shared.markInterrupted()
                return
            }

            genuineInterruptionActive = true
            playbackControlPhase = .systemInterrupted
            interruptedPlaybackSessionID = activePlaybackSessionID
            resumeYouTubeAfterBackgroundTransition = false
            backgroundResumeGeneration += 1
            cancelScheduledBackgroundKicks(reason: "system-interruption")
            cancelScheduledRemoteRecovery(reason: "system-interruption")
            suspendAllWebMedia(reason: "iOS-audio-interruption")
            print("[ROZZA INTERRUPT] GENUINE_EXTERNAL \(context)")
            evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.interruptionBegan();")
            ROZZAAudioSession.shared.markInterrupted()
            resumeAVAfterInterruption = avPlayer.timeControlStatus == .playing
            resumeYouTubeAfterInterruption = isYouTube && youtubeWantsPlayback && !hardUserPauseActive

            if resumeAVAfterInterruption {
                pauseAVPlayer(reason: "iOS audio interruption began")
            }

            // Critical: never call window.player.pauseVideo() here. That facade
            // intentionally means explicit/user Pause. Suspend transport while
            // preserving YT.wantPlay so a real interruption can resume later.
            if activePlaybackSource == "youtube" {
                evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.suspendForInterruption) window.ROZZANativeControls.suspendForInterruption();")
            }
            return
        }

        // An `.ended` can arrive after a startup handoff that we deliberately
        // ignored. Do not manufacture a recovery cycle for something we never
        // classified as a genuine interruption.
        guard genuineInterruptionActive else {
            print("[ROZZA INTERRUPT] END ignored=no-genuine-interruption \(context)")
            evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.clearInterruptionFlag) window.ROZZANativeControls.clearInterruptionFlag('non-genuine-interruption-ended');")
            return
        }
        genuineInterruptionActive = false

        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
        print("[ROZZA INTERRUPT] END shouldResume=\(shouldResume) resumeAV=\(resumeAVAfterInterruption) resumeYouTube=\(resumeYouTubeAfterInterruption) \(context)")
        evaluateYouTube("if(window.ROZZANativeControls) window.ROZZANativeControls.interruptionEnded();")

        if resumeAVAfterInterruption {
            do { try ROZZAAudioSession.shared.reactivateNativePlaybackAfterInterruption() }
            catch { lastError = "Native audio reactivation failed: \(error.localizedDescription)" }
            if shouldResume { avPlayer.play() }
        }

        // Preserve explicit user intent. A real interruption ending is a
        // transport resume, not a fresh human Play command.
        let sameSession = interruptedPlaybackSessionID != nil && interruptedPlaybackSessionID == activePlaybackSessionID
        if shouldResume && resumeYouTubeAfterInterruption && youtubeWantsPlayback && !hardUserPauseActive && sameSession {
            playbackControlPhase = .resuming
            resumeAllWebMediaIfAllowed(reason: "iOS-interruption-ended")
            evaluateYouTube("if(window.ROZZANativeControls && window.ROZZANativeControls.resumeAfterInterruption) window.ROZZANativeControls.resumeAfterInterruption();")
            print("[ROZZA INTERRUPT] RESUME source=youtube shouldResume=true videoID=\(videoID) session=\(videoID) bgGeneration=\(backgroundResumeGeneration) remoteGeneration=\(remoteCommandGeneration)")
        } else if hardUserPauseActive || !youtubeWantsPlayback {
            playbackControlPhase = .userPaused
        } else {
            playbackControlPhase = .backgroundSuspended
        }
        resumeAVAfterInterruption = false
        resumeYouTubeAfterInterruption = false
        interruptedPlaybackSessionID = nil
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
            activePlaybackSource = ""
            activePlaybackSessionID = nil
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
            activePlaybackSessionID = trackID
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

            // Metadata is transport observation only. Explicit user intent now
            // has exactly one authority: playbackIntent / remote commands.
            // This prevents a delayed Now Playing refresh from turning Play
            // into Pause (or vice versa) during Home/Lock transitions.
            let source = (info["source"] as? String)?.lowercased()
            activePlaybackSource = source ?? activePlaybackSource
            if source == "youtube" {
                isYouTubePlaying = isPlaying && !hardUserPauseActive
            } else if source != nil {
                isYouTubePlaying = false
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


    /// Fallback for legacy/responder-chain remote events. Some real iPhones
    /// route Lock Screen/AirPods/car commands to the WKWebView responder while
    /// WebKit owns YouTube audio, bypassing MPRemoteCommandCenter entirely.
    /// Feed those events into the exact same explicit-intent command path.
    func handleResponderRemoteControlEvent(_ subtype: UIEvent.EventSubtype) {
        let action: String
        let shouldPlay: Bool?

        switch subtype {
        case .remoteControlPlay:
            action = "play"; shouldPlay = true
        case .remoteControlPause:
            action = "pause"; shouldPlay = false
        case .remoteControlStop:
            action = "stop"; shouldPlay = false
        case .remoteControlTogglePlayPause:
            action = "toggle"; shouldPlay = nil
        case .remoteControlNextTrack:
            action = "next"; shouldPlay = true
        case .remoteControlPreviousTrack:
            action = "previous"; shouldPlay = true
        default:
            return
        }

        dispatchRemoteCommand(
            action,
            shouldPlay: shouldPlay,
            sourceChannel: .responderChain
        )
    }

    private func configureRemoteCommands() {
        // Make ROZZA an explicit receiver for accessory / vehicle transport
        // events. WebKit MediaSession also forwards commands because WKWebView
        // owns the audible YouTube element; the JS bridge dedupes the two
        // delivery channels so a physical button press executes exactly once.
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()

        // Own the system transport surface exclusively. Removing old targets
        // prevents duplicate handlers if the controller is recreated during
        // development or another legacy playback object is ever initialized.
        [center.playCommand, center.pauseCommand, center.stopCommand,
         center.togglePlayPauseCommand, center.nextTrackCommand,
         center.previousTrackCommand, center.changePlaybackPositionCommand,
         center.skipForwardCommand, center.skipBackwardCommand,
         center.likeCommand, center.dislikeCommand].forEach { $0.removeTarget(nil) }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("play", shouldPlay: true, sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("pause", shouldPlay: false, sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        center.stopCommand.isEnabled = true
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("stop", shouldPlay: false, sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("toggle", sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("next", shouldPlay: true, sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dispatchRemoteCommand("previous", shouldPlay: true, sourceChannel: .mpRemoteCommandCenter) }
            return .success
        }

        // Prefer real Track Previous / Next on Lock Screen, AirPods and car
        // head units. Enabling skipForward/skipBackward at the same time makes
        // some system surfaces choose ±15s instead of previous/next track.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        // Keep the native system surface track-oriented. WebKit was causing
        // Lock Screen to prefer ±10s/seek controls over Previous/Next.
        center.changePlaybackPositionCommand.isEnabled = false

        // Keep vehicle/headset transport surfaces focused on the controls the
        // user actually needs. Feedback commands can crowd out Previous/Next on
        // some head units and are still available inside the ROZZA UI.
        center.likeCommand.isEnabled = false
        center.dislikeCommand.isEnabled = false
    }
}
