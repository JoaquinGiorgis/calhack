#include "../fortwatch_display/event_haptics.h"

#include <cassert>
#include <iostream>
#include <set>
#include <string>
#include <vector>

int main() {
  using namespace fortwatch;
  assert(kEventHapticCount == 10);
  std::set<std::string> names;
  std::set<std::vector<uint16_t>> patterns;
  for (const HapticPattern &pattern : kEventHaptics) {
    assert(names.insert(pattern.event).second);
    assert(pattern.label && *pattern.label);
    assert(pattern.durationCount > 0 && pattern.durationCount <= 7);
    assert(pattern.durationCount % 2 == 1);
    assert(pattern.durations[pattern.durationCount] == 0);
    std::vector<uint16_t> durations;
    unsigned total = 0;
    for (uint8_t i = 0; i < pattern.durationCount; ++i) {
      assert(pattern.durations[i] >= 80 && pattern.durations[i] <= 650);
      total += pattern.durations[i];
      durations.push_back(pattern.durations[i]);
    }
    assert(total <= 2500);
    assert(patterns.insert(durations).second);  // all ten types feel different
    assert(knownHapticsForEvent(pattern.event) == &pattern);
    const HapticPattern *parsed = nullptr;
    assert(parsePatternTest((std::string("P,") + pattern.event).c_str(), parsed));
    assert(parsed == &pattern);
  }

  const auto &knock = hapticsForEvent("KNOCK");
  assert(knock.durationCount == 3);
  assert(knock.durations[0] == 150 && knock.durations[1] == 120 && knock.durations[2] == 150);
  assert(hapticsForEvent("WATER_TAP").durationCount == 1);
  assert(hapticsForEvent(nullptr).durations[0] == 150);
  assert(kBootHaptics.durationCount == 1 && kBootHaptics.durations[0] == 80);
  assert(kFeedbackHaptics.durationCount == 1 && kFeedbackHaptics.durations[0] == 150);
  const uint16_t clonedDog[] = {150, 120, 150, 180, 500, 0};
  const HapticPattern clone = makeHapticPattern("CLONE", "Same rhythm, different storage", clonedDog);
  assert(sameHapticRhythm(hapticsForEvent("DOG"), clone));
  assert(!sameHapticRhythm(hapticsForEvent("DOG"), knock));
  assert(!knownHapticsForEvent("alarm"));
  assert(!knownHapticsForEvent("UNKNOWN"));

  const char *invalid[] = {nullptr, "", "P", "P,", "P,UNKNOWN", "P,alarm", "E,KNOCK",
                          "P, KNOCK", "P,KNOCK ", "P,KNOCK,", "P,KNOCK,1",
                          "P,KNOCK\n", "P,KNOCK\r", "PP,KNOCK", "P,KNOCK,DOG"};
  for (const char *wire : invalid) {
    const HapticPattern *parsed = &knock;
    assert(!parsePatternTest(wire, parsed));
    assert(parsed == nullptr);  // rejection must not retain a previous test
  }
  std::string overlong = "P,KNOCK" + std::string(64, 'X');
  const HapticPattern *parsed = &knock;
  assert(!parsePatternTest(overlong.c_str(), parsed) && parsed == nullptr);
  std::cout << "PASS: ten unique bounded haptic patterns; boot/toggle/knock preserved; strict P test protocol\n";
}
