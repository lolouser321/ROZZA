# ROZZA

ROZZA is an iOS music app built from the checked-in `rozza2.html` experience and hosted by a native SwiftUI/WKWebView shell. The bundled interface is the source of truth for layout and playback behavior.

## iOS app

Requirements: macOS, Xcode 16 or newer, and XcodeGen.

```bash
xcodegen generate
open ROZZA.xcodeproj
```

The shipped interface does not connect to localhost or require the TypeScript backend. It performs Piped/Invidious mirror discovery and uses the visible official YouTube embedded player defined in `rozza2.html`. The supplied `yt_video_play_messenger.js` is bundled and injected into YouTube frames, while native Swift handles its play/pause/state callbacks. Direct audio and imported local files use the HTML audio player. Background behavior for embedded YouTube media remains subject to WebKit, YouTube, and iOS policy restrictions.

## Backend

```bash
cd backend
npm ci
cp .env.example .env
npm run dev
```

The optional backend remains for later native/API integrations, but it is not required by this build. Never add provider credentials to the iOS app or Git. See `README-CI.md` for simulator and device builds.

The app icon is the opaque 1024px ROZZA neon rose/audio mark in `Resources/Assets.xcassets/AppIcon.appiconset`, and matching artwork appears on launch. GitHub Actions publishes both a simulator artifact and an unsigned hardware IPA; the unsigned IPA still requires re-signing before installation on iOS. See `BUILD-IPA.md` for the shortest build path.
