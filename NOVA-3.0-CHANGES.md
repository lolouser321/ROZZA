# ROZZA 3.0 NOVA — Build 13

This build is a product-level UI/UX overhaul plus targeted playback-transition fixes. It intentionally preserves the existing single YouTube foreground state machine and the background-only iframe bridge.

## Product redesign
- Removed fake phone/notch/status-bar/ticker chrome from the actual iPhone experience.
- Switched to native iOS system typography (no remote font CSS on startup).
- Rebuilt Home around one-tap discovery, quick moods, a cinematic current-track card, and real transport controls.
- Rebuilt Search with instant local suggestions, faster cached remote suggestions, explicit Play affordances, and tap-to-play behavior.
- Search suggestion tap now plays the first matching song automatically; it no longer requires manually adding the result to the queue first.
- Top suggestions are lightly prefetched so a tap can often create the YouTube player in the original user-gesture stack, improving audible autoplay reliability.
- Search-result row tap plays immediately; the + button remains queue-only.
- Rebuilt Now Playing around artwork/video, metadata, progress, transport, queue, shuffle/repeat, and volume—removed the old turntable/vinyl visual metaphor.
- Rebuilt the mini player as a floating native-style transport above a floating tab bar.
- Rebuilt Library and Settings into native-style grouped surfaces.
- Added subtle native iPhone haptic feedback through a WKScriptMessage bridge.
- Dynamic artwork now drives Home and Now Playing visual atmosphere.

## Faster feel
- Removed remote Fontsource CSS requests; native system typography renders immediately.
- Added short-lived search and suggestion caches.
- Recent/local suggestions render immediately before remote suggestions return.
- Prefetches only the top few suggestion tracks, not every suggestion.
- Result rows use content-visibility for cheaper long-list rendering.
- Visualizer is throttled to ~30fps.
- Ambient particle loop backs off aggressively when disabled; particles default off for new installs.
- Production DEBUG UI is off.

## YouTube autoplay improvements
- WKWebView already allows inline autoplay; this build keeps that setting intact.
- Suggestion tap activates the native audio session immediately.
- When a prefetched track exists, the iframe/load call occurs synchronously from the suggestion tap.
- If a YouTube embed still lands CUED/UNSTARTED after an async search, ROZZA makes one proactive play request before showing the manual-tap fallback.

## Home / lock automatic resume improvement
The previous build proved background playback could continue after manually pressing Play in Control Center. NOVA automates that same transition path:
- Captures Play intent before WebKit reports the lifecycle pause.
- Starts a short iOS background transition task.
- Arms the existing background-only YouTube bridge.
- Performs a bounded native auto-resume sequence at 0.10s / 0.42s / 0.90s only during the transition.
- Every attempt re-checks JS user intent; an explicit Pause always wins.
- The transition task ends after 1.6s or immediately when no resume is needed.
- Background video-playing callbacks update Lock Screen / Control Center playback state.
- No permanent retry timer or second foreground player was introduced.

## Version
- MARKETING_VERSION: 3.0
- CURRENT_PROJECT_VERSION: 13

## Physical iPhone acceptance test
1. Play 5 YouTube tracks in the foreground; each should remain stable.
2. Type in Search, tap a suggestion, and confirm the first matching song starts without adding it manually to the queue.
3. Press Home while a YouTube track is playing. Do not touch Control Center. Confirm audio resumes/continues automatically.
4. Lock the phone with the side button. Confirm the same behavior.
5. Explicitly Pause, then Home/lock. Confirm ROZZA does not restart playback.
6. Test Control Center Play/Pause/Next/Previous/seek.
7. Test Search, Home, Library, Queue and Now Playing for layout/interaction regressions.

## Local verification performed here
- JavaScript syntax: PASS (`node --check`)
- All root Swift sources: syntax parse PASS (`swiftc -frontend -parse`)
- No duplicate HTML IDs: PASS
- Active screens present: Home / Search / You / Settings
- `project.yml`: 3.0 / build 13
- `UIBackgroundModes`: audio remains enabled
- Build script shell syntax: PASS

A real IPA compile requires macOS + Xcode/xcodebuild and the background/autoplay behavior must be verified on a physical iPhone.
