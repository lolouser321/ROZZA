# ROZZA 4.0.1 GOLD — Build 21 QA hardening

Fixes made during the final pre-device audit:
- Flow no longer remains falsely LIVE when its search/build fails.
- Radio no longer remains falsely LIVE when no related tracks can be added.
- Event emergency backup no longer duplicates a track already present in the event queue.
- Expired Sleep Timer persistence is cleaned on boot.
- Native DJ test launcher is DEBUG-only and cannot overlay the Release UI.
- High-value iPhone touch targets were enlarged.
- Root XcodeGen test-source path casing corrected (`tests`).
- Build pipeline now runs `Scripts/qa-source.py` before XcodeGen/Xcode build.

Automated non-device checks must pass before packaging:
- inline JavaScript syntax
- background bridge JavaScript syntax
- legacy messenger JavaScript syntax
- all Swift files parse
- shell scripts parse
- duplicate HTML IDs = 0
- required UI IDs present
- version/build markers correct
- production HTML DEBUG=false
- app icon/launch asset JSON and image files present

Physical-iPhone-only validation remains necessary for WebKit/iOS behaviors:
- YouTube Home/Lock automatic continuation
- Control Center / Lock Screen commands
- Bluetooth/AirPods route changes
- real YouTube autoplay gesture behavior
- long-session thermal/memory behavior
