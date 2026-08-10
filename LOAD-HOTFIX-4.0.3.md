# ROZZA 4.0.3 — LOAD HOTFIX · Build 23

Purpose: fix the regression where search/results/YouTube appear not to load on the physical iPhone.

## Changes
- Added a native HTTPS URLSession bridge (`networkProxy`) for search/discovery JSON so WKWebView CORS failures do not make healthy metadata sources look offline.
- Kept the existing browser fetch + gateway path as fallback.
- Search now tries mirrors in two bounded waves instead of gambling on one random group of five.
- Mirror selection is best-first using recent success, score, failure count, and latency while preserving Piped/Invidious diversity.
- Added a currently API-capable Invidious seed while retaining dynamic registry discovery.
- Increased suggestion/video-lookup source diversity.
- Removed the Smart Queue network burst 700 ms after selecting a song; Smart Queue now waits until playback is confirmed and stable for 5 seconds.
- Delayed automatic Brain recommendation refresh at boot to reduce competition with the first user search/player load.
- Preserved Build 22 foreground -> native background intent handoff and background bridge.

## Why
The app logic passes a mocked end-to-end search -> result -> YouTube iframe creation test. The fragile part is the live metadata transport: public APIs can be reachable while WKWebView fetch is rejected by CORS/proxy behavior, and the previous search raced only a small random subset. Build 23 makes iOS use URLSession directly as the primary metadata transport and only falls back to browser/gateway transport.
