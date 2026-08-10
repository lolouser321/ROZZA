# ROZZA 3.2 — BRAIN + RADIO (Build 15)

## Added
- ROZZA Brain taste model from real play, skip, completion and favorite behavior
- Explainable recommendation scoring
- Home For You recommendations
- Start Radio from current song/artist
- More Like This / Less Like This controls in Now Playing
- Smart Queue ranking + visible reasons for automatic additions
- Listening insights (plays, listening time, likes, artists)
- Saved Sets playlist foundation (save and replay a queue)
- Richer ROZZA Live ambient atmosphere driven deterministically by current track
- Brain on/off setting

## Protected
- Existing YouTube foreground state machine
- Background bridge
- AVAudioSession / Lock Screen integration
- Persistent WKWebView

## Physical iPhone QA
1. Foreground YouTube 3+ minutes.
2. Home and lock-screen background playback.
3. Start Radio and let Smart Queue replenish.
4. More Like This / Less Like This must not interrupt Play/Pause intent.
5. Save current queue, clear/change queue, replay Saved Set.
