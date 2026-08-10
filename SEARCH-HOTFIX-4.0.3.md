# ROZZA 4.0.3 — Search/Load Reliability Hotfix (Build 23)

## Why this build exists
Build 22 could open normally but return no songs because discovery/search depended on a stale pool of public Piped/Invidious instances. Saved high-scoring dead mirrors could survive upgrades, Piped health checks incorrectly parsed plain-text health responses as JSON, and one bad 5-node race could fail the whole search.

## Fixes
- Reset/migrate the persisted mirror pool once with `MIRROR_POOL_VERSION = 3`.
- Prioritize current CORS-capable Piped instances so WKWebView can query them directly.
- Use `/healthcheck` for Piped and treat any successful HTTP response as healthy instead of forcing JSON parsing.
- Remove the forced Invidious slot from every search race; Invidious is fallback-only unless it proves healthy.
- Add a second disjoint search wave after a registry refresh before declaring search unavailable.
- If Piped `music_songs` returns empty/rejected, retry the same query with `filter=all`.
- Keep the Build 22 background playback state-handoff fix intact.

## Not changed
- YouTube iframe playback state machine
- `yt_background_bridge.js`
- `DJPlaybackController.swift`
- `ROZZAWebAppView.swift`
- `ROZZAAudioSession.swift`

## Device acceptance
1. Fresh launch -> search a common artist -> results appear.
2. Tap a result -> YouTube iframe loads.
3. Tap a search suggestion -> first result starts.
4. Search 5 different queries in succession.
5. Play -> Home/Lock background behavior still works as Build 22 intended.
