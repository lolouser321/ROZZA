import Foundation
import WebKit

/// Installs the bundled YouTube video-event messenger into YouTube frames.
///
/// The JavaScript resource is kept as a separate, inspectable build resource.
/// Runtime scoping prevents YouTube-specific DOM hooks from changing ROZZA's
/// own document while still allowing the hooks to run in WKWebView subframes.
enum YouTubeMessengerBridge {
    static let handlerName = "callbackHandler"

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
