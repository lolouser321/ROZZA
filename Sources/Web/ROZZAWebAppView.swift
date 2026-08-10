import SwiftUI
import UIKit
import WebKit

struct ROZZAWebAppView: UIViewRepresentable {
    @ObservedObject var dj: DJPlaybackController
    func makeCoordinator() -> Coordinator { Coordinator(dj: dj) }

    func makeUIView(context: Context) -> WKWebView {
        if let persistent = dj.persistentWebView {
            return persistent
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "audioSession")
        configuration.userContentController.add(context.coordinator, name: "nowPlaying")
        configuration.userContentController.add(context.coordinator, name: "haptics")
        configuration.userContentController.add(context.coordinator, name: "networkProxy")
        // Install only the new background-only bridge. It is injected into
        // YouTube frames at document start but remains inert until the main
        // ROZZA state machine explicitly arms it during app backgrounding.
        // The legacy yt_video_play_messenger.js controller remains disabled.
        YouTubeMessengerBridge.installBackgroundBridge(in: configuration, handler: context.coordinator)
        // YouTubeMessengerBridge.install(...) is intentionally NOT called.
        //
        // It injected yt_video_play_messenger.js directly into the YouTube
        // iframe, where it read/mutated the embed's own <video> element
        // (forcing .muted, .autoplay, re-attaching play/pause listeners via
        // MutationObserver, polling every 100ms) and overrode
        // document.hidden/visibilitychange so the embed wouldn't react to
        // being backgrounded — a second, uncoordinated control system fighting
        // rozza2.html's own compliant postMessage-based YT controller over the
        // same player. That is the root cause of YouTube audio stopping a
        // moment after starting, even in the foreground.
        //
        // No replacement bridge is installed because none is needed: the
        // "audioSession" and "nowPlaying" handlers above already receive
        // everything from the official channel — isPlaying, elapsed time,
        // duration, title, artist — via rozza2.html's own
        // postNowPlayingToNative()/activateNativeAudioSession(), which fire on
        // every real state transition. rozza2.html's YT object is the single
        // source of truth for YouTube playback; nothing native touches the
        // iframe's content.
        //
        // The JS resource file itself is left in place for reference, per
        // instruction — see Sources/Web/YouTubeMessengerBridge.swift.

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        context.coordinator.loadApp(in: webView)
        dj.attach(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // Intentionally keep the persistent mixer WebView and its script bridge
    // alive. SwiftUI state updates and DJ sheet presentation must not reload it.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private weak var dj: DJPlaybackController?

        init(dj: DJPlaybackController) { self.dj = dj }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "audioSession", let action = message.body as? String {
                if action == "activate" { activateAudioSession() }
            } else if message.name == "nowPlaying", let dict = message.body as? [String: Any] {
                dj?.updateNowPlaying(info: dict)
            } else if message.name == "haptics" {
                fireHaptic(message.body as? String ?? "light")
            } else if message.name == "networkProxy", message.frameInfo.isMainFrame,
                      let payload = message.body as? [String: Any] {
                proxyJSONRequest(payload)
            } else if message.name == YouTubeMessengerBridge.handlerName,
                      let payload = message.body as? [String: Any] {
                dj?.handleYouTubeMessengerEvent(payload)
            }
        }

        private func fireHaptic(_ kind: String) {
            switch kind {
            case "selection": UISelectionFeedbackGenerator().selectionChanged()
            case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "rigid": UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        private func activateAudioSession() {
            do {
                try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
            } catch {
                let nsError = error as NSError
                print("[ROZZA WebView] audioSession activation failed domain=\(nsError.domain) OSStatus=\(nsError.code) error=\(nsError)")
            }
        }

        /// Native metadata/search transport for ROZZA's public discovery APIs.
        /// WKWebView fetches can be rejected by CORS even when the same HTTPS
        /// endpoint is healthy. URLSession is not subject to browser CORS, so
        /// the web layer can use this as a bounded fallback instead of depending
        /// on public CORS proxy sites.
        private func proxyJSONRequest(_ payload: [String: Any]) {
            guard let requestID = payload["id"] as? String,
                  let rawURL = payload["url"] as? String,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else {
                return
            }

            let requestedTimeout = (payload["timeoutMs"] as? Double ?? 8000) / 1000.0
            let timeout = min(max(requestedTimeout, 2.0), 12.0)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("ROZZA/4.0.5 iOS", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let ok = error == nil && (200...299).contains(status) && !text.isEmpty
                let result: [String: Any] = [
                    "ok": ok,
                    "status": status,
                    "text": text,
                    "error": error?.localizedDescription ?? ""
                ]
                guard JSONSerialization.isValidJSONObject(result),
                      let resultData = try? JSONSerialization.data(withJSONObject: result),
                      let resultJSON = String(data: resultData, encoding: .utf8),
                      let idData = try? JSONSerialization.data(withJSONObject: requestID, options: .fragmentsAllowed),
                      let idJSON = String(data: idData, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    self?.dj?.persistentWebView?.evaluateJavaScript(
                        "window.ROZZANativeNetwork && window.ROZZANativeNetwork._resolve(\(idJSON), \(resultJSON));",
                        completionHandler: nil
                    )
                }
            }.resume()
        }

        func loadApp(in webView: WKWebView) {
            guard let url = Bundle.main.url(forResource: "rozza2", withExtension: "html"),
                  let html = try? String(contentsOf: url, encoding: .utf8) else {
                webView.loadHTMLString(Self.missingResourcePage, baseURL: nil)
                return
            }
            // A stable HTTPS base origin lets the official YouTube IFrame API
            // validate postMessage traffic and avoids file:// CORS restrictions.
            webView.loadHTMLString(html, baseURL: URL(string: "https://rozza.app/"))
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
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
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private static let missingResourcePage = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <body style="margin:0;background:#0d0406;color:#fff;font:16px -apple-system;padding:32px">
        ROZZA could not load its interface. Reinstall this build.
        </body>
        """
    }
}
