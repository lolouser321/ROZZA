# Pure Tube behavior mapped into ROZZA

The supplied Pure Tube application executable is a compiled, signed iOS app and cannot be linked as a library inside another iOS application. It is not shipped in this project.

The usable behavior was mapped as follows:

| Supplied component | ROZZA implementation |
| --- | --- |
| Pure Tube executable | Used as a behavioral reference only |
| `yt_video_play_messenger.js` | Bundled unchanged in `Resources/`, injected **main-frame only** (see below) |
| WKWebView player | Implemented in `RozzaWebViewController.swift` |
| `UIBackgroundModes = audio` | Added in `Config/Info.plist` |
| Native audio session | `AVAudioSession` playback category in Swift |
| Lock Screen controls | `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` bridge |

## Phase 2 change: no longer injected into the YouTube embed

`yt_video_play_messenger.js` originally injected into **every** frame
(`forMainFrameOnly: false`), including the YouTube embed iframe itself, where
it read the embed's raw `<video>` element directly and called `focustApp()`
to spoof `document.hidden` / `visibilitychange` so the embed wouldn't react to
being backgrounded.

That is now removed. Two independent problems with it:

1. **Redundant.** `rozza2.html`'s own `YT` object already controls playback
   through the official, documented postMessage-based IFrame Player API
   (`cmd('playVideo', ...)` etc.), and already reports state to native via the
   `nowPlaying` bridge on every transition. The Pure Tube script's
   `VideoPlay`/`VideoPause`/`VideoIsPlaying` callback messages duplicated
   information Swift already had through the compliant channel.
2. **The wrong kind of fix.** Reaching into the embed's own DOM to override
   its pause behavior when backgrounded is a "keep the iframe going through a
   lock/background pause" hack — exactly what this build does not attempt.
   YouTube playback now follows YouTube's own foreground-only rules with no
   interference from ROZZA.

The script is still bundled and still injected, but `forMainFrameOnly` is now
`true`. `rozza2.html` itself has no `<video>` tags — the `Audio` object is an
unattached `HTMLAudioElement`, not a DOM `<video>` — so the script's scan loop
runs, finds nothing, and does nothing on the main frame. It no longer touches
the YouTube iframe's content in any way.

One minor, accepted trade-off: the script's `YouTubeFullscreen` message used
to hide/show the status bar when the user entered the embed's native
fullscreen. That signal required reaching into the iframe's own execution
context (WKUserScript injection can do this even across origins; ordinary
cross-origin JS cannot) and no longer fires. Status bar auto-hide during
YouTube fullscreen is lost; nothing else is.

YouTube playback still depends on iOS WebKit and YouTube behavior. Background playback must be verified on a real iPhone; the source does not claim that an untested build is guaranteed to survive every screen-lock or iOS update.
