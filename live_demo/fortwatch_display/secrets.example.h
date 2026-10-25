// Copy this file to secrets.h (same folder; git-ignored) and fill it in to make the
// wristband upload its alerts to the analytics dashboard over Wi-Fi.
// Without secrets.h the firmware builds and works the same, just without Wi-Fi.
// Never commit secrets.h.
#pragma once

struct WifiNetwork { const char *ssid; const char *password; };

// Tried in this order (put the one you use most first). 2.4 GHz WPA2 networks only (the ESP32 can't join
// 5 GHz, or networks that need a login web page or a username, like eduroam).
// A phone hotspot works well for demos.
const WifiNetwork WIFI_NETWORKS[] = {
    {"<wifi name>", "<wifi password>"},
    {"<phone hotspot name>", "<hotspot password>"},
};

// Analytics ingest URL (ends in /route, no trailing slash) and device key.
#define ANALYTICS_URL "https://<server>/v1/database/fortwatch/route"
#define ANALYTICS_KEY "sk_..."
