# FortWatch — Feel What You Can't Hear

A wrist-worn display that turns important sounds into visual alerts for deaf and
hard-of-hearing people. Built at Cal Hacks 13.0.

```
iPhone microphones → YAMNet (521 classes) + direction (on iPhone) → Bluetooth LE → ESP32-S3 wristband
```

The iPhone app now connects directly to the wristband. It recognizes sounds and
estimates their dominant direction locally; it sends only alert, level and clock
messages over Bluetooth. No Mac, server, Wi-Fi or account is required while using
the app. Xcode on a Mac is used to build and install this prototype.

The iPhone bundles a converted copy of Google YAMNet and exposes its full 521-class
vocabulary. Specific names appear on both screens; related classes share learned
rhythms. The Mac demo remains a separate ten-alert fallback. Its older benchmark
does not establish accuracy for the expanded iPhone selector.

See [the 521-class integration and verification](docs/SOUND-CATALOG-521.md).

> **Status:** direct iPhone software integration; real iPhone capture, angular
> accuracy and physical BLE/motor validation still pending. FortWatch is a
> complementary aid and does not replace certified safety devices.

For where the project stands, why it is built this way, and what's next, see
[PROJECT_STATUS.md](PROJECT_STATUS.md).
The [2026-10-25 capability audit](docs/CURRENT-CAPABILITIES.md) separates changes
from `main`, local iPhone functionality, team-reported hardware tests and remaining gaps.

## What's in this repo

| Path | What it is |
|---|---|
| `live_demo/mac_listener.py` | Mac program: microphone → YAMNet → Bluetooth/USB → wristband |
| `ios/` | Native iPhone recognition, spatial direction and direct Bluetooth to the wristband |
| `live_demo/spatial_audio.py` | Spatial receiver, calibration and dominant-sound angle estimator |
| `live_demo/fortwatch_display/` | Wristband firmware (Arduino sketch). Screens are the Figma designs in `screens.h` |
| `live_demo/screen_preview/` | Slideshow firmware to preview every designed screen on the real display |
| `live_demo/requirements.txt` | Python packages for the Mac program |
| `pretrained/yamnet/` | Google's YAMNet model (Apache 2.0), loaded by the Mac program |
| `hardware/enclosure/` | 3D-printable wristband case (OpenSCAD source, STLs, 3D viewer) |
| `hardware/tools/` | STL export and pre-print checks for the case |
| `docs/hardware/` | Hardware inventory and parts photos |
| `BOARD.md` · `dashboard.html` | Team task board and a local dashboard for it (Spanish) |

## Use the iPhone directly

See [the iPhone setup](ios/README.md). Power the wristband, stop any running Mac
receiver, then tap **Connect → Sound library → Test**, then **Start listening**.
Allow Bluetooth and microphone. Keep the app open and the iPhone upright on a
fixed support; calibrate the front before testing direction.

The searchable library contains all 521 model classes, with eight family filters.
Silence is visible in the catalog but does not trigger an automatic alert. Legacy
alert messages and their ten rhythms remain supported.

## Mac fallback: detection and benchmark

Twice a second, the Mac takes the last second of audio, and YAMNet scores it against
521 sound types. Each FortWatch alert groups a few of those types; when the best
score in a group passes its threshold, the alert is sent. If several fire at once,
the highest priority wins, and the same alert won't repeat within 2 seconds.

| Priority | Alert | YAMNet sound types | Threshold |
|---|---|---|---|
| Safety | ALARM! | Alarm, alarm clock, smoke/fire alarm, car alarm, buzzer, sirens | 0.50 |
| Safety | CAR HORN | Vehicle horn, air/truck horn | 0.30 |
| Safety | GLASS | Glass, shatter, breaking, smash | 0.50 |
| Safety | SHOUT! | Shout, yell, screaming, children shouting | 0.40 |
| Attention | BABY | Baby cry | 0.50 |
| Attention | KNOCK | Knock, Door, Wood, Chop, Hammer, Whack/thwack, Tap | 0.30 |
| Attention | DOORBELL | Doorbell, ding-dong | 0.30 |
| Attention | PHONE | Telephone, telephone bell, ringtone | 0.50 |
| Low | DOG | Bark | 0.30 |
| Lowest | SPEECH | Speech lasting ~1.5 s; at most once every 15 s | 0.50 |

