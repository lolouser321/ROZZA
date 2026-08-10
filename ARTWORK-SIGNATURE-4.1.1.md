# ROZZA 4.1.1 — ARTWORK SIGNATURE · Build 27

## Now Playing artwork fix

- YouTube playback remains mounted in the established persistent iframe.
- The user-facing Now Playing video area now shows the current track artwork instead of YouTube embed/error chrome.
- ROZZA adds a subtle branded waveform + ROZZA signature on the artwork.
- Direct/local artwork panels receive the same signature treatment.
- The overlay is visual-only (`pointer-events:none`) and does not create another playback engine.
- When Now Playing closes, the artwork cover is removed and the existing playback host returns to its established keep-alive position.
