// Wi-Fi upload of every alert to the FortWatch analytics dashboard, straight from the
// wristband, so it doesn't depend on the Mac for the dashboard.
//
// Off unless secrets.h exists (copy secrets.example.h; it's git-ignored): it holds the
// Wi-Fi networks, the ingest URL and the device key. Only the alert name, score, level
// and time are uploaded, never audio.
//
// Uploads run on their own FreeRTOS task, so a slow or missing network never delays
// the screen, the vibration or Bluetooth. Alerts made while offline are kept (up to
// 50) and sent when Wi-Fi is back.
#pragma once

#if __has_include("secrets.h")
#include "secrets.h"
#define FORTWATCH_WIFI 1
#else
#define FORTWATCH_WIFI 0
#endif

#if FORTWATCH_WIFI
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_mac.h>
#include <time.h>
#include "root_ca.h"

struct AlertUpload {
  char event[24];
  float score;
  uint8_t level;
  uint64_t atMs;  // 0 = not known yet (no NTP time); the server then uses arrival time
};

const int UPLOAD_QUEUE = 16;
const int MAX_PENDING = 50;
const uint32_t HEARTBEAT_MS = 5000;

QueueHandle_t uploadQueue;
volatile uint8_t uploadLevel = 0;
volatile const char *uploadLink = "none";
volatile bool wifiUp = false;
char deviceId[24];

uint64_t nowMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 1700000000) return 0;  // clock not set by NTP yet
  return uint64_t(tv.tv_sec) * 1000 + tv.tv_usec / 1000;
}

// Called from loop(): only queues, never touches the network.
void analyticsAlert(const char *event, float score) {
  AlertUpload a;
  strncpy(a.event, event, sizeof(a.event) - 1);
  a.event[sizeof(a.event) - 1] = '\0';
  a.score = score;
  a.level = uploadLevel;  // latest L, level from the Mac
  a.atMs = nowMs();
  xQueueSend(uploadQueue, &a, 0);  // full queue: drop (the task drains it every 200 ms)
}

void analyticsStatus(int level, const char *link) {
  uploadLevel = constrain(level, 0, 100);
  uploadLink = link;
}

// Returns the HTTP status, or a negative HTTPClient error when the server can't be reached.
int postJson(HTTPClient &http, WiFiClientSecure &client, const char *path, const String &body) {
  String url = String(ANALYTICS_URL) + "/" + path;
  if (!http.begin(client, url)) return -1;
  http.addHeader("content-type", "application/json");
  http.addHeader("x-device-key", ANALYTICS_KEY);
  int status = http.POST(body);
  http.end();
  return status;
}

// Joins the first configured network that answers, without scanning every channel
// first: a full scan while Bluetooth is busy froze the radio core (watchdog resets).
bool joinKnownNetwork() {
  for (const WifiNetwork &n : WIFI_NETWORKS) {
    WiFi.begin(n.ssid, n.password);
    // Low transmit power: the phone hotspot is centimetres away, and full power drew
    // current spikes this board (on USB or a power bank) didn't always handle.
    WiFi.setTxPower(WIFI_POWER_8_5dBm);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) vTaskDelay(pdMS_TO_TICKS(250));
    if (WiFi.status() == WL_CONNECTED) return true;
    WiFi.disconnect();
    vTaskDelay(pdMS_TO_TICKS(200));
  }
  return false;
}

