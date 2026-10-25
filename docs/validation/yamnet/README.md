# YAMNet production-selector replay

26 deterministic public ESC-50 clips; 234 previously computed CoreML windows. This replay executes Swift selection rules on real model outputs. It does not execute or simulate microphone capture, inference, Bluetooth or direction. No audio is stored in this directory.

## Historical baseline: notifications and visible identity coupled

`selector-results.json` records the production rules before visible identity and vibration notification were separated. `baseline-selector.swift.txt` and `selector-provenance.json` preserve the exact selector and source hashes. Do not describe this baseline as the final app behavior after a selector change.

The baseline selected a declared target-specific label in 16 of the 24 clips for which YAMNet has a matching target label. The two washing-machine clips have no exact washing-machine label in YAMNet. These tiny positive-file counts are not a general accuracy, precision or false-positive-rate estimate.

| Dataset class | File | Exact labels returned by baseline | Target-specific label returned? |
|---|---|---|---|
| glass_breaking | `1-20133-A-39.wav` | None | No |
| glass_breaking | `1-84536-A-39.wav` | Chink, clink | No |
| car_horn | `1-17124-A-43.wav` | Vehicle horn, car horn, honking | Yes |
| car_horn | `1-19026-A-43.wav` | Vehicle horn, car horn, honking | Yes |
| siren | `1-31482-A-42.wav` | Siren | Yes |
| siren | `1-54084-A-42.wav` | Civil defense siren; Music | Yes |
| clock_alarm | `1-13613-A-37.wav` | Alarm clock | Yes |
| clock_alarm | `1-14262-A-37.wav` | Alarm clock; Telephone bell ringing | Yes |
| crying_baby | `1-187207-A-20.wav` | None | No |
| crying_baby | `1-211527-A-20.wav` | Baby cry, infant cry | Yes |
| door_wood_knock | `1-101336-A-30.wav` | Knock | Yes |
| door_wood_knock | `1-103995-A-30.wav` | Knock | Yes |
| dog | `1-100032-A-0.wav` | Bow-wow | Yes |
| dog | `1-110389-A-0.wav` | Bark | Yes |
| cat | `1-34094-A-5.wav` | Baby cry, infant cry; Cat | Yes |
| cat | `1-47819-A-5.wav` | Cat | Yes |
| rain | `1-17367-A-10.wav` | Water | No |
| rain | `1-21189-A-10.wav` | Rain on surface | Yes |
| footsteps | `1-155858-A-25.wav` | Fireworks | No |
| footsteps | `1-223162-A-25.wav` | Knock | No |
| clapping | `1-104089-A-22.wav` | Clapping | Yes |
| clapping | `1-105224-A-22.wav` | Applause | Yes |
| coughing | `1-19111-A-24.wav` | None | No |
| coughing | `1-19118-A-24.wav` | None | No |
| washing_machine | `1-21896-A-35.wav` | Alarm clock; Engine | Not in vocabulary |
| washing_machine | `1-23996-A-35.wav` | Train | Not in vocabulary |

Concrete misses and mismatches:
- `1-20133-A-39.wav`: Glass peaked at 0.4746, below 0.50; no alert. In `1-84536-A-39.wav`, Chink/clink 0.5081 was selected first. Glass is suppressed when its eligible child Chink/clink is present; at 1.935 s Chink/clink 0.8201 also exceeds sibling Shatter 0.7793. The decoupled replay below confirms that removing cooldown from the visual decision still does not select Glass/Shatter. Shared cooldown is not the sole cause of this miss.
- `1-187207-A-20.wav`: Baby cry peaked at 0.1659; no alert. This is low model confidence, not an RMS-gate rejection.
- `1-17367-A-10.wav`: Water notified at 1.455 s. Later Rain 0.8801/0.8064/0.9339 windows were withheld by the shared four-second NATURE cooldown. Exact values are in the JSON.
- `1-19118-A-24.wav`: Cough peaked at 0.7814 but crossed 0.60 in only one window, below the two-of-three hit rule. The other coughing clip peaked at 0.4974.
- Potential unrelated alerts against the dataset label: Baby cry 0.5151 on cat `1-34094-A-5.wav`; Fireworks 0.9887 on footsteps `1-155858-A-25.wav`; Knock 0.6824 on footsteps `1-223162-A-25.wav`; Alarm clock 0.5750 on washing-machine `1-21896-A-35.wav`; Train 0.8012 on washing-machine `1-23996-A-35.wav`. Siren `1-54084-A-42.wav` also returned Music and clock-alarm `1-14262-A-37.wav` returned Telephone bell ringing. These are dataset-label discrepancies, not independently adjudicated annotations of every incidental sound.

