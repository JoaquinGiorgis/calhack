# iPhone sound recognition audit

25 October 2026. This describes the native iPhone pipeline, not the Mac's YAMNet
configuration. The catalog contains **10 alert categories and 22 Apple
classification identifiers**. A complete mapping is not evidence that real
sounds are reliably distinguished.

## Catalog and selection rules

The identifiers below are the exact strings consumed by
[SoundEventSelector](../ios/FortWatchListener/SoundEvents.swift).

| Alert | Apple identifiers | Threshold | Priority | Required windows | Cooldown |
|---|---|---:|---:|---|---|
| ALARM | `alarm_clock`, `siren`, `civil_defense_siren`, `smoke_detector`, `police_siren`, `ambulance_siren`, `fire_engine_siren` | 0.65 | 3 | Current hit | 2 s |
| CAR_HORN | `car_horn`, `air_horn` | 0.65 | 3 | Current hit | 2 s |
| GLASS | `glass_breaking` | 0.65 | 3 | Current hit | 2 s |
| SHOUT | `shout`, `yell`, `children_shouting`, `screaming` | 0.70 | 3 | Current hit | 2 s |
| BABY | `baby_crying` | 0.65 | 2 | Current hit | 2 s |
| KNOCK | `knock` | 0.65 | 2 | Current hit | 2 s |
| DOORBELL | `door_bell` | 0.65 | 2 | Current hit | 2 s |
| PHONE | `telephone_bell_ringing`, `ringtone` | 0.65 | 2 | Current hit | 2 s |
| DOG | `dog_bark`, `dog_bow_wow` | 0.65 | 1 | Current hit | 2 s |
| SPEECH | `speech` | 0.75 | 0 | 3 of the last 4, including the current window | 15 s |

A category uses the largest score among its aliases. Exactly one eligible
category wins each window: highest priority, then highest score divided by its
threshold, then alphabetical event name. Only the winner starts its cooldown;
a different category can appear in the next window. Cooldowns use audio-window
time. Invalid scores and repeated or out-of-order window times cannot alert.
These thresholds are provisional settings, not measured accuracy guarantees.

## What actually runs

[SpatialCapture](../ios/FortWatchListener/SpatialCapture.swift) feeds the FOA W
channel to Apple's built-in SoundAnalysis `.version1` classifier on the phone.
It requests one-second windows with 50% overlap and checks that the installed
classifier supports every configured identifier. Missing identifiers stop
startup with an explicit error. Windows below W RMS 0.0001 provide no category
hits. Results arriving after their capture-end time plus 750 ms are discarded.

**Classification pauses during front calibration.** The calibration branch
returns before submitting audio for classification, and callbacks from the old
analysis generation are rejected. It resumes with fresh history after success
or timeout. Before calibration, or after calibration fails, sound recognition
still works but direction remains unknown. Restarting analysis clears cooldown
and hit history.

## Limits that matter

- The app does not transcribe speech, recognize the word “Fortnite,” identify a
  person or animal, or determine why someone shouts. Category names describe
  acoustic classes; priority does not prove danger.
- There is no source separation or multi-source tracking. With overlapping
  sounds, one category wins. A direction, when available, describes the dominant
  FOA field in the same audio window; it is not proven to belong to that category.
- The iPhone has no special knock-versus-glass veto. That heuristic exists in
  the Mac pipeline and cannot be assumed here. Similar impacts, alarm/ringtone
  overlap, reverberation, distance, recordings, and competing speech can produce
  confusion or missed alerts. No per-category physical confusion matrix exists.
- Each category has a distinct learned rhythm in
  [SoundHaptics](../ios/FortWatchListener/SoundHaptics.swift). One motor conveys
  category through timing, not physical left/right direction. Distinct timing
  patterns do not establish that people can reliably distinguish them.
- The wristband can suppress SPEECH locally. A successful Bluetooth write does
  not confirm that its motor played a pattern.

## Verification boundary

[SoundCatalogTests](../ios/Tests/SoundCatalogTests.swift) checks catalog/selector/
haptic coverage, every alias with an isolated selector, unique visible
identities, and text/signal color contrast. The installed Apple classifier's
identifier list is checked directly without microphone access. Synthetic scores
verify mapping and policy only; they do not measure acoustic recognition.

The integrated iOS suite passed 47 tests on iPhone 17 Pro / iOS 26.5 Simulator.
Signed iPhone build and installation passed. The generated catalog fixtures
were inspected for all ten categories; they are synthetic UI states. Physical
recognition accuracy, tactile distinguishability, and angular accuracy remain
separate validation work. Do not tune thresholds from catalog-test results.

