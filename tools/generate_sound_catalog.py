#!/usr/bin/env python3
"""Generate the offline FortWatch catalog from YAMNet's exact class map.

Run with --ontology /path/to/ontology.json to refresh the compact AudioSet graph.
Otherwise the graph in shared/sound_catalog.json makes generation offline.
The source ontology is CC BY-SA 4.0; names/ancestry retain its attribution.
UI families and shortened titles are FortWatch presentation choices, not new
model labels or claims that all classes have equal recognition accuracy.
"""
import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "pretrained/yamnet/assets/yamnet_class_map.csv"
CATALOG = ROOT / "shared/sound_catalog.json"
SWIFT = ROOT / "ios/FortWatchListener/SoundCatalog.swift"
HEADER = ROOT / "live_demo/fortwatch_display/sound_catalog.h"

# Priority resolves ontology nodes with several parents into one UI family.
FAMILIES = {
    "HUMAN": ("People", "/m/0dgw9r", "person.wave.2", 0x1F6539, 0xA5EAC5),
    "ANIMAL": ("Animals", "/m/0jbk", "pawprint", 0x81501C, 0xF2CFA3),
    "NATURE": ("Nature", "/m/059j3w", "leaf", 0x126B67, 0x8EE9DD),
    "VEHICLE": ("Vehicles", "/m/07yv9", "car.side", 0xA84408, 0xFFBA83),
    "HOUSEHOLD": ("Home", "/t/dd00071", "house", 0x1E4DD4, 0xA5BFFF),
    "MUSIC": ("Music", "/m/04rlf", "music.note", 0x652BC2, 0xCFAEFF),
    "MACHINE": ("Devices & machines", None, "gearshape", 0x485970, 0xC6D9F3),
    "OTHER": ("Other sounds", None, "waveform", 0x48515F, 0xE2E7EE),
}
MACHINE_ROOTS = {"/m/02mk9", "/t/dd00077", "/m/07k1x", "/m/07pp_mv", "/t/dd00091"}
LEGACY = {
    "ALARM": ("light.beacon.max", 0xB92131, 0xFF94A0),
    "CAR_HORN": ("car.side", 0xA84408, 0xFFBA83),
    "GLASS": ("wineglass", 0xA32555, 0xFFAAC9),
    "SHOUT": ("megaphone", 0xA3256D, 0xFCACE0),
    "BABY": ("figure.child", 0x126B67, 0x8EE9DD),
    "KNOCK": ("door.left.hand.closed", 0x1E4DD4, 0xA5BFFF),
    "DOORBELL": ("bell", 0x652BC2, 0xCFAEFF),
    "PHONE": ("phone", 0x485970, 0xC6D9F3),
    "DOG": ("dog", 0x81501C, 0xF2CFA3),
    "SPEECH": ("text.bubble", 0x1F6539, 0xA5EAC5),
}
TITLE_OVERRIDES = {
    "Inside, small room": "Inside a small room",
    "Inside, large room or hall": "Inside a large room or hall",
    "Inside, public space": "Inside a public space",
    "Outside, urban or manmade": "Outside in an urban area",
    "Outside, rural or natural": "Outside in nature",
    "Child speech, kid speaking": "Child speech",
    "Baby cry, infant cry": "Baby crying",
    "Vehicle horn, car horn, honking": "Vehicle horn",
    "Domestic animals, pets": "Domestic animals",
    "Livestock, farm animals, working animals": "Livestock and farm animals",
    "Wind instrument, woodwind instrument": "Wind instrument",
    "Medium engine (mid frequency)": "Medium engine",
    "Light engine (high frequency)": "Light engine",
    "Heavy engine (low frequency)": "Heavy engine",
    "Fire engine, fire truck (siren)": "Fire engine siren",
    "Chop": "Chop",
}


