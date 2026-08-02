import AVFoundation
import MediaPlayer
import UIKit
import WebKit

final class RozzaWebViewController: UIViewController {
    private enum Handler: String, CaseIterable {
        case audioSession
        case nowPlaying
        case callbackHandler
    }

    private let webView: WKWebView
    private var lastKnownPlayingState = false
    private var nowPlayingInfo: [String: Any] = [:]
    private var artworkTask: URLSessionDataTask?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let contentController = WKUserContentController()
        configuration.userContentController = contentController

        if let bridgeURL = Bundle.main.url(forResource: "yt_video_play_messenger", withExtension: "js"),
           let bridgeSource = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            let bridge = WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            contentController.addUserScript(bridge)
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)

        Handler.allCases.forEach { contentController.add(self, name: $0.rawValue) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        Handler.allCases.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0.rawValue)
        }
        artworkTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.051, green: 0.016, blue: 0.024, alpha: 1)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.customUserAgent = "ROZZA/1.0 iOS Music Player"

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configureRemoteCommands()
        observeSystemAudioEvents()
        loadROZZA()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private func loadROZZA() {
        guard let htmlURL = Bundle.main.url(forResource: "rozza2", withExtension: "html"),
              let html = try? String(contentsOf: htmlURL, encoding: .utf8),
              let baseURL = URL(string: "https://rozza.local/") else {
            showLoadError()
            return
        }

        // An HTTPS base origin keeps YouTube's origin validation predictable while
        // the HTML itself remains bundled and available without a web server.
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func showLoadError() {
        let label = UILabel()
        label.text = "ROZZA could not load its bundled player."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            NSLog("[ROZZA] Could not activate audio session: %@", error.localizedDescription)
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            NSLog("[ROZZA] Could not deactivate audio session: %@", error.localizedDescription)
        }
    }

    private func observeSystemAudioEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            runNativeControl("pause")
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume), lastKnownPlayingState {
                activateAudioSession()
                runNativeControl("play")
            }
        @unknown default:
            break
        }
    }

    @objc private func appDidEnterBackground() {
        guard lastKnownPlayingState else { return }
        activateAudioSession()
        evaluate("if(typeof focustApp==='function'){try{focustApp()}catch(e){}}; if(window.ROZZANativeControls){window.ROZZANativeControls.background();}")
    }

    @objc private func appWillEnterForeground() {
        evaluate("if(window.ROZZANativeControls){window.ROZZANativeControls.foreground();}")
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.skipForwardCommand.isEnabled = true
        commands.skipBackwardCommand.isEnabled = true
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.preferredIntervals = [15]

        commands.playCommand.addTarget { [weak self] _ in
            self?.activateAudioSession()
            self?.runNativeControl("play")
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.runNativeControl("pause")
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            self?.runNativeControl("next")
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            self?.runNativeControl("previous")
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.runNativeControl("seekTo", value: positionEvent.positionTime)
            return .success
        }
        commands.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self?.runNativeControl("seekBy", value: interval)
            return .success
        }
        commands.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self?.runNativeControl("seekBy", value: -interval)
            return .success
        }
    }

    private func runNativeControl(_ action: String, value: Double? = nil) {
        let encodedAction = action.replacingOccurrences(of: "'", with: "")
        let argument = value.map { String($0) } ?? "undefined"
        evaluate("if(window.ROZZANativeControls){window.ROZZANativeControls['\(encodedAction)'](\(argument));}")
    }

    private func evaluate(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script) { _, error in
                if let error {
                    NSLog("[ROZZA] JavaScript bridge error: %@", error.localizedDescription)
                }
            }
        }
    }

    private func updateNowPlaying(from body: Any) {
        guard let payload = body as? [String: Any] else { return }

        let title = payload["title"] as? String ?? "ROZZA"
        let artist = payload["artist"] as? String ?? "ROZZA"
        let duration = number(payload["duration"])
        let elapsed = number(payload["elapsed"])
        let isPlaying = payload["isPlaying"] as? Bool ?? false
        let artworkURL = (payload["artwork"] as? String).flatMap(URL.init(string:))

        lastKnownPlayingState = isPlaying
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "ROZZA"
        if duration > 0 { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        if nowPlayingInfo[MPMediaItemPropertyArtwork] == nil,
           let fallback = UIImage(named: "LaunchIcon") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: fallback.size) { _ in fallback }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        loadArtworkIfNeeded(artworkURL)
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        artworkTask?.cancel()
        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            }
        }
        artworkTask?.resume()
    }

    private func handlePureTubeCallback(_ body: Any) {
        guard let payload = body as? [String: Any],
              let event = payload["event"] as? String else { return }

        switch event {
        case "VideoPlay", "VideoIsPlaying":
            if let paused = payload["paused"] as? Bool {
                lastKnownPlayingState = !paused
            }
            activateAudioSession()
        case "VideoPause":
            lastKnownPlayingState = false
        case "YouTubeFullscreen":
            setNeedsStatusBarUpdate()
        default:
            break
        }
    }

    private func number(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }
}

extension RozzaWebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let handler = Handler(rawValue: message.name) else { return }

        switch handler {
        case .audioSession:
            let command = message.body as? String
            command == "deactivate" ? deactivateAudioSession() : activateAudioSession()
        case .nowPlaying:
            updateNowPlaying(from: message.body)
        case .callbackHandler:
            handlePureTubeCallback(message.body)
        }
    }
}

extension RozzaWebViewController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluate("if(typeof setupPlayPauseListener==='function'){try{setupPlayPauseListener()}catch(e){}}")
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased()
        guard ["https", "http", "about", "blob", "data"].contains(scheme ?? "") else {
            decisionHandler(.cancel)
            return
        }

        // Keep the bundled app in place. User-requested top-level web links open
        // in Safari, while YouTube iframe and media subframe navigations remain
        // inside the WKWebView.
        if navigationAction.targetFrame?.isMainFrame == true,
           let host = url.host,
           host != "rozza.local" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}
