# ROZZA

ROZZA is the native SwiftUI iOS music app and its TypeScript service backend. This repository contains the complete current ROZZA UI, global playback manager, search, library, AI and recognition integrations—not an HTML shell.

## iOS app

Requirements: macOS, Xcode 16 or newer, and XcodeGen.

```bash
xcodegen generate
open ROZZA.xcodeproj
```

Local builds default to `http://127.0.0.1:3001`. Set the GitHub repository variable `ROZZA_API_BASE_URL` to the deployed HTTPS backend URL before making a device build. YouTube content uses a visible official embedded player and remains foreground-only. Local and authorized native audio uses AVPlayer and supports background audio, Lock Screen, Control Center, Bluetooth, and AirPlay.

## Backend

```bash
cd backend
npm ci
cp .env.example .env
npm run dev
```

Provider credentials stay on the backend. Never add them to the iOS app or Git. See `backend/.env.example` for the complete configuration and `README-CI.md` for simulator and signed-device builds.
