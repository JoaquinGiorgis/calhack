#pragma once

// One motor: patterns identify the sound type, never its direction.
// Durations alternate ON/OFF in milliseconds, start/end ON, then a zero sentinel.
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace fortwatch {

struct HapticPattern {
  const char *event;
  const char *label;
  const uint16_t *durations;
  uint8_t durationCount;  // excludes the terminal zero; always odd
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
constexpr HapticPattern kUnknownHaptics = makeHapticPattern("UNKNOWN", "One short pulse", kSpeechPulses);
constexpr HapticPattern kFeedbackHaptics = makeHapticPattern("FEEDBACK", "One short pulse", kSpeechPulses);
constexpr HapticPattern kBootHaptics = makeHapticPattern("BOOT", "Motor check", kBootPulses);

inline const HapticPattern *knownHapticsForEvent(const char *event) {
  if (!event) return nullptr;
  for (const HapticPattern &pattern : kEventHaptics)
    if (std::strcmp(event, pattern.event) == 0) return &pattern;
  return nullptr;
}

inline const HapticPattern &hapticsForEvent(const char *event) {
  const HapticPattern *known = knownHapticsForEvent(event);
  return known ? *known : kUnknownHaptics;
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
