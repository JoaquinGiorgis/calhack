# SoundSense — project status and context

*Last updated: 2026-10-24, during Cal Hacks 13.0 (Palace of Fine Arts, San Francisco).*

For setup and usage, see [README.md](README.md). This document records where the
project stands, why it is built the way it is, and what comes next.

## The problem

Deaf and hard-of-hearing people can miss sounds that matter: a knock at the door, a
doorbell, a smoke alarm, a car horn, someone calling them. SoundSense is a wristband
that shows those sounds as clear, full-screen visual alerts, so the person doesn't
need to be looking at a phone.

It is a complementary aid. It is **not** a certified safety device and must not
replace smoke alarms or other alerting systems.

## Current status: working prototype

| Part | Status |
|---|---|
| Sound classification on the Mac (YAMNet) | Working |
| Wristband firmware: alerts, level bar, dismiss button | Working |
| Bluetooth LE link, Mac → wristband (wristband on a power bank) | Working |
| USB link (fallback) | Working |
| 10 alert types with priorities and thresholds | Working, thresholds partly validated (see below) |
| Live test with real sounds, end to end | Partially done; needs a full pass per alert |
| 3D-printed case and strap | Not started in this repo |
| Vibration | Not started (needs a motor and driver circuit) |
| Classification on the wristband itself | Not started (needs an I2S microphone) |

### What has been verified

- **Classification:** YAMNet run over all 2,000 ESC-50 clips to choose thresholds;
  results are in the README. A short live run on the MacBook mic raised no false
  alerts in a noisy hackathon hall.
- **Firmware:** compiles for the ESP32-S3 and was flashed to the board.
- **Bluetooth:** the board advertises as `SoundSense`; the Mac finds it, connects in
  about 2.5 s, and the board acknowledges alert messages.
- **Mac program options:** `--set`, `--disable`, `--link` and input validation.

### What has not been verified

- Most alerts with real sounds through a microphone in a real room, especially
  SHOUT, DOORBELL, PHONE and SPEECH, which had no labelled test recordings.
- Long-running stability (hours) and Bluetooth range in a crowded space.
- Battery life on the power bank.

## How it works

```
Mac microphone ─► YAMNet (on the Mac) ─► Bluetooth LE ─► ESP32-S3 wristband
```

1. The Mac records audio and, twice a second, classifies the last second with YAMNet
   (521 sound types).
2. Each SoundSense alert groups several YAMNet types and has its own threshold and
   priority. Speech must last ~1.5 s and alerts at most every 15 s.
3. The Mac sends short text messages (`L,<level>`, `E,<EVENT>,<score>`) to the
   wristband. Audio never leaves the Mac.
4. The wristband shows a live level bar and full-screen coloured alerts with large
   text, so meaning never depends on colour alone.

### Hardware

- **Wristband:** Waveshare ESP32-S3-Touch-LCD-2 (ESP32-S3R8, 8 MB PSRAM, 16 MB flash,
  2" 240×320 touchscreen), powered by a USB-C power bank.
- **Listener:** a Mac. Its built-in mic or an iPhone (via Continuity) works.

## Key decisions and why

**Classification runs on the Mac, not the wristband.** The board has no microphone
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

**Thresholds chosen from data.** Each threshold trades hit rate against false
alerts measured on ESC-50. Some initial guesses were changed as a result: KNOCK went
from 0.20 to 0.35 because keyboard typing and footsteps triggered it, and DOG uses
only "Bark" because the broader "Dog" class fired on pigs and toothbrushes.

## Known limitations

- Needs the Mac nearby (Bluetooth range roughly 5–10 m indoors).
- Thresholds were tuned on clean recordings; real rooms with distance, echo and
  crowd noise will perform worse.
- YAMNet can tell that speech is happening, not who is speaking or whether someone
  said the user's name.
- Some car horns are labelled ALARM. Both still raise an alert.
- Alerts are visual only (no vibration yet).
- Dismissing an alert uses the small BOOT button, not the touchscreen.

## Next steps

**Near term (hackathon):**
1. Live test every alert with real sounds and tune thresholds.
2. Rehearsal mode: feed a fixed recording through the same pipeline, so the demo
   behaves the same every time.
3. Record a backup demo video.

**Product:**
1. **iPhone app as the listener**, using Apple's on-device sound classifier and
   sending the same Bluetooth messages, so the phone stays in a pocket.
2. **Vibration** with a distinct pattern per alert. For deaf users, feeling an alert
   matters more than seeing it.
3. **Touch-to-dismiss** and an alert history screen.
4. **Fully on-device:** add an INMP441 microphone and run an INT8 YAMNet on the
   ESP32-S3, so no phone or laptop is needed. This needs latency and memory checks on
   the board.
5. **Validate with deaf and hard-of-hearing users**: which sounds matter, and how
   alerts should look and feel.