Everything else (music, typing, general noise) only moves the level bar.

The 2026-10-25 Mac update expands the KNOCK mapping and suppresses GLASS when a
wood-impact class scores at least as highly. This heuristic applies to both Mac
input paths after integration; it is not part of the iPhone's Apple classifier.
The ESC-50 numbers below describe the earlier mapping and thresholds, not a new
evaluation of this knock/glass heuristic.

**How the thresholds were chosen:** YAMNet was run over the 2,000 labelled clips of
the [ESC-50](https://github.com/karolpiczak/ESC-50) dataset, picking values that
catch most real events while keeping false alerts on the other 49 sound categories
low:

| Alert | Caught | False alerts (of ~1,960 other 5 s clips) |
|---|---|---|
| ALARM | 94% | 45 (mostly car horns) |
| CAR HORN | 72% | 11 |
| GLASS | 90% | 12 |
| BABY | 90% | 12 |
| KNOCK | 78% | 13 (footsteps, typing) |
| DOG | 97% | 6 |

These are optimistic: clean recordings, with thresholds picked and measured on the
same clips. ESC-50 has no shout, doorbell, phone or speech examples. A real room
(distance, echo, crowd noise) will do worse, so tune live with `--set`.

## Optional Mac demo setup

### What you need

- Waveshare **ESP32-S3-Touch-LCD-2** (16 MB flash, 8 MB PSRAM)
- A USB-C power bank for the wristband (or a USB cable to the Mac)
- A Mac with Python 3.11 and a microphone (an iPhone also works as the mic, via Continuity)

### 1. Install the Mac program

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r live_demo/requirements.txt
```

### 2. Flash the wristband

**Arduino IDE:** install the board package **esp32 by Espressif Systems** and the
library **GFX Library for Arduino** (by Moon On Our Nation). Open
`live_demo/fortwatch_display/fortwatch_display.ino` and set **Tools**:

| Setting | Value |
|---|---|
| Board | ESP32S3 Dev Module |
| USB CDC On Boot | Enabled |
| Flash Size | 16MB |
| PSRAM | OPI PSRAM |

Then click Upload.

**Or with PlatformIO** (no Arduino IDE needed):

```bash
cd live_demo/fortwatch_display && pio run -t upload
```

**Or with `arduino-cli`:**

```bash
FQBN="esp32:esp32:esp32s3:CDCOnBoot=cdc,FlashSize=16M,PSRAM=opi,USBMode=hwcdc"
arduino-cli compile -b "$FQBN" live_demo/fortwatch_display
arduino-cli upload  -b "$FQBN" -p /dev/cu.usbmodem1101 live_demo/fortwatch_display
```

Stop `mac_listener.py` before uploading. If the screen stays black afterwards, press
the board's RESET button.

### 3. Run

Power the wristband. It shows *Waiting for Mac... Bluetooth: FortWatch*. Then:

```bash
.venv/bin/python live_demo/mac_listener.py
```

Within a few seconds the terminal says `Connected to FortWatch over Bluetooth` and
the wristband switches to **LISTENING...** with a live level bar. Detected sounds
fill the screen with the designed alert (icon, priority, live confidence bar) and
vibrate with the alert's priority pattern; **tap the screen** or press **BOOT** to
dismiss, or it clears after 6 seconds. On first run, allow Terminal to use the **microphone** and **Bluetooth**
(System Settings → Privacy & Security).

### Options

| Command | Effect |
|---|---|
| `--link usb` | Use the USB cable instead of Bluetooth |
| `--no-serial` | No wristband: just print what's detected |
| `--device iPhone` | Use a different microphone (`--list-devices` lists them) |
| `--set KNOCK=0.25` | Change one alert's threshold (repeatable) |
| `--threshold 0.3` | Set every threshold at once |
| `--disable SPEECH` | Turn an alert off (repeatable) |
| `--quiet` | Only print detected alerts |

The terminal prints YAMNet's top three guesses with scores twice a second. To tune a
threshold, make the sound a few times, note its typical score, and set the threshold
a bit below it.

### Sound direction on iPhone

The native app calculates direction and classifies the same audio window on the
phone, then sends the angle with the alert over Bluetooth. It no longer streams
audio to the Mac. See [setup and limitations](docs/SPATIAL-DIRECTION.md).
The older Python spatial receiver remains available for protocol research, but
is not part of the current app's runtime.

### Live analytics dashboard (optional)

The wristband can upload every alert it shows (name, score, level, time; never audio)
to the team's analytics dashboard over **Wi-Fi**, on its own, without the Mac's help:
copy `live_demo/fortwatch_display/secrets.example.h` to `secrets.h` in the same folder,
fill in the Wi-Fi networks, the ingest URL and the device key (ask the team; the file
is git-ignored so the secrets never get committed), and flash. The serial monitor
prints `Wi-Fi: connected to ...` and `Analytics: uploaded 1 alert(s)`.

The ESP32-S3 only joins **2.4 GHz** WPA2/WPA3 networks without a login page. If the
venue Wi-Fi is 5 GHz only (the serial monitor says `not in range on 2.4 GHz`), use a
phone hotspot with "Maximize Compatibility" turned on.

Without Wi-Fi, `mac_listener.py` can upload instead: copy
`live_demo/analytics.env.example` to `live_demo/analytics.env` and fill it in. Use one
or the other, not both, or every alert is counted twice.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Terminal keeps saying `FortWatch not found` | Check the wristband is powered and nearby; allow Bluetooth for Terminal |
| Wristband stuck on *Waiting for Mac...* | The Mac program isn't running or isn't connected; check the terminal |
| `Microphone is returning pure silence` | Allow microphone access for Terminal, then restart the program |
| A sound shows a score but never alerts | Lower that alert's threshold with `--set` |
| Too many false alerts | Raise thresholds, or `--disable SPEECH` in noisy rooms |
| `Can't open /dev/cu.usbmodem…` (USB mode) | Close the Arduino Serial Monitor; only one program can use the port |

## How the listener talks to the wristband

The same text messages go over Bluetooth LE or USB:

| Message | Meaning |
|---|---|
| `L,<0-100>` | Sound level, every 0.5 s (drives the level bar) |
| `E,<EVENT>,<score>` | Detected alert, e.g. `E,KNOCK,0.62`. Unknown names still display |
| `E,<EVENT>,<score>,<angle>,<quality>` | Optional dominant-sound direction relative to the calibrated phone; old messages still work |
| `T,<HH:MM>,<date>` | Local time for the home-screen clock, every 10 s (the wristband has no clock) |

- **Bluetooth:** the wristband advertises as `FortWatch` with service
  `6b1a0001-5d1e-4c3b-9a7e-50554e445345`. Each write to characteristic
  `6b1a0002-5d1e-4c3b-9a7e-50554e445345` is one message.
- **USB:** newline-terminated lines at 115200 baud.

To add a new alert to the Mac listener, add an entry to `EVENTS` in `mac_listener.py` using YAMNet's
class names from `pretrained/yamnet/assets/yamnet_class_map.csv`. The wristband shows
any new name automatically. For a custom colour and hint text, add it to
`EVENT_STYLES` in the sketch.
For the native iPhone app, update `SoundEventSelector.defaultPolicies` separately
using identifiers from Apple's classifier; Python/YAMNet changes do not carry over.

## Roadmap

- Run classification on the wristband with an I2S MEMS microphone (INMP441), so no
  Mac or phone is needed
- Validate direct iPhone recognition, sound direction and BLE; add background/pocket use separately
- Touch-to-dismiss and alert history (vibration patterns per priority are already in the firmware)

## Credits

- [Apple SoundAnalysis](https://developer.apple.com/documentation/soundanalysis) for the native iPhone classifier

- [YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)
  by Google, Apache License 2.0
- Display setup follows Waveshare's
  [ESP32-S3-Touch-LCD-2](https://docs.waveshare.com/ESP32-S3-Touch-LCD-2) Arduino
  examples (board docs and schematic at that link)
- [GFX Library for Arduino](https://github.com/moononournation/Arduino_GFX)
- Thresholds evaluated on [ESC-50](https://github.com/karolpiczak/ESC-50) by K. J. Piczak
