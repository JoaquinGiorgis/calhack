#!/usr/bin/env python3
"""Fetch a bounded, deterministic public evaluation subset; never app assets."""
import argparse
import concurrent.futures
import csv
import hashlib
import io
import json
from pathlib import Path
import urllib.request

COMMIT = "33c8ce9eb2cf0b1c2f8bcf322eb349b6be34dbb6"
BASE = f"https://raw.githubusercontent.com/karolpiczak/ESC-50/{COMMIT}/"
CATEGORIES = ["glass_breaking", "car_horn", "siren", "clock_alarm", "crying_baby",
              "door_wood_knock", "dog", "cat", "rain", "footsteps", "clapping",
              "coughing", "washing_machine"]


def fetch(url, limit):
    request = urllib.request.Request(url, headers={"User-Agent": "FortWatch-public-audio-evaluation"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise RuntimeError(f"Public file exceeds the download limit: {url}")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    metadata = fetch(BASE + "meta/esc50.csv", 500_000)
    license_data = fetch(BASE + "LICENSE", 1_000_000)
    (output / "esc50.csv").write_bytes(metadata)
    (output / "ESC50-LICENSE.txt").write_bytes(license_data)
    license_lines = license_data.decode().splitlines()
    rows = list(csv.DictReader(io.StringIO(metadata.decode())))
    chosen = []
    for category in CATEGORIES:
        seen = set()
        for row in sorted((r for r in rows if r["category"] == category), key=lambda r: r["filename"]):
            if row["src_file"] in seen:
                continue
            seen.add(row["src_file"])
            chosen.append(row)
            if len(seen) == 2:
                break
        if len(seen) != 2:
            raise RuntimeError(f"Expected two independent source clips for {category}")

    def download(row):
        url = BASE + "audio/" + row["filename"]
        # ESC-50 clips are five seconds of mono PCM; each is under 450 KB.
        data = fetch(url, 500_000)
        path = output / row["filename"]
        path.write_bytes(data)
        key = "- [" + "-".join(row["filename"].split("-")[:3]) + ".ogg]:"
        attribution = next(line for line in license_lines if line.startswith(key))
        return dict(row, url=url, path=str(path), bytes=len(data),
                    sha256=hashlib.sha256(data).hexdigest(), attribution=attribution)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        clips = list(pool.map(download, chosen))
    manifest = {
        "dataset": "ESC-50", "repository": "https://github.com/karolpiczak/ESC-50",
        "commit": COMMIT,
        "selection": "First two lexicographic filenames per category with distinct source IDs, chosen before inference.",
        "license_url": BASE + "LICENSE", "metadata_url": BASE + "meta/esc50.csv",
        "license_summary": "ESC-50 CC BY-NC; ESC-10 subset CC BY. Individual source attributions retained. Temporary evaluation only.",
        "total_audio_bytes": sum(clip["bytes"] for clip in clips), "clips": clips,
    }
    (output / "evaluation-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Fetched {len(clips)} clips; {manifest['total_audio_bytes']} audio bytes; no app assets modified.")


if __name__ == "__main__":
    main()