## Isolated ranking comparison

`selector-dominant-results.json` replays a temporary copy that changes only the winner ordering after ancestor suppression: descending score first, priority only for an exact score tie. Thresholds, sustained-hit requirements and family cooldowns remain unchanged. No production code was edited by this experiment.

**Zero of 234 window decisions changed.** The same 16/24 target-specific clips were returned. The cat→baby and washing-machine→alarm discrepancies remained because no stronger eligible candidate displaced those labels in the affected windows. This subset demonstrates neither a gain nor a regression from score-first ordering. It does not establish that the ordering is equivalent for other inputs. `dominant-selector.swift.txt` preserves the exact temporary variant.

## Current policy: visual identity separated from notification

`selector-decoupled-results.json` records the production selector after this separation. A current eligible hit can update the visible identity immediately; sustained-hit rules and family cooldown apply only to `shouldNotify`. `decoupled-priority-selector.swift.txt` and `decoupled-provenance.json` identify the exact source used.

This policy displays a declared target-specific label in **19/24 clips** and notifies a target-specific label in **16/24 clips**. The additional visual matches are Rain (`1-17367-A-10.wav`), Walk/footsteps (`1-155858-A-25.wav`) and Cough (`1-19118-A-24.wav`). This is a count of these particular public clips, not an accuracy estimate. More immediate visual updates also expose transient competing labels, including Opera on a siren clip and Crowing on a crying-baby clip.

| Dataset class | File | Visual labels (distinct) | Notifying labels (distinct) |
|---|---|---|---|
| glass_breaking | `1-20133-A-39.wav` | Coin (dropping) | None |
| glass_breaking | `1-84536-A-39.wav` | Chink, clink | Chink, clink |
| car_horn | `1-17124-A-43.wav` | Vehicle horn, car horn, honking | Vehicle horn, car horn, honking |
| car_horn | `1-19026-A-43.wav` | Vehicle horn, car horn, honking | Vehicle horn, car horn, honking |
| siren | `1-31482-A-42.wav` | Opera; Siren; Speech | Siren |
| siren | `1-54084-A-42.wav` | Civil defense siren; Gong; Music; Siren | Civil defense siren; Music |
| clock_alarm | `1-13613-A-37.wav` | Alarm; Alarm clock | Alarm clock |
| clock_alarm | `1-14262-A-37.wav` | Alarm clock; Telephone bell ringing | Alarm clock; Telephone bell ringing |
| crying_baby | `1-187207-A-20.wav` | Crowing, cock-a-doodle-doo; Speech | None |
| crying_baby | `1-211527-A-20.wav` | Baby cry, infant cry | Baby cry, infant cry |
| door_wood_knock | `1-101336-A-30.wav` | Knock | Knock |
| door_wood_knock | `1-103995-A-30.wav` | Knock | Knock |
| dog | `1-100032-A-0.wav` | Bow-wow; Dog | Bow-wow |
| dog | `1-110389-A-0.wav` | Bark | Bark |
| cat | `1-34094-A-5.wav` | Baby cry, infant cry; Cat; Meow | Baby cry, infant cry; Cat |
| cat | `1-47819-A-5.wav` | Cat; Meow | Cat |
| rain | `1-17367-A-10.wav` | Rain; Rain on surface; Raindrop; Water; Waterfall | Waterfall |
| rain | `1-21189-A-10.wav` | Rain on surface; Stream; Waterfall | Rain on surface |
| footsteps | `1-155858-A-25.wav` | Fireworks; Walk, footsteps | Fireworks |
| footsteps | `1-223162-A-25.wav` | Knock | Knock |
| clapping | `1-104089-A-22.wav` | Clapping | Clapping |
| clapping | `1-105224-A-22.wav` | Applause | Applause |
| coughing | `1-19111-A-24.wav` | None | None |
| coughing | `1-19118-A-24.wav` | Cough | None |
| washing_machine | `1-21896-A-35.wav` | Alarm clock; Engine | Alarm clock; Engine |
| washing_machine | `1-23996-A-35.wav` | Train; Vehicle | Train |

