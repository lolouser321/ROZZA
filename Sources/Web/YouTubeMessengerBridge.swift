import Foundation
import WebKit

/// Installs the bundled YouTube video-event messenger into YouTube frames.
///
/// **Currently not called anywhere.** `ROZZAWebAppView.makeUIView` no longer
/// calls `install(in:handler:)`. This ran directly inside the YouTube
/// embed's own execution context — reading and mutating its `<video>`
/// element, forcing `muted`/`autoplay`, polling every 100ms, and overriding
/// `document.hidden`/`visibilitychange` — as a second, uncoordinated control
/// system alongside `rozza2.html`'s own compliant postMessage-based `YT`
/// object. That was the root cause of YouTube audio stopping shortly after
/// starting, in the foreground, with the app fully active.
///
/// The legacy file (and legacy installer) are kept for reference rather than
/// deleted. `rozza2.html`'s `YT` object remains the single source of truth for
/// foreground playback. A separate background-only bridge may be installed;
/// it is inert in foreground and never runs the legacy 100 ms polling/player
/// mutation loop.
enum YouTubeMessengerBridge {
    static let handlerName = "callbackHandler"

    /// Installs the minimal background-only YouTube lifecycle bridge.
    ///
    /// Unlike the legacy messenger, this script is inert during normal
    /// foreground playback. It only changes visibility handling after the
    /// main ROZZA controller explicitly arms background mode.
    static func installBackgroundBridge(
        in configuration: WKWebViewConfiguration,
        handler: WKScriptMessageHandler
    ) {
        configuration.userContentController.add(handler, name: handlerName)

        guard let resourceURL = Bundle.main.url(
            forResource: "yt_background_bridge",
            withExtension: "js"
        ) else {
            assertionFailure("yt_background_bridge.js is missing from the app bundle")
            return
        }

        do {
            let source = try String(contentsOf: resourceURL, encoding: .utf8)
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        } catch {
            assertionFailure("Could not load yt_background_bridge.js: \(error)")
        }
    }

    static func install(
        in configuration: WKWebViewConfiguration,
        handler: WKScriptMessageHandler
    ) {
        configuration.userContentController.add(handler, name: handlerName)

        guard let resourceURL = Bundle.main.url(
            forResource: "yt_video_play_messenger",
            withExtension: "js"
        ) else {
            assertionFailure("yt_video_play_messenger.js is missing from the app bundle")
            return
        }

        do {
            let source = try String(contentsOf: resourceURL, encoding: .utf8)
            let script = WKUserScript(
                source: scopedSource(from: source),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        } catch {
            assertionFailure("Could not load yt_video_play_messenger.js: \(error)")
        }
    }

    private static func scopedSource(from originalSource: String) -> String {
        let normalizedSource = originalSource.replacingOccurrences(of: "\r\n", with: "\n")

        // Some YouTube documents expose non-configurable visibility properties.
        // Keep the supplied resource unchanged on disk, but protect its focus
        // bootstrap at runtime so the remaining event bridge still installs.
        let hardenedSource = normalizedSource.replacingOccurrences(
            of: "\nfocustApp()\n",
            with: "\ntry { focustApp(); } catch (error) { console.debug('[ROZZA messenger] focus hook unavailable', error); }\n"
        )

        return """
        (() => {
          const host = String(window.location.hostname || '').toLowerCase();
          if (!/(^|\\.)youtube(-nocookie)?\\.com$/.test(host)) return;
          if (window.__rozzaYouTubeMessengerInstalled) return;
          window.__rozzaYouTubeMessengerInstalled = true;

          \(hardenedSource)

          try {
            if (typeof getVideoId === 'function') {
              const suppliedGetVideoId = getVideoId;
              getVideoId = function () {
                const suppliedID = suppliedGetVideoId();
                if (suppliedID) return suppliedID;
                const match = window.location.pathname.match(/^\\/embed\\/([A-Za-z0-9_-]{11})/);
                return match ? match[1] : null;
              };
            }
            if (typeof setupPlayPauseListener === 'function') setupPlayPauseListener();
          } catch (error) {
            console.debug('[ROZZA messenger] play/pause hook unavailable', error);
          }
        })();
        """
    }
}
