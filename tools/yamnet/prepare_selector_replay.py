#!/usr/bin/env python3
"""Export lossless CoreML score traces and capture-window timing; no model load."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from scipy.io import wavfile

TARGET_NAMES = {
    "glass_breaking": ["Glass", "Shatter"],
    "car_horn": ["Vehicle horn, car horn, honking", "Air horn, truck horn"],
    "siren": ["Siren", "Civil defense siren", "Police car (siren)", "Ambulance (siren)", "Fire engine, fire truck (siren)"],
    "clock_alarm": ["Alarm clock"],
    "crying_baby": ["Baby cry, infant cry"],
    "door_wood_knock": ["Knock"],
    "dog": ["Dog", "Bark", "Bow-wow"],
    "cat": ["Cat", "Meow", "Purr", "Caterwaul"],
    "rain": ["Rain", "Raindrop", "Rain on surface"],
    "footsteps": ["Walk, footsteps"],
    "clapping": ["Clapping", "Applause"],
    "coughing": ["Cough", "Throat clearing"],
    # YAMNet's exact class map has no washing-machine-specific label.
    "washing_machine": [],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scores", type=Path, required=True)
    parser.add_argument("--public-manifest", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.scores.read_text())
    source = json.loads(args.public_manifest.read_text())
    source_by_name = {clip["filename"]: clip for clip in source["clips"]}
    labels = report["output"]["labels"]
    assert len(labels) == 521
    index_by_name = {name: index for index, name in enumerate(labels)}
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    packed = bytearray()
    clips = []
    for clip in report["clips"]:
        public = source_by_name[clip["filename"]]
        source_path = Path(public["path"])
        assert hashlib.sha256(source_path.read_bytes()).hexdigest() == public["sha256"]
        rate, audio = wavfile.read(source_path)
        assert audio.ndim == 1 and np.issubdtype(audio.dtype, np.signedinteger)
        divisor = float(max(abs(np.iinfo(audio.dtype).min), np.iinfo(audio.dtype).max + 1))
        audio = audio.astype(np.float64) / divisor
        native_count = int(rate * 15600 / 16000 + 0.5)
        windows = []
        for window in clip["windows"]:
            offset = int(window["start_sample_16k"])
            native_start = int(offset * rate / 16000 + 0.5)
            segment = audio[native_start:native_start + native_count]
            assert len(segment) == native_count
            scores = window["coreml_scores"]
            assert len(scores) == 521 and all(np.isfinite(value) and 0 <= value <= 1 for value in scores)
            byte_offset = len(packed)
            packed.extend(struct.pack("<521f", *scores))
            windows.append({
                "startSample16k": offset,
                "nativeStartFrame": native_start,
                "nativeFrameCount": native_count,
                "capturedEndSeconds": (native_start + native_count) / rate,
                "modelEndSeconds": (offset + 15600) / 16000,
                "rms": float(np.sqrt(np.mean(segment * segment))),
                "scoreByteOffset": byte_offset,
            })
        category = clip["dataset_category"]
        clips.append({
            "filename": clip["filename"], "datasetCategory": category, "sourceRate": int(rate),
            "sourceURL": public["url"], "audioSHA256": public["sha256"],
            "attribution": public["attribution"],
            "targetIndices": [index_by_name[name] for name in TARGET_NAMES[category]],
            "targetNames": TARGET_NAMES[category], "windows": windows,
        })
    binary_name = "coreml-scores.f32le"
    (output / binary_name).write_bytes(packed)
    manifest = {
        "version": 1, "scoreCount": 521, "scoreFile": binary_name,
        "scoresSHA256": hashlib.sha256(packed).hexdigest(), "scoreBytes": len(packed),
        "labels": labels, "clips": clips, "datasetCommit": source["commit"],
        "sourceReportSHA256": hashlib.sha256(args.scores.read_bytes()).hexdigest(),
        "modelSummary": report["summary"],
        "method": "Original CoreML Float32 scores packed losslessly; native-source RMS and rounded975ms capture end follow production timing. Fresh selector per clip. No callback-arrival clock substitution.",
        "limits": [
            "Scores were produced offline after scipy resample_poly, not the app's AVAudioConverter.",
            "This replay does not execute CoreML, resampling, live TTL, microphone capture, BLE, or direction.",
            "Target labels are declared semantic comparators, not a complete human annotation of every sound in each clip.",
            "No washing-machine-specific class exists in the521-label YAMNet vocabulary.",
        ],
    }
    (output / "replay-input.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Exported {len(clips)} clips, {sum(len(c['windows']) for c in clips)} windows, {len(packed)} score bytes; no audio copied.")


if __name__ == "__main__":
    main()
