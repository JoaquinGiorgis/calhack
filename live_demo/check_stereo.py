#!/usr/bin/env python3
"""Check that two microphones arrive as two separate channels (for left/right direction).

    .venv/bin/python live_demo/check_stereo.py --list      # find the DJI receiver
    .venv/bin/python live_demo/check_stereo.py --device DJI

Put the mics apart (1-2 m). Clap or knock near the LEFT mic, then near the RIGHT one.
The bars show the volume of each channel; the louder side should change with the sound.
If the device only has 1 channel, the receiver is in Mono mode (LED green). Switch it to
Stereo (LED cyan) and try again.
"""

import argparse
import sys

import numpy as np
import sounddevice as sd


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--list", action="store_true", help="list input devices and exit")
    parser.add_argument("--device", help="device index or part of its name")
    args = parser.parse_args()

    if args.list:
        for index, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                print(f"{index:>3}  {d['name']}  ({d['max_input_channels']} channels)")
        return

    device = None
    if args.device:
        if args.device.isdigit():
            device = int(args.device)
        else:
            for index, d in enumerate(sd.query_devices()):
                if d["max_input_channels"] > 0 and args.device.lower() in d["name"].lower():
                    device = index
                    break
            else:
                sys.exit(f"No input matching '{args.device}'. Run with --list.")

    info = sd.query_devices(device, kind="input")
    channels = info["max_input_channels"]
    print(f"{info['name']}: {channels} channel(s)")
    if channels < 2:
        sys.exit("Only 1 channel: not usable for direction. Put the receiver in Stereo mode.")

    def on_audio(data, frames, time_info, status):
        rms = np.sqrt(np.mean(data[:, :2] ** 2, axis=0))
        db = 20 * np.log10(rms + 1e-10)
        bars = [int(np.clip((v + 60) / 60 * 30, 0, 30)) for v in db]
        side = "L" if db[0] - db[1] > 3 else "R" if db[1] - db[0] > 3 else "="
        print(f"L [{'#' * bars[0]:<30}] {db[0]:6.1f} dB   R [{'#' * bars[1]:<30}] {db[1]:6.1f} dB  {side}", end="\r")

    with sd.InputStream(device=device, channels=2, samplerate=info["default_samplerate"], callback=on_audio):
        print("Listening. Clap near each mic. Ctrl+C to stop.")
        try:
            while True:
                sd.sleep(1000)
        except KeyboardInterrupt:
            print()


if __name__ == "__main__":
    main()
