# ROZZA 4.0.3 LOAD HOTFIX — QA

## Static checks
- Main inline JavaScript: `node --check` PASS
- All root Swift source files: `swiftc -parse` PASS
- HTML structural QA: PASS (165 IDs, 0 duplicates)
- Production debug UI: gated
- Version: 4.0.3
- Build: 23
- App icon source: 1024x1024 RGB

## Runtime smoke tests
A headless 390x844 iPhone-size browser was run with deterministic mocked metadata endpoints.

- boot JS page errors: 0
- search returns normalized track: PASS
- search result click -> current YouTube track: PASS
- YouTube iframe creation: PASS
- Smart Queue does NOT launch during initial player startup: PASS

## Native-network transport test
The browser network was deliberately blocked and a mock `window.webkit.messageHandlers.networkProxy` was used to emulate the iOS URLSession bridge.

- native bridge detected: PASS
- search JSON delivered through native bridge: PASS
- result normalized/rendered: PASS
- result click sets current YouTube track: PASS
- JS page errors: 0

## Regression protection
- Build 22 background playback intent handoff retained.
- Existing `yt_background_bridge.js` retained.
- Legacy foreground YouTube messenger remains disabled in active ROZZA WebView.
- Build script verifies packaged HTML contains NativeNetwork and native binary contains `networkProxy`.
- One-time mirror-cache network epoch reset added for Build 23.

## Device-only checks still required
Only a physical iPhone can validate real WKWebView / YouTube / iOS lifecycle behavior:
1. Search real song on Wi-Fi.
2. Tap result and confirm YouTube starts.
3. Search on cellular.
4. Tap suggestion and confirm instant playback.
5. Home background test.
6. Side-button lock test.
7. Control Center play/pause.
