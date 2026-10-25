#pragma once

// Preserve the existing dashboard's ten-event contract until its backend is
// expanded. These exact source classes match live_demo/mac_listener.py EVENTS;
// broader catalog ancestry/haptic families are deliberately not used here.
#include <cstddef>
#include <cstring>
#include "sound_catalog.h"

namespace fortwatch {
struct AnalyticsLegacyClass { const char *name; const char *event; };
constexpr AnalyticsLegacyClass kAnalyticsLegacyClasses[] = {
    {"Alarm", "ALARM"}, {"Alarm clock", "ALARM"},
    {"Smoke detector, smoke alarm", "ALARM"}, {"Fire alarm", "ALARM"},
    {"Car alarm", "ALARM"}, {"Buzzer", "ALARM"}, {"Siren", "ALARM"},
    {"Civil defense siren", "ALARM"}, {"Police car (siren)", "ALARM"},
    {"Ambulance (siren)", "ALARM"}, {"Fire engine, fire truck (siren)", "ALARM"},
    {"Vehicle horn, car horn, honking", "CAR_HORN"}, {"Air horn, truck horn", "CAR_HORN"},
    {"Glass", "GLASS"}, {"Shatter", "GLASS"}, {"Breaking", "GLASS"}, {"Smash, crash", "GLASS"},
    {"Shout", "SHOUT"}, {"Yell", "SHOUT"}, {"Screaming", "SHOUT"}, {"Children shouting", "SHOUT"},
    {"Baby cry, infant cry", "BABY"},
    {"Knock", "KNOCK"}, {"Door", "KNOCK"}, {"Wood", "KNOCK"}, {"Chop", "KNOCK"},
    {"Hammer", "KNOCK"}, {"Whack, thwack", "KNOCK"}, {"Tap", "KNOCK"},
    {"Doorbell", "DOORBELL"}, {"Ding-dong", "DOORBELL"},
    {"Telephone", "PHONE"}, {"Telephone bell ringing", "PHONE"}, {"Ringtone", "PHONE"},
    {"Bark", "DOG"}, {"Speech", "SPEECH"},
};
constexpr std::size_t kAnalyticsLegacyClassCount = sizeof(kAnalyticsLegacyClasses) / sizeof(kAnalyticsLegacyClasses[0]);

inline const char *dashboardEventForAlert(const char *event) {
  if (!event || !*event) return nullptr;
  if (event[0] != 'Y') return event;  // preserve existing non-catalog upload behavior
  const SoundCatalogEntry *entry = lookupSoundCatalog(event);
  if (!entry) return nullptr;
  for (const auto &candidate : kAnalyticsLegacyClasses)
    if (std::strcmp(entry->name, candidate.name) == 0) return candidate.event;
  return nullptr;  // never let an unsupported ID invalidate a legacy upload batch
}
}  // namespace fortwatch
