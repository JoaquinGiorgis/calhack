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

Software ready; installation and physical validation pending. The design changes
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
- The iPhone remains unavailable in CoreDevice and there is no wristband USB
  port. Neither new design has been installed on physical hardware this pass.
  Physical direction/calibration quality remains unresolved from earlier work.

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
