# FortWatch — project status and context

> **Latest iPhone revision (25 October):** the app now bundles YAMNet and the full
> 521-class catalog. See [current integration evidence](docs/SOUND-CATALOG-521.md).
> Apple SoundAnalysis and ten-category iPhone notes below describe the earlier revision.
> The [Orbit screen redesign](docs/design/ORBIT-REDESIGN.md) now matches the website
> across native iPhone and firmware alerts. Builds and software checks pass;
> revision `1e782dc` is installed on both devices. Physical direction validation remains pending.

*Last updated: 2026-10-25, during Cal Hacks 13.0 (Palace of Fine Arts, San Francisco).*

For setup and usage, see [README.md](README.md). This document records where the
project stands, why it is built the way it is, and what comes next.
The [main-sync audit](docs/CURRENT-CAPABILITIES.md) records the current branch
differences, software checks and unresolved limitations. Hardware reports below
come from the team's updated BOARD; this audit did not repeat them physically.

## The problem

Deaf and hard-of-hearing people can miss sounds that matter: a knock at the door, a
doorbell, a smoke alarm, a car horn, someone calling them. FortWatch is a wristband
that shows those sounds as clear, full-screen visual alerts, so the person doesn't
need to be looking at a phone.

It is a complementary aid. It is **not** a certified safety device and must not
replace smoke alarms or other alerting systems.

## Current status: working prototype

| Part | Status |
|---|---|
| Direct iPhone recognition + spatial direction + BLE | Implemented; physical validation pending |
| Sound classification on the Mac (YAMNet fallback) | Working |
| Wristband firmware: Orbit alerts, live level meter, dismiss | Orbit installed on 25/10; previous touch controls preserved. Hold home/BOOT for 1 s to toggle SPEECH, persisted across restart |
| Bluetooth LE link, Mac → wristband (wristband on a power bank) | Working |
| USB link (fallback) | Working |
| 10 alert types with priorities and thresholds | Working, thresholds partly validated (see below) |
| Live test with real sounds, end to end | Partially done; needs a full pass per alert |
| 3D-printed case and strap | Team reports shell, lid and weights printed; assembly and wrist-use validation remain in progress |
| Vibration | Team reports motor circuit assembled without breadboard and working with power bank and real alerts |
| Live analytics: wristband uploads alert metadata over Wi-Fi (`wifi_analytics.h`) | Team reports hotspot upload working; bounded queues can lose events during outages |
| Classification on the wristband itself | Not started (needs an I2S microphone) |

### What has been verified

- **Classification:** YAMNet run over all 2,000 ESC-50 clips to choose thresholds;
  results are in the README. A short live run on the MacBook mic raised no false
  alerts in a noisy hackathon hall.
- **Firmware:** earlier team version was compiled and flashed to the board; the combined iPhone/main firmware has separate software checks in the audit and has not been flashed during this audit.
- **Bluetooth:** the board advertises as `FortWatch`; the Mac finds it, connects in
  about 2.5 s, and the board acknowledges alert messages.
- **Mac program options:** `--set`, `--disable`, `--link` and input validation.

### What has not been verified

- Most alerts with real sounds through a microphone in a real room, especially
  SHOUT, DOORBELL, PHONE and SPEECH, which had no labelled test recordings.
- Long-running stability (hours) and Bluetooth range in a crowded space.
- Battery life on the power bank.

## How it works

### Direct iPhone listener (2026-10-25)

The native app now uses bundled YAMNet through Core ML and FOA direction estimation on the
iPhone, then connects directly to the existing ESP32 BLE service. No Mac, HTTP,
pairing token or Wi-Fi is required at runtime. There is a manual vibration test,
explicit Bluetooth connection and foreground-only capture. See [iOS setup](ios/README.md).

YAMNet replaces the earlier Apple classifier and exposes all 521 class names.
Model conversion and on-device synthetic inference checks passed; a small public
audio replay is documented in `docs/validation/yamnet/`. This does not establish
general accuracy. The Mac benchmark below applies only to the older Mac demo.
Both updated devices are installed. Physical calibration accuracy, microphone
recognition and end-to-end screen/motor behavior still need validation.

### Existing Mac fallback path

```
Mac microphone ─► YAMNet (on the Mac) ─► Bluetooth LE ─► ESP32-S3 wristband
```

1. The Mac records audio and, twice a second, classifies the last second with YAMNet
   (521 sound types).
2. Each FortWatch alert groups several YAMNet types and has its own threshold and
   priority. Speech must last ~1.5 s and alerts at most every 15 s.
3. The Mac sends short text messages (`L,<level>`, `E,<EVENT>,<score>`) to the
   wristband. Audio never leaves the Mac.
4. The wristband shows a live level bar and full-screen coloured alerts with large
   text, so meaning never depends on colour alone.

### Hardware

