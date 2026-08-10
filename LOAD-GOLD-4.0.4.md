# ROZZA 4.0.4 — LOAD GOLD · Build 24

This build supersedes the earlier 4.0.3 search-only IPA.

- Keeps the Build 22 background playback intent hotfix.
- Uses the native iOS URLSession `networkProxy` for metadata search before browser/CORS fallbacks.
- Refreshes the static Piped seed roster to the current TeamPiped uptime configuration, excluding a node currently documented down.
- Adds `MIRROR_POOL_VERSION = 4` so stale mirror scores from older builds do not survive this source migration.
- Keeps bounded two-wave failover and dynamic registry discovery.
- Does not change the YouTube foreground/background playback bridge.
