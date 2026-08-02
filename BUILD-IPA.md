# Build the ROZZA IPA

The project is configured as **ROZZA 1.7 (build 8)** with bundle identifier `com.rozza.app` and deployment target iOS 17.

## Easiest: GitHub Actions unsigned IPA

1. Put this folder in a GitHub repository.
2. Open **Actions → Unsigned iOS IPA → Run workflow**.
3. Download the `ROZZA-Unsigned-IPA` artifact when the job finishes.
4. Re-sign the IPA with your Apple account or signing service before installing it on a physical iPhone.

The workflow refuses to package the app unless it finds:

- the opaque 1024×1024 `AppIcon` and compiled `Assets.car`;
- the ROZZA launch artwork;
- `rozza2.html`;
- `yt_video_play_messenger.js`;
- `UIBackgroundModes = audio`;
- the display name `ROZZA`.

## One-command unsigned build on a Mac

Requirements: Xcode 16 or newer and XcodeGen.

```bash
brew install xcodegen
chmod +x Scripts/*.sh
Scripts/build-unsigned-ipa.sh
```

The result is written to `build/ROZZA-Unsigned.ipa`.

## Signed IPA

The **Signed IPA (physical iPhone)** workflow uses these GitHub secrets:

- `IOS_P12_BASE64`
- `IOS_P12_PASSWORD`
- `IOS_PROFILE_BASE64`
- `IOS_KEYCHAIN_PASSWORD`
- `IOS_TEAM_ID`
- `IOS_BUNDLE_ID`

The certificate, provisioning profile, Team ID, and bundle identifier must all match. The App ID/profile must also support any enabled capabilities, including MusicKit if that entitlement remains enabled.

## What is wired into the app

- Native SwiftUI application and persistent `WKWebView` shell.
- Official YouTube WKWebView/IFrame player already used by ROZZA.
- The supplied `yt_video_play_messenger.js`, injected into YouTube frames, with native `callbackHandler` handling for play, pause, state, and fullscreen events.
- `AVAudioSession` configured as `.playback`.
- Lock Screen and Control Center commands through `MPRemoteCommandCenter` and Now Playing metadata.
- `UIBackgroundModes` containing `audio`.

The compiled Pure Tube executable is not a build input: iOS cannot link another signed/FairPlay application executable into this app. The readable messenger behavior is integrated as a normal source resource instead.
