# Full YAMNet sound catalog — 25 October 2026

The iPhone path now runs the bundled Google YAMNet model through Core ML. It no
longer uses Apple's 303-label SoundAnalysis model in production. All 521 original
YAMNet classes have stable IDs, exact names, display titles, styles, family rhythms
and a wristband renderer. The legacy ten-alert wire format remains supported.

## What users see

- **Sound library** contains 521 searchable entries and eight family filters:
  People, Animals, Nature, Vehicles, Home, Music, Devices & machines, Other sounds.
- Both screens use the specific predicted class name. Shared colors, meaningful
  subfamily icons and family rhythms make related classes recognizable without
  implying 521 unique motor patterns. The ten learned alert rhythms remain.
- The photo, translucent dark surfaces, lime accent and bundled brand typefaces
  are preserved. Names wrap, with longer model names retained in explanatory copy.
- The [Orbit redesign](design/ORBIT-REDESIGN.md) now shares graphite/smoke surfaces,
  Gabarito/Atkinson type and a lime bearing crescent across both devices. Wristband
  titles use Gabarito 32 px for 476 cards and 20 px for 45 long titles. All 521
  preserve full words and fit their region. The ten legacy alert screens use this
  new composition too; their wire messages and learned pulse arrays are preserved.
- Silence is listed for vocabulary completeness, with **No vibration**; it does
  not create an automatic alert. All other 520 classes are eligible for selection.
- A direction is shown only when the current spatial measurement meets the
  existing quality rules. A recent label never borrows a newer sound's direction.
- Manual `P,Ynnn` tests remain visibly marked TEST and never become analytics.

## Actual processing

`YAMNetClassifier.swift` loads the 16,144,253-byte FP32 Core ML package, including
Hann window, FFT, mel projection and log frontend. Input is Float32 mono W at
16 kHz, 15,600 samples; output is 521 sigmoid scores in the exact CSV order.
The original four-channel FOA window is retained for direction. Supported source
rates are resampled with AVAudioConverter, with pitch and anti-alias checks.

Windows are 975 ms with a 480 ms hop. One inference slot is allowed. A busy model
skips old windows rather than growing a queue. The 750 ms delivery deadline starts
at capture end, not after inference. Calibration, gaps, interruptions and stop
invalidate generations; old results cannot revive earlier directions.

The full selector requires a present-window hit. New general classes use a
provisional 0.60 score threshold. The screen updates on the current hit; vibration
waits for two hits in three contiguous windows. Speech notification requires three
in four. Existing specialized families retain their starting
thresholds. An eligible specific child removes its generic ancestors. One class
wins by priority, then score. Notification cooldown is applied after selection and grouped by rhythm. Fresh
labels/directions still reach both screens through a display-only D message; they
do not restart the motor, increase counters or create duplicate dashboard records.
Weaker guesses cannot become alerts merely because the winner is cooling down. This is classification of a dominant audio window, not source separation.

## Evidence

| Check | Result | Scope |
|---|---|---|
| Model conversion vs original TensorFlow | PASS, 238/238 top labels identical; max score error 0.0000117123 | 26 public ESC-50 clips ×9 windows +4 synthetic inputs; CPU on Mac |
| Installed iOS model in Simulator | PASS | Three deterministic waveforms, all 521 scores compared against original TF, error limit 0.001 |
| Full iOS suite | PASS, 66 production tests plus three render exports | Catalog/CSV, styles/SF Symbols/contrast, all 520 alertable classes, quiet behavior, hierarchy, messages, audio resampling, windows, existing spatial/legacy tests |
| Swift/C++ rhythm contract | PASS, 531 event IDs | 521 catalog IDs plus 10 legacy events; exact pulse arrays, quiet and invalid IDs |
| C++ host checks | PASS | Catalog, legacy haptics and parser under AddressSanitizer/UndefinedBehaviorSanitizer |
| Signed iPhone app build | PASS | Compiles, signs and includes the model |
| New model inference on connected iPhone | PASS, 3 runtime tests | All 521 synthetic score parity, six source-rate conversion checks, window scheduling; predictions 5.07–8.76ms |
| New visual render review | PASS within software scope | Native SwiftUI cards, three sample library rows and largest accessibility text size inspected; 521 firmware titles checked. Actual Simulator search returned Piano/Electric piano; Nature filter returned 17 classes; no-results state and search dismissal verified. Physical screen review remains pending |
| New firmware build | PASS | Orbit composition and Gabarito/Atkinson atlases; analytics enabled, RAM 84,108 B, flash 3,712,625 B; no credentials changed |
| Final app + firmware installation | PASS | Orbit revision `1e782dc`: iPhone installation/launch/process verified; ESP32-S3 app0 hash verified and FortWatch BLE advertisement detected after reboot. Physical sound/direction validation remains pending |
| Expanded dashboard vocabulary | NOT VERIFIED | Mana project requires access; never send unknown IDs into legacy batch until contract is verified |

