# FortWatch screen and orbit redesign

## Brief and visual audit

The user requests a better device screen and sound circle, matching their
FortWatch website. Preserve the existing brand, English UI, full sound catalog,
Bluetooth behavior and explicit uncertainty. The audience needs to identify a
sound and its direction at a glance.

The previous phone layout made the circle only 120 pt, with a 67 pt visible ring,
then repeated direction in a dominant lime rectangle. Category-filled cards
obscured the brand photograph and made each sound feel like a different app.
The wristband also used large saturated fields and a small supporting direction.

Design read: accessible native device UI, preserving FortWatch's photographic,
smoke-glass identity. DESIGN_VARIANCE 4, MOTION_INTENSITY 1, VISUAL_DENSITY 4.
Marketing-specific layout and package instructions do not apply to SwiftUI or
the embedded display. No new web framework or imitation platform components.

## Tokens and composition

- Graphite `#12141F`, smoke `#1E2130`, off-white `#F5F7FA`, muted `#CCD0D8`,
  lime `#8FD63D`. Existing category colors stay on the sound glyph.
- iPhone: bundled Gabarito for names, Atkinson Hyperlegible Next for supporting
  copy. Wristband uses native glyph atlases within its actual memory limits.
- Signature: one large neutral orbit and a lime tapered bearing crescent around
  a fixed phone reference. The phone puts its category-colored glyph on the ring;
  the wristband keeps a compact category glyph beside the sound name. No decorative
  rotation or scanning animation, no invented confidence/precision.
- Phone: status, sound name, orbit, one direction label, one rhythm explanation.
  Calibration and input level are secondary. Text can grow outside the orbit.
- Wristband: compact brand header; orbit left, specific name right; direction
  and rhythm below. Its 320 by 240 display prioritizes legibility over a photo.

## Desk critique decisions

Remove the duplicate direction block and duplicate rhythm legend. Do not simply
enlarge the old canvas while retaining a tiny ring. Keep the center explicitly
relative to the phone. Use enough neutral scrim for contrast on the photo.
Unknown, expired, calibration and test states must remove bearing graphics rather
than placing a sound at zero degrees. Keep accessibility text outside fixed
geometry and preserve all existing state and freshness guards.

## Verification

Software installed; physical sound/direction validation pending. The design changes
do not alter the model, BLE contract, pulse arrays or analytics compatibility.

- iOS full suite: 69 tests passed (66 production tests plus three opt-in visual
  export tests). After correcting the largest-text calibration button, the three
  visual exports passed again and the signed iPhone build passed.
- Actual Simulator home inspected: header, connection, library and bottom action
  remain visible. Shared production card renders cover 320 pt width, long names,
  recent/unknown/calibration states and accessibility5 text. The largest button
  now stacks its icon and wraps at words. Manual VoiceOver remains pending.
- Firmware: 521 complete titles fit (476 at Gabarito 32 px, 45 at 20 px).
  Host rendering checked 1,956 frames with ASan/UBSan, including 361 angle inputs;
  unknown/test/quiet/recent states have no bearing. These test drawing geometry,
  not microphone accuracy. D/E/P lifecycle, haptic and dashboard contracts pass.
- PlatformIO build passed: RAM 84,108 bytes; flash 3,712,625 bytes.
- The interactive preview compares **Orbit** and **Focus**. Orbit informs the
  native implementation; Focus is an alternative mockup, not a shipped app mode.
  Both preview variants use simulated inputs.
- On the following user-requested installation pass, both devices became available.
  The signed app installed and launched successfully; CoreDevice confirmed its
  process remained running. ESP32-S3 app0 was written and its hash verified, then
  the board rebooted and advertised the FortWatch BLE service. Physical screen,
  microphone, motor and direction/calibration checks remain pending.

### Device installation — 25 October 2026

Revision `1e782dc`. Current partition table matched the build before writing
3,712,992 bytes only at app0 (`0x10000`). No NVS, partition table or credential
file was changed. Dashboard configuration is preserved; this pass did not test
an actual dashboard upload. No synthetic alert was sent as a real detection.

- Firmware SHA-256: `9b3edd3baeebaa095c6d2a150fa88b639feca90c9be400a952ee3eb33a2331ab`.
- iPhone executable SHA-256: `c0e823f2a62f97deb66607a0e25e86aafa72d6acc14d48d187cf77e7b1e8baa7`.
- Installation evidence: `/tmp/fortwatch-orbit-install.json`,
  `/tmp/fortwatch-orbit-launch.json`, `/tmp/fortwatch-orbit-processes.json`,
  `/tmp/fortwatch-orbit-partition-read.log`, `/tmp/fortwatch-orbit-flash.log`.
- BLE scan detected the actual FortWatch advertisement after reboot. Opening the
  serial port later yielded no startup messages; no boot-log claim is made.

## Evidence

[iPhone card](ios/orbit-cat.png), [narrow layout](ios/orbit-narrow.png),
[calibration state](ios/orbit-calibration.png), [largest text](ios/orbit-largest-text.png),
[recent state](ios/orbit-recent.png), [long name](ios/orbit-long-name.png).
These are simulated states rendered with production SwiftUI views.

[Wristband catalog](wristband-orbit-catalog.png),
[wristband states](wristband-orbit-states.png) and
[legacy compatibility](wristband-orbit-legacy.png) are software renders of actual
firmware drawing functions, not photographs of the physical screen.

Logs: `/tmp/fortwatch-orbit-ios-tests.log`, `/tmp/fortwatch-orbit-final-renders.log`,
`/tmp/fortwatch-orbit-iphone-build.log`, `/tmp/fortwatch-orbit-firmware-build.log`.
Reproduce embedded previews with
`python3 live_demo/tests/test_alert_render.py --output /tmp/fortwatch-brand-preview`.
