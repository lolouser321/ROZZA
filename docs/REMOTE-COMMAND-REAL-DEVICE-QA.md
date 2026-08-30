# ROZZA system-command real-device QA

Source tests cannot prove delivery from iOS hardware. Capture Xcode device logs for each matrix row before calling the fix verified.

## Required matrix

Test Play, Pause, Toggle, Next, and Previous from:

- Lock Screen
- Control Center
- AirPods or Bluetooth headset
- Car/steering-wheel controls
- Siri media command

For Pause, leave the device locked for at least 15 seconds and confirm no foreground recovery, background recovery, watchdog, or delayed callback restarts audio. Then press explicit Play and confirm it resumes.

For Next/Previous, confirm exactly one queue-index transition and one autoplay for every physical press.

## Required log envelope

Filter the device console for `[ROZZA REMOTE]`. Every received command must include:

```text
sourceChannel commandID queueIndexBefore queueIndexAfter videoId
wantPlay humanPauseActive accepted rejectionReason
```

Duplicate deliveries must show `accepted=false` and a `duplicate-of-...` rejection before any queue or intent mutation.
