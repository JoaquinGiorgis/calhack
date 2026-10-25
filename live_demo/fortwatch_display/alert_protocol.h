#pragma once

// Shared by the ESP32 sketch and the host parser tests. No Arduino dependencies.
// E,<event>,<classification score>[,<phone-relative degrees>,<direction quality>]
// Positive angles point right; 0 is ahead of the phone and +/-180 is behind it.
// Direction quality is a heuristic coherence indicator, not a probability or
// a calibrated statement of angular accuracy.
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include "sound_catalog.h"

namespace fortwatch {

constexpr std::size_t kMaxMessageLength = 63;
constexpr std::size_t kMaxEventLength = 23;
constexpr float kMinimumDirectionQuality = 0.60f;

struct AlertMessage {
  char event[kMaxEventLength + 1] = {};
  float score = 0;
  bool hasDirection = false;
  float angleDegrees = 0;
  float directionQuality = 0;
};

inline bool parseFiniteNumber(const char *text, float minimum, float maximum,
                              float &result) {
  if (!text || !*text) return false;
  // strtof accepts leading whitespace; the wire format deliberately does not.
  for (const char *p = text; *p; ++p) {
    if (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n' ||
        *p == '\v' || *p == '\f') return false;
  }
  char *end = nullptr;
  float value = std::strtof(text, &end);
  if (end == text || *end != '\0' || !std::isfinite(value) ||
      value < minimum || value > maximum) return false;
  result = value;
  return true;
}

inline bool parseSoundMessage(const char *text, AlertMessage &output, char kind) {
  // Reset on every attempt: a legacy/invalid message never inherits an angle.
  output = AlertMessage{};
  if (!text) return false;
  std::size_t length = 0;
  while (length <= kMaxMessageLength && text[length]) ++length;
  if (length > kMaxMessageLength) return false;

  char buffer[kMaxMessageLength + 1];
  std::memcpy(buffer, text, length + 1);
  char *fields[6] = {buffer};
  std::size_t count = 1;
  for (char *p = buffer; *p; ++p) {
    if (*p != ',') continue;
    *p = '\0';
    if (count < 6) fields[count] = p + 1;
    ++count;
  }
  if (count < 3 || fields[0][0] != kind || fields[0][1] != '\0') return false;
  const std::size_t eventLength = std::strlen(fields[1]);
  if (!eventLength || eventLength > kMaxEventLength) return false;
  for (const char *p = fields[1]; *p; ++p) {
    if (!((*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_'))
      return false;
  }
  // Y is reserved for exact YAMNet IDs; never treat a malformed ID as a label.
  if (fields[1][0] == 'Y' && !lookupSoundCatalog(fields[1])) return false;

  AlertMessage parsed;
  if (!parseFiniteNumber(fields[2], 0.0f, 1.0f, parsed.score)) return false;
  std::memcpy(parsed.event, fields[1], eventLength + 1);
  // Bad optional metadata must not suppress an otherwise valid sound alert.
  // Partial/extra fields, nonfinite values and out-of-range values mean unknown.
  if (count == 5) {
    float angle = 0, quality = 0;
    if (parseFiniteNumber(fields[3], -180.0f, 180.0f, angle) &&
        parseFiniteNumber(fields[4], 0.0f, 1.0f, quality)) {
      parsed.hasDirection = true;
      parsed.angleDegrees = angle;
      parsed.directionQuality = quality;
    }
  }
  output = parsed;
  return true;
}

inline bool parseAlert(const char *text, AlertMessage &output) {
  return parseSoundMessage(text, output, 'E');
}

// D has the same validated payload as E, but is display-only at dispatch.
inline bool parseDisplay(const char *text, AlertMessage &output) {
  return parseSoundMessage(text, output, 'D');
}

inline bool hasUsableDirection(const AlertMessage &message) {
  return message.hasDirection &&
         message.directionQuality >= kMinimumDirectionQuality;
}

}  // namespace fortwatch
