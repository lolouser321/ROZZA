# ROZZA

ROZZA is an iOS music app built from the checked-in `rozza2.html` experience and hosted by a small native SwiftUI/WKWebView shell. The bundled interface is the source of truth for layout and playback behavior.

## iOS app

Requirements: macOS, Xcode 16 or newer, and XcodeGen.

```bash
xcodegen generate
open ROZZA.xcodeproj
```

The shipped interface does not connect to localhost or require the TypeScript backend. It performs Piped/Invidious mirror discovery and uses the visible official YouTube embedded player defined in `rozza2.html`. Direct audio and imported local files use its HTML audio player. YouTube remains subject to embedded-player foreground restrictions.

## Backend

```bash
cd backend
npm ci
cp .env.example .env
npm run dev
```

The optional backend remains for later native/API integrations, but it is not required by this build. Never add provider credentials to the iOS app or Git. See `README-CI.md` for simulator and device builds.

The app icon is the ROZZA neon `R` waveform mark in `Resources/Assets.xcassets/AppIcon.appiconset`. GitHub Actions publishes both a simulator artifact and an unsigned hardware IPA; the unsigned IPA still requires re-signing before installation on iOS.
