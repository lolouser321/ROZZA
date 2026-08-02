# ROZZA iOS — start here

The complete native iOS wrapper is in [`ios/`](ios/README.md).

It contains the existing ROZZA interface plus:

- native WKWebView hosting
- the supplied Pure Tube JavaScript bridge
- `AVAudioSession` playback mode
- `UIBackgroundModes = audio`
- Lock Screen and Control Center commands and metadata
- a new original ROZZA icon and launch screen
- an unsigned-IPA GitHub Actions workflow

The original compiled Pure Tube executable is not linked or shipped. A complete iOS app executable cannot be reused as a framework; its observed behavior is mapped in [`ios/PURE_TUBE_MAPPING.md`](ios/PURE_TUBE_MAPPING.md).

Use a Mac with Xcode or run `.github/workflows/ios-ipa.yml` on GitHub. Background YouTube behavior must be verified on a physical iPhone after each iOS/YouTube update.
