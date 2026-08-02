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
            guard message.name == "audioSession", let action = message.body as? String else { return }
            if action == "activate" { activateAudioSession() }
        }

        private func activateAudioSession() {
            do {
                try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
            } catch {
                let nsError = error as NSError
                print("[ROZZA WebView] audioSession activation failed domain=\(nsError.domain) OSStatus=\(nsError.code) error=\(nsError)")
            }
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
