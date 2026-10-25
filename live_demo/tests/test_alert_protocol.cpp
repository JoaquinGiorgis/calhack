#include "../fortwatch_display/alert_protocol.h"

#include <cassert>
#include <cmath>
#include <iostream>
#include <string>

using fortwatch::AlertMessage;
using fortwatch::hasUsableDirection;
using fortwatch::parseAlert;

static void expectUnknownDirection(const char *wire) {
  AlertMessage alert;
  // Start from a known angle to check that malformed metadata cannot retain it.
  assert(parseAlert("E,KNOCK,0.62,-35,0.81", alert));
  assert(hasUsableDirection(alert));
  assert(parseAlert(wire, alert));
  assert(std::string(alert.event) == "ALARM");
  assert(std::fabs(alert.score - 0.9f) < 0.00001f);
  assert(!alert.hasDirection);
  assert(!hasUsableDirection(alert));
  assert(alert.angleDegrees == 0 && alert.directionQuality == 0);
}

int main() {
  AlertMessage alert;
  assert(parseAlert("E,KNOCK,0.62,-35,0.81", alert));
  assert(std::string(alert.event) == "KNOCK");
  assert(std::fabs(alert.score - 0.62f) < 0.00001f);
  assert(alert.angleDegrees == -35 && hasUsableDirection(alert));
  assert(std::fabs(alert.directionQuality - 0.81f) < 0.00001f);

  // Legacy messages and damaged direction metadata still deliver the alert.
  const char *uncertain[] = {
      "E,ALARM,0.9", "E,ALARM,0.9,-35", "E,ALARM,0.9,,",
      "E,ALARM,0.9,-35,", "E,ALARM,0.9,,0.9", "E,ALARM,0.9,0,0.9,extra",
      "E,ALARM,0.9,nan,0.9", "E,ALARM,0.9,inf,0.9",
      "E,ALARM,0.9,-inf,0.9", "E,ALARM,0.9,181,0.9",
      "E,ALARM,0.9,-180.01,0.9", "E,ALARM,0.9,30,nan",
      "E,ALARM,0.9,30,inf", "E,ALARM,0.9,30,-0.1",
      "E,ALARM,0.9,30,1.01", "E,ALARM,0.9,30,0.9junk",
      "E,ALARM,0.9, 30,0.9", "E,ALARM,0.9,30,0.9 ",
  };
  for (const char *wire : uncertain) expectUnknownDirection(wire);

  // Unknown event names remain supported for the firmware's text fallback.
  assert(parseAlert("E,WATER_TAP,1,180,1", alert));
  assert(alert.angleDegrees == 180 && hasUsableDirection(alert));
  assert(parseAlert("E,ALARM,0,-180,0", alert));
  assert(alert.hasDirection && !hasUsableDirection(alert));
  assert(parseAlert("E,ALARM,0.9,0,0.60", alert));
  assert(hasUsableDirection(alert));
  assert(parseAlert("E,ALARM,0.9,0,0.59", alert));
  assert(!hasUsableDirection(alert));

  const char *invalid[] = {
      "", "E", "E,ALARM", "E,,0.9", "L,ALARM,0.9",
      "E,alarm,0.9", "E,AL ARM,0.9", "E,ALARM,", "E,ALARM,nan",
      "E,ALARM,inf", "E,ALARM,-inf", "E,ALARM,1e99", "E,ALARM,-0.1",
      "E,ALARM,1.01", "E,ALARM,0.9oops", "E,ALARM, 0.9",
      "E,ALARM,0.9\n", "E,ABCDEFGHIJKLMNOPQRSTUVWXYZ,0.9",
  };
  for (const char *wire : invalid) {
    assert(parseAlert("E,KNOCK,0.62,-35,0.81", alert));
    assert(!parseAlert(wire, alert));
    assert(!alert.hasDirection && alert.event[0] == '\0' && alert.score == 0);
  }
  assert(!parseAlert(nullptr, alert));

  // Exact transport limit accepted; a longer numeric prefix must not be clipped.
  std::string boundary = "E,ALARM,0.";
  boundary.append(fortwatch::kMaxMessageLength - boundary.size(), '0');
  assert(boundary.size() == 63);
  assert(parseAlert(boundary.c_str(), alert));
  boundary += '0';
  assert(!parseAlert(boundary.c_str(), alert));
  assert(!alert.hasDirection && alert.event[0] == '\0');

  std::cout << "PASS: alert protocol legacy, direction, uncertainty, invalid values, "
               "stale reset and 63-byte boundary\n";
}
