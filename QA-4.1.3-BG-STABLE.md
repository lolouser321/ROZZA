# ROZZA 4.1.3 — BG STABLE · Build 29

## Root cause fixed
Build 28 correctly separated human Pause from automatic recovery, but it made
background transport observations depend on the native `youtubeWantsPlayback`
mirror already being true. During `willResignActive`, the iframe bridge can
recover the real video before that mirror arrives. Build 28 interpreted that
valid recovery as unwanted playback and paused it again.

## New playback contract
- Main-page Play/Pause intent is sent directly to Swift through `playbackIntent`.
- Iframe play/pause/playing events are transport observations only.
- A human/system Pause creates a hard pause fence and cancels background recovery.
- Automatic recovery can never clear that hard pause fence.
- Background `playing` is accepted unless a hard human pause is active; it no
  longer depends on a potentially stale native intent mirror.
- `backgroundPrepare()` returns the main player's current `YT.wantPlay`, and
  Swift accepts it only for the current transition generation.
- Automatic `YT.resume()` preserves intent and never generates a fresh user Play.
- Continuous Play remains enabled and auto-next behavior is preserved.
- HD artwork/signature, Drive controls, network fallback, and persistent YouTube
  player from previous builds are retained.

## Verification performed
- Source QA: PASS — 182 IDs, 0 duplicates.
- Main inline JavaScript syntax: PASS.
- Background bridge JavaScript syntax: PASS.
- Legacy messenger JavaScript syntax: PASS.
- Root Swift files: parse PASS.
- Build/resource scripts: shell syntax PASS.
- Runtime contract test:
  - human Play publishes explicit PLAY intent: PASS.
  - automatic resume publishes no new explicit PLAY intent: PASS.
  - human Pause publishes explicit PAUSE intent: PASS.
  - backgroundResumeIfWanted after human Pause: requested=false PASS.
  - backgroundPrepare after Play: true PASS.
  - backgroundResumeIfWanted after Play: requested=true PASS.
  - Continuous Play ON invokes auto-next: PASS.
  - Continuous Play OFF does not auto-next: PASS.

## Physical iPhone validation still required
Actual iOS Home/Lock WebKit timing cannot be fully reproduced in this Linux QA
environment. Build 29 specifically fixes the race found in Build 28 and adds
source guards to prevent that regression from returning.
