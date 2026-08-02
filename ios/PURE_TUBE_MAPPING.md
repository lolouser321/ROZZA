# Pure Tube behavior mapped into ROZZA

The supplied Pure Tube application executable is a compiled, signed iOS app and cannot be linked as a library inside another iOS application. It is not shipped in this project.

The usable behavior was mapped as follows:

| Supplied component | ROZZA implementation |
| --- | --- |
| Pure Tube executable | Used as a behavioral reference only |
| `yt_video_play_messenger.js` | Bundled unchanged in `Resources/` and injected into all WKWebView frames |
| WKWebView player | Implemented in `RozzaWebViewController.swift` |
| `UIBackgroundModes = audio` | Added in `Config/Info.plist` |
| Native audio session | `AVAudioSession` playback category in Swift |
| Lock Screen controls | `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` bridge |

YouTube playback still depends on iOS WebKit and YouTube behavior. Background playback must be verified on a real iPhone; the source does not claim that an untested build is guaranteed to survive every screen-lock or iOS update.