Detailed model reproducibility, version hashes, original conversion failure and
precise DFT coefficient fix: [tools/yamnet/README.md](../tools/yamnet/README.md).
Model license and provenance are bundled in `ios/FortWatchListener/Models/`.
The catalog's AudioSet ancestry retains CC BY-SA attribution in its generated data.

## Dashboard preservation

The remote dashboard is an authenticated Mana app whose ingest schema is not in
this repository. Its firmware uploader drops an entire batch for some 4xx errors;
sending an unsupported new ID could therefore also lose old alerts. A tested
compatibility adapter maps only the 36 exact original Mac source classes back to
the ten existing dashboard event names. Other 485 catalog classes stay local to
phone/wristband until that backend is expanded. No family/ancestry shortcut labels
a new sound as an old event. Wi-Fi, keys, heartbeat, queueing and original events
are preserved. Manual P tests and display-only D updates never enqueue analytics.

## Accuracy and remaining limits

Numeric parity proves the conversion preserves the original model, not that the
model identifies every physical sound correctly. The public sample contains
original-model errors, including footsteps strongly classified as fireworks and
washing-machine audio classified as engine/train. There is no 521-class physical
confusion matrix, nor a measured guarantee of accuracy across environments.

The separate selector replay reports exact alerts after thresholds and hierarchy;
its output must not be confused with raw model top labels. A catalog test with
synthetic scores only proves that a category is wired through the application.

The new implementation still needs an on-phone microphone run with this model, a physical
Bluetooth/screen/motor check, and user validation of rhythm distinguishability.
Front calibration and physical angle sign/accuracy remain unresolved from the
previous revision. No new result claims to fix them. One motor does not physically
indicate left/right. The app still needs to remain open, does not recognize the
spoken command “Fortnite,” and does not locate multiple independent sources.

## Verification commands

```sh
python3 tools/generate_sound_catalog.py
xcodebuild -project ios/FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' \
  -derivedDataPath /tmp/fortwatch-design-update/ios-build CODE_SIGNING_ALLOWED=NO test
python3 live_demo/tests/test_haptic_contract.py
python3 live_demo/tests/test_catalog_title_layout.py
python3 live_demo/tests/test_display_runtime.py
python3 live_demo/tests/test_analytics_compatibility.py
```

The final replay of real recorded scores produced a target-specific visual label
in 19 of 24 clips with a modeled comparator, and a target notification in 16 of 24.
The two washing-machine clips have no exact YAMNet class. These counts are a small
selected sample, not general accuracy. Compared with the original coupling,
separating display and notification exposed Rain, Footsteps and Cough. Recorded
confusions remain, and rapid related-label alternation still needs physical review.
[Full replay evidence](validation/yamnet/README.md).

Current run logs in `/tmp/fortwatch-yamnet-model/`: `ios-final-production-tests.log`,
`iphone-runtime-tests.log`, `iphone-final-build.log`, `firmware-final-build.log`,
`library-render.log`, `validation.json` and `evaluation-manifest.json`.
Raw recordings remain in temporary validation folders, outside the repo and app.

## Visual evidence

[Actual Simulator search](design/ios/yamnet-library-search.png) shows the production
library, disconnected from a wristband. [Static sample cards](design/ios/yamnet-library-samples.png)
and [largest text size](design/ios/yamnet-library-largest-text.png) are explicitly
simulated SwiftUI renders. [Wristband catalog](design/wristband-catalog-preview.png)
and [LIVE / RECENT / TEST states](design/wristband-live-preview.png) are software
renders of the firmware drawing functions, not photos of the device.