def build(ontology):
    parents = {node["id"]: [] for node in ontology}
    for node in ontology:
        for child in node["children"]:
            parents.setdefault(child, []).append(node["id"])
    cache = {}

    def ancestors(mid):
        if mid not in cache:
            result = set(parents.get(mid, []))
            for parent in list(result):
                result.update(ancestors(parent))
            cache[mid] = result
        return cache[mid]

    rows = list(csv.DictReader(CSV.open()))
    assert len(rows) == 521 and [int(row["index"]) for row in rows] == list(range(521))
    index_by_mid = {row["mid"]: int(row["index"]) for row in rows}
    entries = []
    for row in rows:
        index, mid, name = int(row["index"]), row["mid"], row["display_name"]
        lineage = ancestors(mid) | {mid}
        family = next((key for key, (_, root, *_rest) in FAMILIES.items()
                       if root and root in lineage), None)
        family = family or ("MACHINE" if lineage & MACHINE_ROOTS else "OTHER")
        _, _, icon, color, signal = FAMILIES[family]
        haptic = family
        # Specific rhythms retain their existing learned meaning. Broad classes
        # keep the family rhythm, never masquerading as one of these events.
        special_roots = [
            ("/t/dd00002", "BABY"), ("/m/07p6fty", "SHOUT"), ("/m/03qc9zr", "SHOUT"),
            ("/m/09x0r", "SPEECH"), ("/m/0bt9lr", "DOG"),
            ("/m/03wwcy", "DOORBELL"), ("/m/07cx4", "PHONE"),
            ("/m/0912c9", "CAR_HORN"), ("/m/05x_td", "CAR_HORN"),
            ("/m/039jq", "GLASS"),
            ("/m/07r4wb8", "KNOCK"), ("/m/03kmc9", "ALARM"),
            ("/m/046dlr", "ALARM"), ("/m/01y3hg", "ALARM"),
            ("/m/0c3f7m", "ALARM"), ("/m/02mfyn", "ALARM"),
        ]
        for root, key in special_roots:
            if root in lineage:
                haptic = key
                break
        if name == "Knock":
            haptic = "KNOCK"
        if name == "Alarm":
            haptic = "ALARM"
        if name in {"Howl", "Growling"}:
            # These nodes also include wolves / cats. A dog glyph would imply
            # a source the classifier did not identify.
            haptic = "ANIMAL"
        if haptic in LEGACY:
            icon, color, signal = LEGACY[haptic]
        else:
            # Familiar symbols for meaningful subfamilies, shared across labels.
            icon_roots = [
                ("/m/01yrx", "cat"), ("/m/015p6", "bird"), ("/m/03vt0", "ant"),
                ("/m/0fx80y", "guitars"), ("/m/05148p4", "pianokeys"),
                ("/m/0395lw", "bell"), ("/m/06d_3", "tram"),
                ("/m/0k5j", "airplane"), ("/m/019jd", "ferry"),
                ("/m/0838f", "drop"), ("/m/03m9d0z", "wind"),
                ("/m/02_41", "flame"), ("/m/0jb2l", "cloud.bolt.rain"),
                ("/m/0bpl036", "figure.walk"), ("/m/0k65p", "hands.clap"),
                ("/m/01j3sz", "face.smiling"), ("/m/07k1x", "wrench.and.screwdriver"),
                ("/m/014zdl", "burst"), ("/m/02dgv", "door.left.hand.closed"),
            ]
            icon = next((symbol for root, symbol in icon_roots if root in lineage), icon)
        quiet = mid == "/m/028v0c"
        if quiet:
            icon, haptic = "speaker.slash", "QUIET"
        title = TITLE_OVERRIDES.get(name, name.split(", ")[0])
        assert title.isascii() and name.isascii(), (index, name)
        entries.append(dict(event=f"Y{index:03d}", index=index, mid=mid, name=name,
                            title=title, family=family, icon=icon, colorHex=color,
                            signalHex=signal, hapticEvent=haptic, isQuiet=quiet,
                            parentIndices=sorted(index_by_mid[p] for p in ancestors(mid) if p in index_by_mid)))
    return entries


