# ROZZA Flutter

This is the native-audio replacement for the legacy WKWebView iOS shell.

```powershell
$env:Path += ";C:\Users\kokon\develop\flutter\bin"
flutter run
```

Without configuration, search uses Audius public, authorized HTTPS streams
directly. To add the complete backend catalog, build with:

```powershell
flutter run --dart-define=ROZZA_API_BASE_URL=https://your-backend.example
```

The app uses `just_audio` (iOS AVPlayer) through `audio_service`. Pause,
previous, next, seek, Lock Screen, Control Center, AirPods, and background
playback therefore operate on a native audio queue. YouTube is intentionally
not sent to the native audio service and remains foreground-only.