The rain clip now displays several related labels (Rain, Rain on surface, Raindrop, Water and Waterfall); its notification changes from historical Water to Waterfall. Cat→Baby, footsteps→Fireworks/Knock and washing-machine→Alarm/Train discrepancies remain. Displaying all 521 model classes does not mean all classes are reliably recognized, and this selector does not separate simultaneous sources.

### Ranking comparison after separation

`selector-decoupled-dominant-results.json` changes only winner ordering in a temporary selector copy: highest score first after ancestor suppression, priority only for exact-score ties. `decoupled-dominant-selector.swift.txt` preserves that variant; `decoupled-comparison.json` contains the exact differences.

Both orderings retain **19/24 target visual clips and 16/24 target notification clips**. Of 234 windows, three change visible label and one additional window changes only notification timing:

| Clip and capture-end time | Production priority first | Temporary score first |
|---|---|---|
| Glass `1-84536-A-39.wav`, 1.455 s | Chink/clink 0.508; notifies | Breaking 0.881; visual only |
| Same glass clip, 1.935 s | Chink/clink 0.820; visual only | Chink/clink 0.820; notifies 480 ms later |
| Siren `1-31482-A-42.wav`, 4.815 s | Siren 0.653; notifies | Emergency vehicle 0.654; visual only |
| Clock `1-14262-A-37.wav`, 4.815 s | Telephone bell 0.523; notifies | Bicycle bell 0.670; visual only |

This comparison does not establish a recognition improvement from changing priority order. It removes one secondary phone notification but substitutes another non-target bell label, and it loses a specific Siren label for a marginally higher Emergency vehicle score. Neither Cat→Baby nor washing-machine→Alarm is fixed: no stronger eligible target candidate wins those windows. Production priorities were left unchanged; the evidence does not support tuning thresholds or claiming a broader gain.

## Input timing and provenance

`coreml-scores.f32le` stores all 521 outputs for each of 234 windows losslessly as little-endian Float32: 487,656 bytes. `replay-input.json` supplies score offsets, category/name/index comparators, public source URLs/attribution and hashes. It also records native-source RMS and both model and capture-end times. No 7.5 MB raw report or audio is duplicated.

Windows begin every 7680 samples at 16 kHz and contain 15600 samples. Capture-end times use the source-rate frame rounding from `YAMNetWindowSchedule` (for 44.1 kHz: 42998 frames, first end 0.9750113379 s). The selector receives these audio-end times, not processing or callback time. Native-source W/mono RMS applies the same 0.0001 gate as `SpatialCapture.receive`; each clip starts a fresh selector.

The scores were originally produced using scipy resample_poly on public mono audio, not the app’s AVAudioConverter or iPhone FOA. Live TTL expiration, skipped real-time windows and microphone timing were not exercised. Target comparators are explicit semantic label sets; a different label can be related rather than false. There is no negative-class set.

## Reproduce

Export from the existing conversion evidence (requires numpy/scipy, no TensorFlow/CoreML load):

```sh
.venv/bin/python tools/yamnet/prepare_selector_replay.py \
  --scores /tmp/fortwatch-yamnet-model/validation.json \
  --public-manifest /tmp/fortwatch-yamnet-model/evaluation-manifest.json \
  --output-directory /tmp/fortwatch-selector-input
```

The checked-in score trace can be replayed without downloading audio or loading the model:

```sh
swiftc -O ios/FortWatchListener/SoundCatalog.swift \
  ios/FortWatchListener/SoundEvents.swift ios/FortWatchListener/SpatialDirection.swift \
  ios/FortWatchListener/YAMNetEventSelector.swift tools/yamnet/replay_selector.swift \
  -o /tmp/fortwatch-replay-selector
/tmp/fortwatch-replay-selector docs/validation/yamnet/replay-input.json \
  /tmp/fortwatch-current-selector-results.json
```

That command evaluates the current production selector. To reproduce the historical policy, copy the corresponding `.swift.txt` snapshot to a temporary `.swift` path and compile it instead of the production selector. Subsequent production candidate-type changes may require matching the historical `SoundEventCandidate` shape; no policy should be reimplemented in the harness.

Source audio/labels: [official ESC-50 metadata](https://github.com/karolpiczak/ESC-50/blob/33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6/meta/esc50.csv), with [dataset license and per-source attributions](https://github.com/karolpiczak/ESC-50/blob/33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6/LICENSE). Audio remains temporary and is not included in the app or this report.