def swift(entries):
    q = lambda value: json.dumps(value, ensure_ascii=True)
    lines = ["// Generated by tools/generate_sound_catalog.py; do not edit by hand.",
             "// Exact names: YAMNet class map. Ancestry: AudioSet, CC BY-SA 4.0.",
             "// https://github.com/audioset/ontology — UI families are FortWatch choices.",
             "import Foundation", "", "enum SoundCatalog {", "    struct Entry: Identifiable, Equatable, Sendable {",
             "        let event: String", "        let index: Int", "        let mid: String",
             "        let name: String", "        let title: String", "        let family: String",
             "        let icon: String", "        let colorHex: UInt32", "        let signalHex: UInt32",
             "        let hapticEvent: String", "        let isQuiet: Bool", "        let parentIndices: [Int]",
             "        var id: String { event }", "        var familyTitle: String { SoundCatalog.familyTitle(for: family) }",
             "    }", "", "    static let families = [" + ", ".join(q(k) for k in FAMILIES) + "]",
             "    static func familyTitle(for key: String) -> String {", "        switch key {"]
    lines += [f"        case {q(key)}: return {q(value[0])}" for key, value in FAMILIES.items()]
    lines += ["        default: return \"Other sounds\"", "        }", "    }", "",
              "    static func forEvent(_ event: String) -> Entry? {",
              "        let bytes = Array(event.utf8)",
              "        guard bytes.count == 4, bytes[0] == 89, bytes.dropFirst().allSatisfy({ (48...57).contains($0) }) else { return nil }",
              "        let index = Int(bytes[1] - 48) * 100 + Int(bytes[2] - 48) * 10 + Int(bytes[3] - 48)",
              "        return all.indices.contains(index) ? all[index] : nil", "    }", "", "    static let all: [Entry] = ["]
    for e in entries:
        fields = [f"{key}: {q(e[key])}" for key in ["event"]]
        fields += [f"index: {e['index']}"]
        fields += [f"{key}: {q(e[key])}" for key in ["mid", "name", "title", "family", "icon"]]
        fields += [f"colorHex: 0x{e['colorHex']:06X}", f"signalHex: 0x{e['signalHex']:06X}",
                   f"hapticEvent: {q(e['hapticEvent'])}", f"isQuiet: {str(e['isQuiet']).lower()}",
                   "parentIndices: " + json.dumps(e['parentIndices'])]
        lines.append("        Entry(" + ", ".join(fields) + "),")
    return "\n".join(lines + ["    ]", "}", ""])


def header(entries):
    q = lambda value: json.dumps(value, ensure_ascii=True)
    lines = ["// Generated by tools/generate_sound_catalog.py; do not edit by hand.",
             "// Exact YAMNet labels; ancestry derived from AudioSet (CC BY-SA 4.0).",
             "// https://github.com/audioset/ontology", "#pragma once", "#include <stddef.h>", "#include <stdint.h>", "",
             "struct SoundCatalogEntry {", "  const char *name;", "  const char *title;", "  const char *family;",
             "  const char *hapticEvent;", "  uint32_t colorHex;", "  uint32_t signalHex;", "  bool isQuiet;", "};",
             "static constexpr size_t SOUND_CATALOG_COUNT = 521;", "static const SoundCatalogEntry SOUND_CATALOG[521] = {"]
    for e in entries:
        lines.append("  {" + ", ".join([q(e[k]) for k in ["name", "title", "family", "hapticEvent"]] +
                                      [f"0x{e['colorHex']:06X}", f"0x{e['signalHex']:06X}", str(e['isQuiet']).lower()]) + "},")
    lines += ["};", "", "static inline const SoundCatalogEntry *lookupSoundCatalog(const char *event) {",
              "  if (!event || event[0] != 'Y') return nullptr;",
              "  unsigned index = 0;", "  for (unsigned i = 1; i <= 3; ++i) {",
              "    if (event[i] < '0' || event[i] > '9') return nullptr;",
              "    index = index * 10 + unsigned(event[i] - '0');", "  }",
              "  if (event[4] != '\\0' || index >= SOUND_CATALOG_COUNT) return nullptr;",
              "  return &SOUND_CATALOG[index];", "}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ontology", type=Path)
    args = parser.parse_args()
    if args.ontology:
        raw = json.loads(args.ontology.read_text())
        graph = [dict(id=n["id"], name=n["name"], children=n["child_ids"]) for n in raw]
    else:
        graph = json.loads(CATALOG.read_text())["ontology"]["nodes"]
    entries = build(graph)
    document = dict(schema_version=1, model="YAMNet", class_map=str(CSV.relative_to(ROOT)),
                    ontology=dict(source="https://github.com/audioset/ontology", attribution="Google Inc. / AudioSet",
                                  license="CC BY-SA 4.0", nodes=graph),
                    family_titles={k: v[0] for k, v in FAMILIES.items()}, entries=entries)
    CATALOG.parent.mkdir(exist_ok=True)
    CATALOG.write_text(json.dumps(document, indent=2, ensure_ascii=True) + "\n")
    SWIFT.write_text(swift(entries))
    HEADER.write_text(header(entries))
    counts = {key: sum(e['family'] == key for e in entries) for key in FAMILIES}
    print(f"Generated {len(entries)} classes: {counts}")
    print(f"Maximum title length {max(len(e['title']) for e in entries)}; exact name length {max(len(e['name']) for e in entries)}")


if __name__ == "__main__":
    main()
