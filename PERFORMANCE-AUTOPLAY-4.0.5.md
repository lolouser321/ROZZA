ROZZA 4.0.5 — PERFORMANCE + AUTOPLAY HOTFIX (Build 25)

Primary fixes
- Reuses one persistent YouTube iframe across songs.
- Uses loadVideoById/cueVideoById for track changes instead of creating a new iframe.
- Automatic Next now gets bounded play nudges and skips an unstartable track instead of waiting forever.
- Background resume now sends a direct pulse to the iframe-side video bridge even when outer YouTube state is stale.
- Background transition recovery budget increased only for the short Home/lock transition; no permanent timer loop.
- Native background resume transition window expanded to 4.8 seconds with bounded scheduled attempts.

Performance
- YouTube status polling reduced from 700 ms / 4 commands to a lighter 1 s cadence with duration/volume sampled less often.
- Lock Screen/native position updates throttled to 2.5 seconds.
- MediaSession position updates throttled to 1 second.
- DJ debug polling now runs only while the debug DJ UI is presented.
- Expensive product-memory rendering moved to idle/debounced work.
- Visualizer reduced from 40 bars / ~30 FPS to 28 bars / ~20 FPS.
- Startup no longer fires registry discovery + 5 health checks + recommendations all at once.
- Search first wave reduced to the three best sources; expands only on failure.
- Piped warmup now validates a real JSON API endpoint instead of `/`.

Important
- No second foreground YouTube controller was re-enabled.
- yt_video_play_messenger.js remains disabled for foreground playback.
- Background bridge remains background-only.
