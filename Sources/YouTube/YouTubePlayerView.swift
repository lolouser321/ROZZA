import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String?
    let provider: YouTubeEmbeddedProvider
    func makeCoordinator() -> Coordinator { Coordinator(provider: provider) }
    func makeUIView(context: Context) -> WKWebView {
        try? ROZZAAudioSession.shared.configureAndActivateIfNeeded()
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .black; view.scrollView.isScrollEnabled = false
        context.coordinator.webView = view; provider.bridge = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.videoID != videoID else { return }
        context.coordinator.videoID = videoID
        guard let videoID else { view.loadHTMLString("<body style='background:#000'></body>", baseURL: URL(string: "https://www.youtube.com")); return }
        context.coordinator.load(videoID: videoID)
    }
    final class Coordinator: NSObject, YouTubePlayerBridge {
        weak var webView: WKWebView?; weak var provider: YouTubeEmbeddedProvider?; var videoID: String?
        init(provider: YouTubeEmbeddedProvider) { self.provider = provider }
        func load(videoID: String) {
            self.videoID = videoID
            let escaped = videoID.replacingOccurrences(of: "'", with: "")
            let html = """
            <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
            <body style='margin:0;background:#000;overflow:hidden'><div id='player'></div>
            <script src='https://www.youtube.com/iframe_api'></script><script>
            var player; function onYouTubeIframeAPIReady(){ player=new YT.Player('player',{width:'100%',height:'100%',videoId:'\(escaped)',playerVars:{playsinline:1,controls:1,rel:0}}); }
            function play(){if(player)player.playVideo()} function pause(){if(player)player.pauseVideo()}
            function seek(v){if(player)player.seekTo(v,true)} function stop(){if(player)player.stopVideo()}
            </script></body></html>
            """
            webView?.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        }
        func play() { evaluate("play()") }; func pause() { evaluate("pause()") }; func seek(to seconds: TimeInterval) { evaluate("seek(\(seconds))") }; func stop() { evaluate("stop()") }
        private func evaluate(_ js: String) { webView?.evaluateJavaScript(js) }
    }
}

