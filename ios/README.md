# ROZZA for iOS

This folder wraps the existing `rozza2.html` player in a native UIKit/WKWebView application.

## Included

- ROZZA web interface, queue, favorites, playlists, search, and local import
- Pure Tube JavaScript playback bridge
- Native `AVAudioSession` playback setup
- Lock Screen and Control Center metadata/transport bridge
- `UIBackgroundModes = audio`
- New ROZZA icon and launch screen
- No ad, Firebase, Facebook, TikTok, or Pangle SDKs

## Generate the Xcode project on a Mac

```bash
brew install xcodegen
cd ios
xcodegen generate
open ROZZA.xcodeproj
```

Select your Apple Development team, confirm the bundle identifier, then run on a physical iPhone. YouTube background behavior must be tested on-device; the Simulator is not sufficient for validating screen-lock audio.

## Unsigned IPA

The repository workflow `.github/workflows/ios-ipa.yml` builds an unsigned IPA on a GitHub macOS runner. Sideloadly or AltStore must sign it before installation.

## Files that control playback

- `Sources/RozzaWebViewController.swift`
- `Resources/rozza2.html`
- `Resources/yt_video_play_messenger.js`
- `Config/Info.plist`
