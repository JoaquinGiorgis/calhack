#!/usr/bin/env python3
"""Compare the compiled iPhone and wristband rhythm tables (macOS Swift + C++)."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args):
    return subprocess.check_output(args, text=True)


def main():
    with tempfile.TemporaryDirectory(prefix="fortwatch-haptics-") as directory:
        temp = Path(directory)
        swift = temp / "main.swift"
        swift.write_text('''import Foundation
let patterns = Dictionary(uniqueKeysWithValues: SoundHapticPattern.all.map { ($0.event, $0.segments) })
let data = try JSONSerialization.data(withJSONObject: patterns, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
''')
        cpp = temp / "main.cpp"
        cpp.write_text('''#include <iostream>
#include "event_haptics.h"
int main() {
  std::cout << "{";
  for (size_t i = 0; i < fortwatch::kEventHapticCount; ++i) {
    const auto &p = fortwatch::kEventHaptics[i];
    if (i) std::cout << ",";
    std::cout << "\\\"" << p.event << "\\\":[";
    for (int j = 0; j < p.durationCount; ++j) {
      if (j) std::cout << ",";
      std::cout << p.durations[j];
    }
    std::cout << "]";
  }
  std::cout << "}\\n";
}
''')
        run("xcrun", "swiftc", str(ROOT / "ios/FortWatchListener/SoundHaptics.swift"),
            str(swift), "-o", str(temp / "ios"))
        run("xcrun", "clang++", "-std=c++11", "-I", str(ROOT / "live_demo/fortwatch_display"),
            str(cpp), "-o", str(temp / "firmware"))
        ios = json.loads(run(str(temp / "ios")))
        firmware = json.loads(run(str(temp / "firmware")))
        assert ios == firmware, f"Rhythm contract differs:\niOS: {ios}\nFirmware: {firmware}"
        assert len(ios) == 10
        assert len({tuple(pattern) for pattern in ios.values()}) == 10
        print("PASS: all 10 compiled iOS and firmware vibration patterns match and are distinct.")


if __name__ == "__main__":
    main()
