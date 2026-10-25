#!/usr/bin/env python3
"""FortWatch live demo: listen on the Mac, classify with YAMNet, alert the ESP32.

    microphone -> YAMNet (on the Mac) -> Bluetooth LE or USB -> ESP32 screen

Audio never leaves the Mac. The ESP32 only receives short text messages:

    L,<0-100>            sound level, sent every hop (for the level bar)
    E,<EVENT>,<score>    detected event, e.g. "E,KNOCK,0.62"
    T,<HH:MM>,<date>     local time for the home-screen clock, every 10 s

Examples:
    .venv/bin/python live_demo/mac_listener.py                  # Bluetooth (default)
    .venv/bin/python live_demo/mac_listener.py --link usb       # USB cable
    .venv/bin/python live_demo/mac_listener.py --list-devices
    .venv/bin/python live_demo/mac_listener.py --no-serial      # test without the ESP32
    .venv/bin/python live_demo/mac_listener.py --device iPhone  # use the iPhone mic
    .venv/bin/python live_demo/mac_listener.py --set KNOCK=0.25 --set SPEECH=0.6
"""

from __future__ import annotations

from datetime import datetime

import argparse
import asyncio
import csv
import glob
import os
import queue
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass
from math import gcd
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import serial
import sounddevice as sd
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parent.parent
YAMNET_DIR = ROOT / "pretrained" / "yamnet"
MODEL_RATE = 16_000
WINDOW_SECONDS = 1.0  # YAMNet needs at least 0.975 s for one frame

# Must match BLE_NAME / BLE_SERVICE_UUID / BLE_RX_UUID in fortwatch_display.ino.
BLE_NAME = "FortWatch"
BLE_SERVICE_UUID = "6b1a0001-5d1e-4c3b-9a7e-50554e445345"
BLE_RX_UUID = "6b1a0002-5d1e-4c3b-9a7e-50554e445345"


@dataclass
class Event:
    classes: list[str]  # YAMNet display names
    threshold: float
    priority: int  # when several events fire at once, the highest priority wins
    min_hits: int = 1  # hops above threshold required within the last `window` hops
    window: int = 1
    cooldown: float = 2.0  # seconds before the same event can alert again


