#!/usr/bin/env python3
"""Verify firmware dashboard compatibility against the real Mac EVENTS + CSV."""
import ast
import csv
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    tree = ast.parse((ROOT / "live_demo/mac_listener.py").read_text())
    literals = {}
    events_node = None
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "KNOCK_CLASSES":
                    literals[target.id] = ast.literal_eval(node.value)
                if isinstance(target, ast.Name) and target.id == "EVENTS":
                    events_node = node.value
    assert isinstance(events_node, ast.Dict)
    classes = {}
    for key, call in zip(events_node.keys, events_node.values):
        event = ast.literal_eval(key)
        arg = call.args[0]
        if isinstance(arg, ast.Call):
            assert isinstance(arg.func, ast.Name) and arg.func.id == "list"
            names = literals[arg.args[0].id]
        else:
            names = ast.literal_eval(arg)
        for name in names:
            assert name not in classes, f"Ambiguous original Mac class: {name}"
            classes[name] = event
    with (ROOT / "pretrained/yamnet/assets/yamnet_class_map.csv").open() as file:
        rows = list(csv.DictReader(file))
    expected = {f"Y{int(row['index']):03d}": classes[row["display_name"]]
                for row in rows if row["display_name"] in classes}
    assert len(expected) == len(classes) == 36
    with tempfile.TemporaryDirectory(prefix="fortwatch-dashboard-contract-") as directory:
        temp = Path(directory)
        source = temp / "contract.cpp"
        source.write_text(r'''#include <cassert>
#include <cstdio>
#include <cstring>
#include <iostream>
#include "analytics_compatibility.h"
int main() {
  assert(!fortwatch::dashboardEventForAlert(nullptr));
  assert(!fortwatch::dashboardEventForAlert("Y521"));
  assert(!fortwatch::dashboardEventForAlert("Y0000"));
  assert(!fortwatch::dashboardEventForAlert("Y494"));
  assert(!fortwatch::dashboardEventForAlert("Y001"));
  assert(std::strcmp(fortwatch::dashboardEventForAlert("ALARM"), "ALARM") == 0);
  assert(std::strcmp(fortwatch::dashboardEventForAlert("WATER_TAP"), "WATER_TAP") == 0);
  bool comma = false;
  std::cout << "{";
  for (unsigned i = 0; i < SOUND_CATALOG_COUNT; ++i) {
    char event[5]; std::snprintf(event, sizeof(event), "Y%03u", i);
    if (const char *mapped = fortwatch::dashboardEventForAlert(event)) {
      if (comma) std::cout << ",";
      std::cout << "\"" << event << "\":\"" << mapped << "\"";
      comma = true;
    }
  }
  std::cout << "}\n";
}
''')
        subprocess.run(["xcrun", "clang++", "-std=c++11", "-fsanitize=address,undefined",
                        "-I", str(ROOT / "live_demo/fortwatch_display"), str(source),
                        "-o", str(temp / "contract")], check=True)
        actual = json.loads(subprocess.check_output([str(temp / "contract")], text=True))
    assert actual == expected, f"Dashboard mapping differs: {actual} vs {expected}"
    print("PASS: exactly 36 original Mac classes map to legacy dashboard events; 485 new classes stay local; legacy uploads unchanged.")


if __name__ == "__main__":
    main()
