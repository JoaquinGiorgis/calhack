#include "../fortwatch_display/alert_protocol.h"
#include "../fortwatch_display/event_haptics.h"

#include <cassert>
#include <cstdio>
#include <iostream>
#include <set>
#include <string>
#include <vector>

int main() {
  using namespace fortwatch;
  assert(SOUND_CATALOG_COUNT == 521);
  std::set<std::vector<uint16_t>> familyRhythms;
  assert(kFamilyHapticCount == 8);
  for (const auto &pattern : kFamilyHaptics) {
    assert(pattern.durationCount > 0 && pattern.durationCount <= 7 && pattern.durationCount % 2 == 1);
    assert(pattern.durations[pattern.durationCount] == 0);
    unsigned total = 0;
    for (unsigned i = 0; i < pattern.durationCount; i++) total += pattern.durations[i];
    assert(total <= 2500);
    assert(familyRhythms.insert({pattern.durations, pattern.durations + pattern.durationCount}).second);
  }

  unsigned quietCount = 0;
  for (unsigned index = 0; index < SOUND_CATALOG_COUNT; index++) {
    char id[5], wire[64];
    snprintf(id, sizeof(id), "Y%03u", index);
    const auto *entry = lookupSoundCatalog(id);
    assert(entry == &SOUND_CATALOG[index]);
    assert(entry->name[0] && entry->title[0] && strlen(entry->title) < 48);
    for (const char *c = entry->title; *c; ++c) assert(*c >= 32 && *c <= 126);
    const auto *pattern = knownHapticsForEvent(id);
    assert(pattern);
    assert(pattern->durationCount == 0 ? entry->isQuiet : pattern->durationCount % 2 == 1);
    assert(pattern->durations[pattern->durationCount] == 0);
    if (entry->isQuiet) { quietCount++; assert(index == 494 && pattern == &kQuietHaptics); }
    snprintf(wire, sizeof(wire), "E,%s,0.625,-135,0.81", id);
    AlertMessage alert;
    assert(parseAlert(wire, alert) && strcmp(alert.event, id) == 0 && hasUsableDirection(alert));
    wire[0] = 'D';
    assert(parseDisplay(wire, alert) && strcmp(alert.event, id) == 0 && hasUsableDirection(alert));
    assert(!parseAlert(wire, alert));
    snprintf(wire, sizeof(wire), "P,%s", id);
    const HapticPattern *testPattern = nullptr;
    assert(parsePatternTest(wire, testPattern) && testPattern == pattern);
  }
  assert(quietCount == 1);

  for (const char *id : {"Y", "Y0", "Y00", "Y0000", "Y00A", "Y-01", "Y521", "Y999", "YABC"}) {
    assert(!lookupSoundCatalog(id));
    assert(!knownHapticsForEvent(id));
    AlertMessage alert;
    assert(!parseAlert((std::string("E,") + id + ",0.9").c_str(), alert));
    const HapticPattern *pattern = &kQuietHaptics;
    assert(!parsePatternTest((std::string("P,") + id).c_str(), pattern) && !pattern);
  }
  for (const char *wire : {"P,Y000,1", "P,Y000 ", "P,Y000\n", "P,HUMAN", "P,QUIET"}) {
    const HapticPattern *pattern = nullptr;
    assert(!parsePatternTest(wire, pattern));
  }
  AlertMessage fallback;
  assert(parseAlert("E,WATER_TAP,0.9", fallback));
  std::cout << "PASS: all 521 exact IDs, named catalog entries, haptic mappings, quiet, family uniqueness, malformed IDs and legacy fallback\n";
}
