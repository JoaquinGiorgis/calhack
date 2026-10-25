# Apple SoundAnalysis: small public-file check

Executed on Version 26.5.1 (Build 25F80). `SNClassifierIdentifier.version1`, one-second windows, 50% overlap. No microphone or device was used.

Fourteen deterministic ESC-50 clips (7 dataset classes / 6 alert categories), 126 complete windows. The expected category was selected at least once in 13 clips; one car-horn clip produced no alert. This is a descriptive result for these clips, not a general accuracy estimate.

| ESC-50 class | File | Expected alert | Highest expected-alias score | Alias | Production selected events | Other category above threshold |
|---|---|---|---:|---|---|---|
| glass_breaking | `1-20133-A-39.wav` | GLASS | 0.9846 | `glass_breaking` | GLASS | None |
| glass_breaking | `1-84536-A-39.wav` | GLASS | 1.0000 | `glass_breaking` | GLASS | None |
| car_horn | `1-17124-A-43.wav` | CAR_HORN | 0.5267 | `car_horn` | None | None |
| car_horn | `1-19026-A-43.wav` | CAR_HORN | 0.9912 | `air_horn` | CAR_HORN | None |
| siren | `1-31482-A-42.wav` | ALARM | 0.8204 | `police_siren` | ALARM | None |
| siren | `1-54084-A-42.wav` | ALARM | 0.9955 | `civil_defense_siren` | ALARM | None |
| clock_alarm | `1-13613-A-37.wav` | ALARM | 0.9306 | `smoke_detector` | ALARM | PHONE |
| clock_alarm | `1-14262-A-37.wav` | ALARM | 0.9967 | `alarm_clock` | ALARM | None |
| crying_baby | `1-187207-A-20.wav` | BABY | 0.9531 | `baby_crying` | BABY | None |
| crying_baby | `1-211527-A-20.wav` | BABY | 0.9911 | `baby_crying` | BABY | None |
| door_wood_knock | `1-101336-A-30.wav` | KNOCK | 0.9997 | `knock` | KNOCK | None |
| door_wood_knock | `1-103995-A-30.wav` | KNOCK | 0.9981 | `knock` | KNOCK | None |
| dog | `1-100032-A-0.wav` | DOG | 0.9561 | `dog_bark` | DOG | None |
| dog | `1-110389-A-0.wav` | DOG | 0.9799 | `dog_bark` | DOG | None |

Observations: `1-17124-A-43.wav` peaked at car_horn 0.5267 (below 0.65), while duck_quack scored 0.6724 in its principal window. In the final window of `1-13613-A-37.wav`, telephone_bell_ringing scored 0.9432 and alarm_clock 0.8869; ALARM won because its priority is higher. These are concrete ambiguity/miss examples; thresholds were not changed.

All 22 configured aliases exist among the 303 classifications on this host. No nonexpected alert was selected in these 14 positive clips, but there is no negative-class set and no false-positive-rate claim. SHOUT, DOORBELL, PHONE and SPEECH have no dedicated ESC-50 classes in this subset/dataset.

Provenance: https://github.com/karolpiczak/ESC-50 at commit `33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6`. Audio download total 6174616 bytes. The first two lexicographic filenames per class were chosen before inference, with distinct original source IDs. `manifest.json` records source URLs, SHA-256 hashes and individual attributions. ESC-50 is CC BY-NC; the ESC-10 subset is CC BY. Full metadata/license are saved alongside this report. No fixtures enter the app or repository.

Limitations: macOS file inference does not exercise the iPhone microphone/FOA path or establish model equivalence across OS versions. No gain normalization, source playback, BLE, live result expiry, angular accuracy or tactile distinguishability was evaluated. Model training overlap with public ESC-50/Freesound is unknown. Timings in JSON cover analyzer.analyze(), not request/model initialization.

Reproduction:
```sh
swiftc -O SoundEvents.swift SpatialDirection.swift main.swift -o evaluate
./evaluate
```

The production source snapshots are unchanged; hashes are in `production-source-sha256.txt`. Full per-window scores (category scores and top five labels), selected events and RMS values are in `results.json`.