# Thresholds were chosen on ESC-50 (2,000 labelled clips) to keep false alerts
# low; SHOUT, DOORBELL, PHONE and SPEECH have no ESC-50 examples, so theirs are
# set from false-alert counts only. Tune with --set and the live printout.
EVENTS = {
    # Safety: always shown first.
    "ALARM": Event(
        [
            "Alarm",
            "Alarm clock",
            "Smoke detector, smoke alarm",
            "Fire alarm",
            "Car alarm",
            "Buzzer",
            "Siren",
            "Civil defense siren",
            "Police car (siren)",
            "Ambulance (siren)",
            "Fire engine, fire truck (siren)",
        ],
        0.50, priority=3,
    ),
    "CAR_HORN": Event(["Vehicle horn, car horn, honking", "Air horn, truck horn"], 0.30, priority=3),
    "GLASS": Event(["Glass", "Shatter", "Breaking", "Smash, crash"], 0.50, priority=3),
    "SHOUT": Event(["Shout", "Yell", "Screaming", "Children shouting"], 0.40, priority=3),
    # Attention: someone or something needs you.
    "BABY": Event(["Baby cry, infant cry"], 0.50, priority=2),
    "KNOCK": Event(["Knock"], 0.35, priority=2),
    "DOORBELL": Event(["Doorbell", "Ding-dong"], 0.30, priority=2),
    "PHONE": Event(["Telephone", "Telephone bell ringing", "Ringtone"], 0.50, priority=2),
    "DOG": Event(["Bark"], 0.30, priority=1),
    # Speech is everywhere, so it must last ~1.5 s (3 of the last 4 hops)
    # and alerts at most every 15 s.
    "SPEECH": Event(["Speech"], 0.50, priority=0, min_hits=3, window=4, cooldown=15.0),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--list-devices", action="store_true", help="list microphones and exit")
    parser.add_argument("--device", help="microphone index or part of its name (default: system input)")
    parser.add_argument(
        "--link", choices=["ble", "usb", "none"], default="ble",
        help="how to reach the ESP32: Bluetooth (default), USB cable, or none (print only)",
    )
    parser.add_argument("--port", help="USB serial port (default: first /dev/cu.usbmodem*)")
    parser.add_argument("--no-serial", action="store_true", help="same as --link none")
    parser.add_argument("--threshold", type=float, help="override every event threshold")
    parser.add_argument(
        "--set", action="append", default=[], metavar="EVENT=VALUE",
        help="override one event threshold, e.g. --set KNOCK=0.25 (repeatable)",
    )
    parser.add_argument(
        "--disable", action="append", default=[], metavar="EVENT",
        help="turn an event off, e.g. --disable SPEECH (repeatable)",
    )
    parser.add_argument("--hop", type=float, default=0.5, help="seconds between classifications")
    parser.add_argument("--quiet", action="store_true", help="only print detected events")
    return parser.parse_args()


def apply_overrides(args: argparse.Namespace) -> None:
    for name in args.disable:
        if name.upper() not in EVENTS:
            sys.exit(f"--disable {name}: unknown event. Choose from {', '.join(EVENTS)}")
        del EVENTS[name.upper()]
    if args.threshold is not None:
        for event in EVENTS.values():
            event.threshold = args.threshold
    for override in args.set:
        name, _, value = override.partition("=")
        name = name.upper()
        if name not in EVENTS or not value:
            sys.exit(f"--set {override}: use EVENT=VALUE with EVENT in {', '.join(EVENTS)}")
        EVENTS[name].threshold = float(value)


def resolve_device(spec: str | None) -> int | None:
    if spec is None:
        return None
    if spec.isdigit():
        return int(spec)
    for index, device in enumerate(sd.query_devices()):
        if device["max_input_channels"] > 0 and spec.lower() in device["name"].lower():
            return index
    sys.exit(f"No microphone matching '{spec}'. Run with --list-devices.")


def load_yamnet():
    import tensorflow as tf  # imported late so --list-devices stays fast

    print("Loading YAMNet...", flush=True)
    infer = tf.saved_model.load(str(YAMNET_DIR)).signatures["serving_default"]
    with (YAMNET_DIR / "assets" / "yamnet_class_map.csv").open(newline="") as handle:
        names = [row["display_name"] for row in csv.DictReader(handle)]

    def classify(waveform: np.ndarray) -> np.ndarray:
        outputs = infer(waveform=tf.convert_to_tensor(waveform, tf.float32))
        return outputs["output_0"].numpy().max(axis=0)  # max over YAMNet frames

    return classify, names


def event_indices(names: list[str]) -> dict[str, list[int]]:
    lookup = {name: index for index, name in enumerate(names)}
    missing = [c for event in EVENTS.values() for c in event.classes if c not in lookup]
    if missing:
        sys.exit(f"YAMNet class names not found: {missing}")
    return {name: [lookup[c] for c in event.classes] for name, event in EVENTS.items()}


class SerialLink:
    """Newline-delimited text over USB serial, reconnecting if the board is unplugged."""

    def __init__(self, port: str | None):
        self.port_spec = port
        self.serial: serial.Serial | None = None
        self.next_attempt = 0.0

    def _connect(self) -> None:
        if time.monotonic() < self.next_attempt:
            return
        self.next_attempt = time.monotonic() + 3.0
        ports = [self.port_spec] if self.port_spec else sorted(glob.glob("/dev/cu.usbmodem*"))
        if not ports:
            print("  (no ESP32 found on USB; retrying...)")
            return
        try:
            link = serial.Serial()
            link.port, link.baudrate, link.timeout = ports[0], 115200, 0
            # Keep DTR/RTS low so opening the port doesn't reset the ESP32.
            link.dtr = link.rts = False
            link.open()
            self.serial = link
            print(f"  Connected to ESP32 on {ports[0]}")
        except serial.SerialException as error:
            print(f"  Can't open {ports[0]}: {error}")
            print("  Is the Arduino Serial Monitor open? Close it and this will retry.")

    def send(self, line: str) -> None:
        if self.serial is None:
            self._connect()
            if self.serial is None:
                return
        try:
            self.serial.write((line + "\n").encode("ascii"))
        except (serial.SerialException, OSError):
            print("  ESP32 disconnected; retrying...")
            self.serial = None


class BleLink:
    """One message per BLE write, on a background thread that finds and reconnects to the ESP32."""

    def __init__(self):
        self.outbox: queue.Queue[str] = queue.Queue(maxsize=20)
        self.connected = False
        threading.Thread(target=lambda: asyncio.run(self._run()), daemon=True).start()

    def send(self, line: str) -> None:
        if not self.connected:
            return  # messages made while disconnected would be stale on arrival
        try:
            self.outbox.put_nowait(line)
        except queue.Full:
            pass

    @staticmethod
    def _is_fortwatch(device, advertisement) -> bool:
        uuids = [uuid.lower() for uuid in advertisement.service_uuids]
        return BLE_SERVICE_UUID in uuids or device.name == BLE_NAME

    async def _run(self) -> None:
        from bleak import BleakClient, BleakScanner

        while True:
            print("  Searching for FortWatch over Bluetooth...")
            device = await BleakScanner.find_device_by_filter(self._is_fortwatch, timeout=10.0)
            if device is None:
                print("  FortWatch not found. Is the ESP32 powered on and nearby? Retrying...")
                continue
            disconnected = asyncio.Event()
            try:
                async with BleakClient(device, disconnected_callback=lambda _: disconnected.set()) as client:
                    print("  Connected to FortWatch over Bluetooth")
                    self.connected = True
                    while not disconnected.is_set():
                        try:
                            line = self.outbox.get_nowait()
                        except queue.Empty:
                            await asyncio.sleep(0.02)
                            continue
                        # Alerts are acknowledged; level updates are fire-and-forget.
                        await client.write_gatt_char(
                            BLE_RX_UUID, line.encode("ascii"), response=line.startswith("E,")
                        )
            except Exception as error:  # bleak raises several types for radio/timeout errors
                print(f"  Bluetooth error: {error}")
            self.connected = False
            while not self.outbox.empty():
                self.outbox.get_nowait()
            print("  Bluetooth disconnected; reconnecting...")
            await asyncio.sleep(1.0)


class NoLink:
    def send(self, line: str) -> None:
        pass


def main() -> None:
    args = parse_args()
    if args.list_devices:
        print(sd.query_devices())
        return
    apply_overrides(args)

    device = resolve_device(args.device)
    info = sd.query_devices(device, kind="input")
    mic_rate = int(info["default_samplerate"])
    divisor = gcd(MODEL_RATE, mic_rate)
    up, down = MODEL_RATE // divisor, mic_rate // divisor

    classify, names = load_yamnet()
    indices = event_indices(names)
    link_type = "none" if args.no_serial else args.link
    link = {"ble": BleLink, "usb": lambda: SerialLink(args.port), "none": NoLink}[link_type]()
    history = {name: deque(maxlen=event.window) for name, event in EVENTS.items()}
    last_sent: dict[str, float] = {}

    chunks: queue.Queue[np.ndarray] = queue.Queue()

    def on_audio(data, frames, time_info, status):
        chunks.put(data[:, 0].copy())

    window = np.zeros(int(MODEL_RATE * WINDOW_SECONDS), np.float32)
    hop_samples = int(MODEL_RATE * args.hop)
    pending = np.zeros(0, np.float32)
    silent_hops = 0
    next_clock = 0.0  # the wristband has no clock of its own: send it the time

    print(f"Microphone: {info['name']} ({mic_rate} Hz, resampled to {MODEL_RATE} Hz)")
    print(f"ESP32 link: {link_type}")
    print("Alerts (threshold):")
    for name, event in EVENTS.items():
        sustain = f", needs {event.min_hits} of {event.window} hops" if event.min_hits > 1 else ""
        print(f"  {name:<9} {event.threshold:.2f}  priority {event.priority}{sustain}")
    print("Listening. Press Ctrl+C to stop.\n")

    with sd.InputStream(device=device, channels=1, samplerate=mic_rate, dtype="float32", callback=on_audio):
        while True:
            pending = np.concatenate([pending, resample_poly(chunks.get(), up, down).astype(np.float32)])
            if len(pending) < hop_samples:
                continue
            hop, pending = pending[:hop_samples], pending[hop_samples:]
            window = np.concatenate([window[len(hop):], hop])

            rms = float(np.sqrt(np.mean(hop**2)))
            db = 20 * np.log10(rms + 1e-10)
            level = int(np.clip((db + 60) / 60 * 100, 0, 100))  # -60 dBFS..0 dBFS -> 0..100
            link.send(f"L,{level}")
            if time.monotonic() >= next_clock:
                next_clock = time.monotonic() + 10
                link.send("T," + datetime.now().strftime("%H:%M,%A, %b %-d"))

            silent_hops = silent_hops + 1 if rms == 0.0 else 0
            if silent_hops == int(3 / args.hop):
                print("  Microphone is returning pure silence. Allow microphone access for your\n"
                      "  terminal app in System Settings > Privacy & Security > Microphone, then restart.")

            scores = classify(window)
            now = time.monotonic()
            candidates = []
            for name, event in EVENTS.items():
                score = float(scores[indices[name]].max())
                history[name].append(score >= event.threshold)
                sustained = sum(history[name]) >= event.min_hits
                cooled = now - last_sent.get(name, -1e9) >= event.cooldown
                if sustained and cooled:
                    candidates.append((event.priority, score / event.threshold, name, score))

            if candidates:
                _, _, name, score = max(candidates)
                last_sent[name] = now
                link.send(f"E,{name},{score:.2f}")
                print(f">>> {name}  score={score:.2f}")
            elif not args.quiet:
                top = np.argsort(scores)[-3:][::-1]
                bar = "#" * (level // 5)
                summary = "  ".join(f"{names[i]} {scores[i]:.2f}" for i in top)
                print(f"[{bar:<20}] {db:6.1f} dB | {summary}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")