void uploadTask(void *) {
  WiFi.setAutoReconnect(true);  // after a short drop the driver rejoins by itself
  WiFiClientSecure client;
  client.setCACert(ANALYTICS_ROOT_CA);
  HTTPClient http;
  http.setTimeout(8000);
  http.setReuse(true);  // keep the TLS connection open between posts

  AlertUpload pending[MAX_PENDING];
  int pendingCount = 0;
  bool clockStarted = false;
  uint32_t nextHeartbeat = 0;
  uint32_t lastWarning = 0;
  uint32_t retryMs = 5000;  // grows to 60 s while no network is in range

  for (;;) {
    AlertUpload a;
    while (xQueueReceive(uploadQueue, &a, 0) == pdTRUE) {
      if (pendingCount == MAX_PENDING) {  // full: drop the oldest
        memmove(pending, pending + 1, sizeof(AlertUpload) * (MAX_PENDING - 1));
        pendingCount--;
      }
      pending[pendingCount++] = a;
    }

    // Link down: try the known networks, then back off (5 s up to 60 s) so a missing
    // hotspot doesn't keep the radio busy.
    if (WiFi.status() != WL_CONNECTED && !joinKnownNetwork()) {
      if (wifiUp) Serial.println("Wi-Fi: disconnected; alerts are kept and retried");
      wifiUp = false;
      Serial.printf("Wi-Fi: no configured network in range (2.4 GHz only); retrying in %lu s\n",
                    (unsigned long)(retryMs / 1000));
      vTaskDelay(pdMS_TO_TICKS(retryMs));
      retryMs = min<uint32_t>(retryMs * 2, 60000);
      continue;
    }
    retryMs = 5000;
    if (!wifiUp) Serial.printf("Wi-Fi: connected to %s (%s)\n", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str());
    wifiUp = true;
    if (!clockStarted) {
      configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC, for alert timestamps
      clockStarted = true;
    }

    int status = 200;
    if (pendingCount > 0) {
      String body = String("{\"deviceId\":\"") + deviceId + "\",\"alerts\":[";
      for (int i = 0; i < pendingCount; i++) {
        char item[160];
        snprintf(item, sizeof(item),
                 "%s{\"event\":\"%s\",\"score\":%.3f,\"level\":%u,\"delivered\":true,\"atMs\":%llu}",
                 i ? "," : "", pending[i].event, pending[i].score, pending[i].level,
                 (unsigned long long)pending[i].atMs);
        body += item;
      }
      body += "]}";
      status = postJson(http, client, "alert", body);
      if (status >= 200 && status < 300) {
        Serial.printf("Analytics: uploaded %d alert(s)\n", pendingCount);
        pendingCount = 0;
      } else if (status >= 400 && status < 500 && status != 401 && status != 408 && status != 429) {
        // The server will never accept this batch; retrying would block every later alert.
        Serial.printf("Analytics: server refused %d alert(s) (HTTP %d); dropped\n", pendingCount, status);
        pendingCount = 0;
      }
    }
    if (status >= 200 && status < 500 && millis() >= nextHeartbeat) {
      nextHeartbeat = millis() + HEARTBEAT_MS;
      char body[160];
      snprintf(body, sizeof(body),
               "{\"deviceId\":\"%s\",\"name\":\"%s\",\"level\":%u,\"link\":\"%s\",\"wristbandConnected\":true}",
               deviceId, deviceId, uploadLevel, (const char *)uploadLink);
      int hb = postJson(http, client, "heartbeat", body);
      if (hb < 200 || hb >= 300) status = hb;
    }
    if (status < 200 || status >= 300) {
      if (millis() - lastWarning > 30000) {
        lastWarning = millis();
        if (status == 401) Serial.println("Analytics: server rejected the device key (ANALYTICS_KEY in secrets.h)");
        else Serial.printf("Analytics: upload failed (%d: %s); retrying\n", status, http.errorToString(status).c_str());
      }
      vTaskDelay(pdMS_TO_TICKS(5000));
    }
    vTaskDelay(pdMS_TO_TICKS(200));
  }
}

void startAnalytics() {
  uint8_t mac[6];
  WiFi.mode(WIFI_STA);
  esp_read_mac(mac, ESP_MAC_WIFI_STA);  // from eFuse: valid before Wi-Fi has started
  snprintf(deviceId, sizeof(deviceId), "fortwatch-%02x%02x%02x", mac[3], mac[4], mac[5]);
  uploadQueue = xQueueCreate(UPLOAD_QUEUE, sizeof(AlertUpload));
  // Core 0, next to the radio; loop() (screen, touch, vibration) stays on core 1.
  xTaskCreatePinnedToCore(uploadTask, "analytics", 12288, nullptr, 1, nullptr, 0);
  Serial.printf("Analytics: on, as %s\n", deviceId);
}

#else
void analyticsAlert(const char *, float) {}
void analyticsStatus(int, const char *) {}
void startAnalytics() { Serial.println("Analytics: off (no secrets.h)"); }
#endif