## Actual public-audio check on macOS

On 25 October 2026, Apple's real `.version1` classifier ran on **14 ESC-50
recordings**, with one-second windows and 50% overlap: 126 complete windows.
The harness compiled unchanged copies of production `SoundEvents.swift` and
`SpatialDirection.swift`; category selection used the real thresholds, RMS
gate, priorities, speech history and cooldowns, with a fresh selector per clip.
The host was macOS 26.5.1 (25F80), with 303 available classifier identifiers and
**zero missing configured aliases**. No microphone was accessed.

Two clips per available dataset class were selected before inference: the first
two filenames in lexicographic order with distinct original source IDs. This
covers seven dataset classes and six alert categories; siren and clock alarm
both map to ALARM. Files and labels came from the official
[ESC-50 metadata at the pinned commit](https://github.com/karolpiczak/ESC-50/blob/33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6/meta/esc50.csv).

| File | Expected alert | Highest score among its configured aliases | Highest-scoring alias | Alerts actually selected in the clip |
|---|---|---:|---|---|
| `1-20133-A-39.wav` | GLASS | 0.9846 | `glass_breaking` | GLASS |
| `1-84536-A-39.wav` | GLASS | 1.0000 | `glass_breaking` | GLASS |
| `1-17124-A-43.wav` | CAR_HORN | 0.5267 | `car_horn` | None |
| `1-19026-A-43.wav` | CAR_HORN | 0.9912 | `air_horn` | CAR_HORN |
| `1-31482-A-42.wav` | ALARM | 0.8204 | `police_siren` | ALARM |
| `1-54084-A-42.wav` | ALARM | 0.9955 | `civil_defense_siren` | ALARM |
| `1-13613-A-37.wav` | ALARM | 0.9306 | `smoke_detector` | ALARM |
| `1-14262-A-37.wav` | ALARM | 0.9967 | `alarm_clock` | ALARM |
| `1-187207-A-20.wav` | BABY | 0.9531 | `baby_crying` | BABY |
| `1-211527-A-20.wav` | BABY | 0.9911 | `baby_crying` | BABY |
| `1-101336-A-30.wav` | KNOCK | 0.9997 | `knock` | KNOCK |
| `1-103995-A-30.wav` | KNOCK | 0.9981 | `knock` | KNOCK |
| `1-100032-A-0.wav` | DOG | 0.9561 | `dog_bark` | DOG |
| `1-110389-A-0.wav` | DOG | 0.9799 | `dog_bark` | DOG |

The expected category was selected at least once in **13 of these 14 clips**.
This count is not a general accuracy estimate. The missed horn's principal
window scored `duck_quack` at 0.6724 and `car_horn` at 0.5267, below the 0.65
alert threshold. The clock recording `1-13613-A-37.wav` also exceeded PHONE's
threshold: its final window scored `telephone_bell_ringing` at 0.9432 and
`alarm_clock` at 0.8869. ALARM won that window because its priority is higher.
PHONE was the only nonexpected category to exceed its threshold; no nonexpected
alert was selected. Thresholds were not changed.

**Limits:** this is file inference on a Mac, not the iPhone microphone, FOA
capture, speaker playback or a live-room test. It does not establish model
equivalence across OS versions. The sample is small, contains no negative-class
set, and supplies no false-positive-rate estimate. SHOUT, DOORBELL, PHONE and
SPEECH have no dedicated ESC-50 classes. Possible classifier training overlap
with public ESC-50/Freesound recordings is unknown. Live alert expiry, Bluetooth,
angles and tactile recognition were not exercised.

Evidence is in `/tmp/fortwatch-sound-benchmark/`: `results.json` contains all
per-window category scores, top-five labels, RMS and selected events;
`REPORT.md`, `main.swift`, `build.log`, `run.log` and production-source SHA-256
hashes preserve the method. `manifest.json` records exact source URLs, hashes
and per-clip attributions. Audio downloads totaled **6,174,616 bytes** and remain
temporary, outside the app and repository. The dataset's
[license and individual attributions](https://github.com/karolpiczak/ESC-50/blob/33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6/LICENSE)
are retained alongside the files; ESC-50 is CC BY-NC and its ESC-10 subset is CC
BY. No live audio was recorded and no production code was changed.

Numerical results and public-source provenance are retained in [validation/sound-recognition](validation/sound-recognition/REPORT.md); no audio is bundled.
