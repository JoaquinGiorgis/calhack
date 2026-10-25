#!/usr/bin/env python3
"""Compare compiled iPhone/wristband rhythms for legacy events and all 521 IDs."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LEGACY = ["ALARM", "CAR_HORN", "GLASS", "SHOUT", "BABY", "KNOCK", "DOORBELL", "PHONE", "DOG", "SPEECH"]


def run(*args):
    return subprocess.check_output(args, text=True)


def main():
    with tempfile.TemporaryDirectory(prefix="fortwatch-haptics-") as directory:
        temp = Path(directory)
        swift = temp / "main.swift"
        swift.write_text('''import Foundation
let legacy = ["ALARM", "CAR_HORN", "GLASS", "SHOUT", "BABY", "KNOCK", "DOORBELL", "PHONE", "DOG", "SPEECH"]
for invalid in ["Y", "Y0", "Y00", "Y0000", "Y00A", "Y-01", "Y521", "Y999"] {
    precondition(SoundCatalog.forEvent(invalid) == nil)
}
let events = legacy + SoundCatalog.all.map(\\.event)
let patterns = Dictionary(uniqueKeysWithValues: events.map { ($0, SoundHapticPattern.forEvent($0).segments) })
let data = try JSONSerialization.data(withJSONObject: patterns, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
''')
        cpp = temp / "main.cpp"
        cpp.write_text('''#include <cassert>
#include <cstdio>
#include <iostream>
#include <string>
#include "alert_protocol.h"
#include "event_haptics.h"
void printPattern(const char *event, const fortwatch::HapticPattern &p) {
  std::cout << "\\\"" << event << "\\\":[";
  for (int j = 0; j < p.durationCount; ++j) {
    if (j) std::cout << ",";
    std::cout << p.durations[j];
  }
  std::cout << "]";
}
int main() {
  for (const char *id : {"Y", "Y0", "Y00", "Y0000", "Y00A", "Y-01", "Y521", "Y999"}) {
    assert(!lookupSoundCatalog(id));
    fortwatch::AlertMessage alert;
    assert(!fortwatch::parseAlert((std::string("E,") + id + ",0.9").c_str(), alert));
    const fortwatch::HapticPattern *pattern = nullptr;
    assert(!fortwatch::parsePatternTest((std::string("P,") + id).c_str(), pattern));
  }
  std::cout << "{";
  for (size_t i = 0; i < fortwatch::kEventHapticCount; ++i) {
    if (i) std::cout << ",";
    printPattern(fortwatch::kEventHaptics[i].event, fortwatch::kEventHaptics[i]);
  }
  for (unsigned i = 0; i < SOUND_CATALOG_COUNT; ++i) {
    char event[5]; snprintf(event, sizeof(event), "Y%03u", i);
    const auto *pattern = fortwatch::knownHapticsForEvent(event);
    assert(pattern); std::cout << ","; printPattern(event, *pattern);
  }
  std::cout << "}\\n";
}
''')
        run("xcrun", "swiftc", str(ROOT / "ios/FortWatchListener/SoundCatalog.swift"),
            str(ROOT / "ios/FortWatchListener/SoundHaptics.swift"), str(swift), "-o", str(temp / "ios"))
        run("xcrun", "clang++", "-std=c++11", "-I", str(ROOT / "live_demo/fortwatch_display"),
            str(cpp), "-o", str(temp / "firmware"))
        ios = json.loads(run(str(temp / "ios")))
        firmware = json.loads(run(str(temp / "firmware")))
        differences = {event: (ios.get(event), firmware.get(event))
                       for event in ios.keys() | firmware.keys() if ios.get(event) != firmware.get(event)}
        assert not differences, f"Rhythm contract differs: {differences}"
        assert len(ios) == 531
        assert len({tuple(ios[event]) for event in LEGACY}) == 10
        assert ios["Y494"] == []
        print("PASS: 10 legacy and all 521 catalog iOS/firmware rhythms match; exact ID validation and quiet class checked.")


if __name__ == "__main__":
    main()