- **Wristband:** Waveshare ESP32-S3-Touch-LCD-2 (ESP32-S3R8, 8 MB PSRAM, 16 MB flash,
  2" 240×320 touchscreen), powered by a USB-C power bank.
- **Listener:** the native iPhone app; the existing Mac/YAMNet demo is an optional fallback.
- **Vibration:** 130 DC motor with a printed eccentric weight, switched by a PN2222
  from GPIO17 (1 kΩ to the base, motor on 5 V, 1N4007 across the motor).
- **Case:** parametric OpenSCAD model with a snap-fit back (no screws), sized for the
  board, female Dupont jumpers on the header pins, and the motor. Checked with
  `hardware/tools/check_stl.py` (watertight parts, no collisions, PLA snap-fit
  strain 0.4 %). See `hardware/enclosure/README.md`.

## Key decisions and why

**Classification runs on the listener, not the wristband.** Both the current iPhone app and original Mac demo use YAMNet, with different selection policies. The board has no microphone
suitable for classification. The team's Grove Sound Sensor is built for loudness:
its fixed high-gain amplifier clips on loud sounds such as alarms and horns, so it
cannot feed a classifier. An I2S MEMS microphone (e.g. INMP441) is needed for
on-device classification, and none was available in time.

**Pretrained YAMNet instead of a custom model.** The team first trained tiny custom
models (≈17k parameters) on ESC-50 plus UrbanSound8K. A review found:

- **Data leakage:** ESC-50 and UrbanSound8K share Freesound source recordings. All 8
  car-horn test clips came from recordings that were also in the training data, so
  the reported car-horn accuracy was inflated. A model that hadn't seen some of
  those recordings detected 1 of 8.
- **Very few test examples:** 8–16 clips per sound type, too few for reliable
  numbers.
- **Accuracy looked better than it was:** 92% of test clips were background noise,
  so 95% "accuracy" was close to always guessing "no event".

YAMNet was trained by Google on ~2 million AudioSet clips, already covers the target
sounds (knock, doorbell, alarm, siren, horn and more), and needs no training. That
research code is kept outside this repo.

**Bluetooth LE for the link.** The ESP32-S3 supports Bluetooth LE but not Classic
Bluetooth, so Bluetooth headsets can't be used as a microphone. BLE is ideal for
short alert messages. USB remains as a fallback.

**Thresholds chosen from data, then adjusted in live tests.** The initial Mac
thresholds were measured on ESC-50. KNOCK was initially raised to 0.35, then changed
to 0.30 with broader wood-impact classes in the 25/10 update. That update also vetoes
GLASS when those classes score as highly; the old benchmark has not been rerun for
this configuration. DOG uses only "Bark" because the broader "Dog" class fired on
pigs and toothbrushes. The iPhone's expanded selector exposes all classes with
hierarchy suppression and provisional thresholds; physical accuracy remains unverified.

## Known limitations

- The iPhone must remain within Bluetooth range, upright and fixed for direction, with this app open. Background listening and physical range are not verified.
- Thresholds were tuned on clean recordings; real rooms with distance, echo and
  crowd noise will perform worse.
- YAMNet can tell that speech is happening, not who is speaking or whether someone
  said the user's name.
- Some car horns are labelled ALARM. Both still raise an alert.
- Vibration uses a small DC motor with a printed eccentric weight, not a coin vibration motor, and has not been tested on the wrist yet.
- Touch-to-dismiss reads the CST816 controller directly over I2C; if it doesn't respond, the BOOT button still works.
- Wi-Fi upload needs a 2.4 GHz network without a login page: the ESP32-S3 can't use 5 GHz. The Cal Hacks Wi-Fi is 5/6 GHz only, so the demo uses a phone hotspot. Wi-Fi passwords and the dashboard key live in the git-ignored `secrets.h`; the dashboard URL's token expires around 24/11.

## Next steps

**Near term (hackathon):**
1. Live test every alert with real sounds and tune thresholds.
2. Rehearsal mode: feed a fixed recording through the same pipeline, so the demo
   behaves the same every time.
3. Record a backup demo video.

**Product:**
1. **Validate the direct iPhone app** with real sounds, BLE and the motor. Pocket/background use still needs separate work; the spatial version requires a fixed phone.
2. **Vibration:** patterns per priority are in the firmware (safety: 3 long, attention:
   2 short, low: 1 short). Next: test them on the wrist and swap the DC motor for a
   coin vibration motor. For deaf users, feeling an alert matters more than seeing it.
3. An alert history screen (touch-to-dismiss is in the firmware).
4. **Fully on-device:** add an INMP441 microphone and run an INT8 YAMNet on the
   ESP32-S3, so no phone or laptop is needed. This needs latency and memory checks on
   the board.
5. **Validate with deaf and hard-of-hearing users**: which sounds matter, and how
   alerts should look and feel.
