#pragma once

// One motor: patterns identify the sound type, never its direction.
// Durations alternate ON/OFF in milliseconds, start/end ON, then a zero sentinel.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include "sound_catalog.h"

namespace fortwatch {

struct HapticPattern {
  const char *event;
  const char *label;
  const uint16_t *durations;
  uint8_t durationCount;  // excludes terminal zero; odd, or zero for quiet
};

constexpr uint16_t kAlarmPulses[] = {400, 150, 400, 150, 400, 0};
constexpr uint16_t kCarHornPulses[] = {650, 200, 650, 0};
constexpr uint16_t kGlassPulses[] = {150, 120, 150, 120, 150, 0};
constexpr uint16_t kShoutPulses[] = {450, 180, 150, 180, 450, 0};
constexpr uint16_t kBabyPulses[] = {150, 180, 500, 180, 150, 0};
constexpr uint16_t kKnockPulses[] = {150, 120, 150, 0};
constexpr uint16_t kDoorbellPulses[] = {500, 180, 150, 0};
constexpr uint16_t kPhonePulses[] = {150, 120, 150, 400, 150, 120, 150, 0};
constexpr uint16_t kDogPulses[] = {150, 120, 150, 180, 500, 0};
constexpr uint16_t kSpeechPulses[] = {150, 0};
constexpr uint16_t kBootPulses[] = {80, 0};
constexpr uint16_t kMachinePulses[] = {350, 150, 350, 0};
constexpr uint16_t kMusicPulses[] = {150, 120, 150, 120, 150, 120, 150, 0};
constexpr uint16_t kNaturePulses[] = {650, 0};
constexpr uint16_t kOtherPulses[] = {300, 0};
constexpr uint16_t kQuietPulses[] = {0};

template <std::size_t N>
constexpr HapticPattern makeHapticPattern(const char *event, const char *label,
                                         const uint16_t (&durations)[N]) {
  return {event, label, durations, static_cast<uint8_t>(N - 1)};
}

constexpr HapticPattern kEventHaptics[] = {
    makeHapticPattern("ALARM", "Three long pulses", kAlarmPulses),
    makeHapticPattern("CAR_HORN", "Two long pulses", kCarHornPulses),
    makeHapticPattern("GLASS", "Three short pulses", kGlassPulses),
    makeHapticPattern("SHOUT", "Long - short - long", kShoutPulses),
    makeHapticPattern("BABY", "Short - long - short", kBabyPulses),
    makeHapticPattern("KNOCK", "Two short pulses", kKnockPulses),
    makeHapticPattern("DOORBELL", "Long - short", kDoorbellPulses),
    makeHapticPattern("PHONE", "Double - pause - double", kPhonePulses),
    makeHapticPattern("DOG", "Short - short - long", kDogPulses),
    makeHapticPattern("SPEECH", "One short pulse", kSpeechPulses),
};
constexpr std::size_t kEventHapticCount = sizeof(kEventHaptics) / sizeof(kEventHaptics[0]);
constexpr HapticPattern kFamilyHaptics[] = {
    makeHapticPattern("HUMAN", "One short pulse", kSpeechPulses),
    makeHapticPattern("ANIMAL", "Two short - one long", kDogPulses),
    makeHapticPattern("VEHICLE", "Two long pulses", kCarHornPulses),
    makeHapticPattern("HOUSEHOLD", "Two short pulses", kKnockPulses),
    makeHapticPattern("MACHINE", "Two medium pulses", kMachinePulses),
    makeHapticPattern("MUSIC", "Four short pulses", kMusicPulses),
    makeHapticPattern("NATURE", "One long pulse", kNaturePulses),
    makeHapticPattern("OTHER", "One medium pulse", kOtherPulses),
};
constexpr std::size_t kFamilyHapticCount = sizeof(kFamilyHaptics) / sizeof(kFamilyHaptics[0]);
constexpr HapticPattern kQuietHaptics = makeHapticPattern("QUIET", "No vibration", kQuietPulses);
constexpr HapticPattern kUnknownHaptics = makeHapticPattern("UNKNOWN", "One short pulse", kSpeechPulses);
constexpr HapticPattern kFeedbackHaptics = makeHapticPattern("FEEDBACK", "One short pulse", kSpeechPulses);
constexpr HapticPattern kBootHaptics = makeHapticPattern("BOOT", "Motor check", kBootPulses);

inline const HapticPattern *hapticsForKey(const char *event) {
  if (!event) return nullptr;
  for (const HapticPattern &pattern : kEventHaptics)
    if (std::strcmp(event, pattern.event) == 0) return &pattern;
  for (const HapticPattern &pattern : kFamilyHaptics)
    if (std::strcmp(event, pattern.event) == 0) return &pattern;
  return nullptr;
}

inline const HapticPattern *knownHapticsForEvent(const char *event) {
  if (!event) return nullptr;
  if (const SoundCatalogEntry *entry = lookupSoundCatalog(event))
    return entry->isQuiet ? &kQuietHaptics : hapticsForKey(entry->hapticEvent);
  // Families are display/haptic groupings, not additional wire event IDs.
  for (const HapticPattern &pattern : kEventHaptics)
    if (std::strcmp(event, pattern.event) == 0) return &pattern;
  return nullptr;
}

inline const HapticPattern &hapticsForEvent(const char *event) {
  const HapticPattern *known = knownHapticsForEvent(event);
  return known ? *known : kUnknownHaptics;
}

inline bool sameHapticRhythm(const HapticPattern &a, const HapticPattern &b) {
  return a.durationCount == b.durationCount &&
         std::memcmp(a.durations, b.durations, a.durationCount * sizeof(uint16_t)) == 0;
}

// Manual training command, kept separate from real E alerts and their analytics.
inline bool parsePatternTest(const char *text, const HapticPattern *&output) {
  output = nullptr;
  if (!text) return false;
  std::size_t length = 0;
  while (length <= 63 && text[length]) ++length;
  if (length < 3 || length > 63 || text[0] != 'P' || text[1] != ',') return false;
  output = knownHapticsForEvent(text + 2);  // exact match rejects extra fields/space
  return output != nullptr;
}

}  // namespace fortwatch
