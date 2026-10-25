// FortWatch wristband display for the Waveshare ESP32-S3-Touch-LCD-2.
//
// Receives text messages from live_demo/mac_listener.py over Bluetooth LE
// (device name "FortWatch") or over the USB cable:
//   L,<0-100>            sound level -> live level bar
//   E,<EVENT>,<score>[,<angle>,<quality>] -> full-screen alert + optional direction
// Angle: degrees relative to phone, positive right; quality: heuristic coherence.
//
// With secrets.h (see secrets.example.h) the wristband also joins Wi-Fi and uploads
// every alert it shows to the analytics dashboard itself (wifi_analytics.h).
//
// Over BLE, each write to the RX characteristic is one message; over USB,
// messages are newline-terminated. Both paths feed the same handler.
//
// Home and waiting use the Figma backgrounds (docs/design, exported to screens.h).
// Alerts use the same category colours, Inter type and icons on a dark layout,
// with a circular cue for the dominant sound direction captured with the alert.
//
// The alert stays up for ALERT_MS or until the screen is tapped / BOOT is pressed.
// Each alert also vibrates (130 motor on GPIO17 through a PN2222 + 1N4007,
// see hardware/README wiring): the pattern depends on the alert's priority, so the
// user can tell a safety alert from a low-priority one without looking.
// Display pins and setup are taken from Waveshare's 02_gfx_helloworld example.
//
// Arduino IDE settings (Tools menu):
//   Board: ESP32S3 Dev Module, USB CDC On Boot: Enabled,
//   Flash Size: 16MB, PSRAM: OPI PSRAM
// Library: "GFX Library for Arduino" by Moon On Our Nation.

#include <Arduino_GFX_Library.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <Preferences.h>
#include <Wire.h>
#include "screens.h"
#include "fonts.h"
#include "alert_protocol.h"
#include "wifi_analytics.h"  // optional Wi-Fi upload to the dashboard (needs secrets.h)
#include "icons.h"    // generated: python ../fonts/make_icons.py icons.h (alert icons from Figma)    // generated: python ../fonts/make_font_atlas.py fonts.h (Inter, SIL OFL)  // generated: python ../screen_preview/png_to_rgb565.py ../../docs/design/firmware_screens screens.h

#define PIN_LCD_SCLK 39
#define PIN_LCD_MOSI 38
#define PIN_LCD_MISO 40
#define PIN_LCD_DC 42
#define PIN_LCD_RST -1
#define PIN_LCD_CS 45
#define PIN_LCD_BL 1
#define PIN_BOOT_BUTTON 0
#define PIN_TOUCH_SDA 48  // CST816 touch controller (I2C 0x15) — header pins 47/48 are taken
#define PIN_TOUCH_SCL 47
#define TOUCH_ADDR 0x15
#define PIN_MOTOR 17  // header pin 24 (printed "17", left column) -> 1 kOhm -> PN2222 base (never drive the motor directly)

const uint32_t ALERT_MS = 6000;      // how long an alert stays on screen
const uint32_t LINK_TIMEOUT_MS = 3000;  // no data for this long -> "waiting for Mac"

// Must match BLE_SERVICE_UUID / BLE_RX_UUID in mac_listener.py.
const char *BLE_NAME = "FortWatch";
const char *BLE_SERVICE_UUID = "6b1a0001-5d1e-4c3b-9a7e-50554e445345";
const char *BLE_RX_UUID = "6b1a0002-5d1e-4c3b-9a7e-50554e445345";

// RGB565 colours, defined here so the sketch doesn't depend on library colour names.
const uint16_t C_BLACK = 0x0000;
const uint16_t C_WHITE = 0xFFFF;
const uint16_t C_GREY = 0x7BEF;
const uint16_t C_DARK = 0x2104;
const uint16_t C_GREEN = 0x07E0;
const uint16_t C_RED = 0xF800;
const uint16_t C_ORANGE = 0xFD20;
const uint16_t C_BLUE = 0x041F;
const uint16_t C_PURPLE = 0x801F;
const uint16_t C_MAGENTA = 0xC818;
const uint16_t C_CRIMSON = 0xA000;
const uint16_t C_TEAL = 0x0410;
const uint16_t C_BROWN = 0x8200;
const uint16_t C_SLATE = 0x3A6F;
const uint16_t C_DARKGREEN = 0x0360;
const uint16_t C_UNKNOWN = 0x4208;

Arduino_DataBus *bus = new Arduino_ESP32SPI(
    PIN_LCD_DC, PIN_LCD_CS, PIN_LCD_SCLK, PIN_LCD_MOSI, PIN_LCD_MISO);
Arduino_GFX *gfx = new Arduino_ST7789(
    bus, PIN_LCD_RST, 1 /* rotation: landscape */, true /* IPS */, 240, 320);

enum class Screen { Waiting, Listening, Alert };

Screen screen = Screen::Waiting;
uint32_t lastMessageMs = 0;
uint32_t alertStartedMs = 0;
uint32_t alertCount = 0;
int lastLevel = -1;
char line[fortwatch::kMaxMessageLength + 1];
size_t lineLength = 0;
bool droppingSerialLine = false;
const char *linkName = "";  // "Bluetooth" or "USB", shown on the listening screen

// BLE callbacks run on the Bluetooth task, so they only queue messages;
// loop() does all drawing, keeping the display on a single task.
struct BleMessage {
  char text[fortwatch::kMaxMessageLength + 1];
};
QueueHandle_t bleQueue;
volatile bool bleConnected = false;

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    // Never turn a truncated write into a plausible but different alert.
    if (value.length() == 0 || value.length() > fortwatch::kMaxMessageLength) return;
    if (memchr(value.c_str(), '\0', value.length()) != nullptr) return;
    BleMessage message;
    size_t length = value.length();
    memcpy(message.text, value.c_str(), length);
    message.text[length] = '\0';
    xQueueSend(bleQueue, &message, 0);  // drop the message if the queue is full
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override { bleConnected = true; }
  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    BLEDevice::startAdvertising();  // let the Mac reconnect
  }
};

// Vibration patterns: alternating on/off durations in ms, 0-terminated.
const uint16_t VIB_SAFETY[] = {400, 150, 400, 150, 400, 0};  // 3 long
const uint16_t VIB_ATTENTION[] = {150, 120, 150, 0};        // 2 short
const uint16_t VIB_LOW[] = {150, 0};                        // 1 short
const uint16_t VIB_SELFTEST[] = {80, 0};                    // boot: motor wiring OK

struct EventStyle {
  const char *name;   // as sent by the Mac
  const char *title;  // shown on screen
  const char *hint;
  uint16_t colour;
  const uint16_t *vibration;
  const char *image;  // screen name in screens.h
};

// Names the Mac doesn't send yet still show up, using the fallback style below.
const EventStyle EVENT_STYLES[] = {
    {"ALARM", "ALARM!", "Alarm or siren nearby", C_RED, VIB_SAFETY, "alarm"},
    {"CAR_HORN", "CAR HORN", "Vehicle honking nearby", C_ORANGE, VIB_SAFETY, "car_horn"},
    {"GLASS", "GLASS", "Something broke", C_CRIMSON, VIB_SAFETY, "glass"},
    {"SHOUT", "SHOUT!", "Someone is shouting", C_MAGENTA, VIB_SAFETY, "shout"},
    {"BABY", "BABY", "Baby crying", C_TEAL, VIB_ATTENTION, "baby"},
    {"KNOCK", "KNOCK", "Someone at the door", C_BLUE, VIB_ATTENTION, "knock"},
    {"DOORBELL", "DOORBELL", "Someone at the door", C_PURPLE, VIB_ATTENTION, "doorbell"},
    {"PHONE", "PHONE", "Phone ringing", C_SLATE, VIB_ATTENTION, "phone"},
    {"DOG", "DOG", "Dog barking", C_BROWN, VIB_LOW, "dog"},
    {"SPEECH", "SPEECH", "Someone is talking nearby", C_DARKGREEN, VIB_LOW, "speech"},
};

// Non-blocking vibration player, stepped from loop().
const uint16_t *vibPattern = nullptr;
uint8_t vibStep = 0;
uint32_t vibStepStartedMs = 0;

void vibrate(const uint16_t *pattern) {
  vibPattern = pattern;
  vibStep = 0;
  vibStepStartedMs = millis();
  digitalWrite(PIN_MOTOR, HIGH);  // even steps are "on"
}

void updateVibration() {
  if (vibPattern == nullptr) return;
  if (millis() - vibStepStartedMs < vibPattern[vibStep]) return;
  vibStep++;
  vibStepStartedMs = millis();
  if (vibPattern[vibStep] == 0) {
    vibPattern = nullptr;
    digitalWrite(PIN_MOTOR, LOW);
  } else {
    digitalWrite(PIN_MOTOR, vibStep % 2 == 0 ? HIGH : LOW);
  }
}

void drawCentered(const char *text, int y, uint8_t size, uint16_t colour) {
  // Shrink until the text fits; the built-in font is 6x8 pixels per size step.
  while (size > 1 && (int)strlen(text) * 6 * size > gfx->width() - 10) size--;
  gfx->setTextSize(size);
  gfx->setTextColor(colour);
  int width = strlen(text) * 6 * size;
  gfx->setCursor((gfx->width() - width) / 2, y);
  gfx->print(text);
}

// ---- Figma screens ----
const uint16_t *screenImage(const char *name) {
  for (int i = 0; i < SCREEN_COUNT; i++) {
    if (strcmp(SCREENS[i].name, name) == 0) return SCREENS[i].pixels;
  }
  return nullptr;
}

// Redraw a rectangle of a full-screen image (used to erase live elements).
uint16_t blitBuffer[320 * 16];
void restoreRegion(const uint16_t *img, int x, int y, int w, int h) {
  for (int row = 0; row < h; row += 16) {
    int rows = min(16, h - row);
    for (int r = 0; r < rows; r++) memcpy(&blitBuffer[r * w], &img[(y + row + r) * 320 + x], w * 2);
    gfx->draw16bitRGBBitmap(x, y + row, blitBuffer, w, rows);
  }
}

// ---- Text: Inter glyph atlases (fonts.h), alpha-blended over the background image ----
uint16_t glyphBuffer[64 * 64];

inline uint16_t blend565(uint16_t bg, uint8_t r, uint8_t g, uint8_t b, uint16_t a /*0..256*/) {
  uint8_t br = (bg >> 11) << 3, bgg = ((bg >> 5) & 0x3F) << 2, bb = (bg & 0x1F) << 3;
  uint8_t R = br + (((int)r - br) * a >> 8), G = bgg + (((int)g - bgg) * a >> 8), B = bb + (((int)b - bb) * a >> 8);
  return ((R & 0xF8) << 8) | ((G & 0xFC) << 3) | (B >> 3);
}

// Draws text with its left edge at x and its baseline at y; returns the x after the text.
int drawText(const AtlasFont &f, const uint16_t *bg, int x, int y, const char *text,
             float opacity = 1.0f, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255) {
  uint16_t op = uint16_t(opacity * 256);
  for (const char *p = text; *p; p++) {
    uint8_t code = (uint8_t)*p;
    if (code < f.first || code > f.last) continue;
    const Glyph &gl = f.glyphs[code - f.first];
    int gx = x + gl.xoff, gy = y + gl.yoff;
    if (gl.w && gl.h && gl.w * gl.h <= (int)sizeof(glyphBuffer) / 2 && gx >= 0 && gy >= 0 && gx + gl.w <= 320 && gy + gl.h <= 240) {
      for (int j = 0; j < gl.h; j++) {
        for (int i = 0; i < gl.w; i++) {
          uint16_t a = (f.alpha[gl.offset + j * gl.w + i] * op) >> 8;
          glyphBuffer[j * gl.w + i] = blend565(bg[(gy + j) * 320 + gx + i], r, g, b, a);
        }
      }
      gfx->draw16bitRGBBitmap(gx, gy, glyphBuffer, gl.w, gl.h);
    }
    x += gl.adv + f.tracking;
  }
  return x;
}

// ---- Home screen (iOS-style Liquid Glass, designed in Figma: docs/design/firmware_screens/home.png) ----
// Live parts drawn on top: clock + date (from the Mac's T message), level bars, status, last alert.
char clockText[8] = "";
char dateText[32] = "";
char lastAlertTitle[16] = "";
const char *lastAlertIcon = nullptr;  // icon name in icons.h (same as the screen name)
uint32_t lastAlertMs = 0;
uint32_t lastAgoDrawMs = 0;

const int BARS = 14, BAR_X = 24, BAR_BOTTOM = 200, BAR_MAX = 36, BAR_W = 6, BAR_STEP = 9;
uint8_t barHeight[BARS];
int meterLevel = 0;
uint32_t lastMeterMs = 0;
uint16_t columnBuffer[BAR_W * BAR_MAX];

const uint16_t *homeBg() { return screenImage("home"); }

void drawBar(const uint16_t *bg, int i, int h) {
  int x = BAR_X + i * BAR_STEP, top = BAR_BOTTOM - BAR_MAX;
  bool hot = meterLevel > 60;
  uint8_t r = 255, g = hot ? 191 : 255, b = hot ? 36 : 255;  // white, amber (#FFBF24) when loud
  for (int row = 0; row < BAR_MAX; row++) {
    int fromBottom = BAR_MAX - 1 - row;
    for (int c = 0; c < BAR_W; c++) {
      bool on = fromBottom < h;
      // round the top and bottom corners: drop the outer pixels of the first/last two rows
      int edge = min(h - 1 - fromBottom, fromBottom);
      if (on && edge < 2 && (c == 0 || c == BAR_W - 1)) on = false;
      uint16_t px = bg[(top + row) * 320 + x + c];
      columnBuffer[row * BAR_W + c] = on ? blend565(px, r, g, b, 230) : px;
    }
  }
  gfx->draw16bitRGBBitmap(x, top, columnBuffer, BAR_W, BAR_MAX);
}

void updateMeter() {
  const uint16_t *bg = homeBg();
  if (screen != Screen::Listening || bg == nullptr || millis() - lastMeterMs < 50) return;
  lastMeterMs = millis();
  float t = millis() * 0.004f;
  for (int i = 0; i < BARS; i++) {
    float x = i / float(BARS - 1);
    float env = expf(-powf((x - 0.5f) / 0.32f, 2));
    float wob = 0.55f + 0.45f * fabsf(sinf(t + i * 1.7f));
    int target = 4 + int((BAR_MAX - 4) * (meterLevel / 100.0f) * env * wob);
    int h = barHeight[i] + (target - barHeight[i]) / 2;  // ease towards the target
    if (h != barHeight[i]) {
      barHeight[i] = h;
      drawBar(bg, i, h);
    }
  }
}

void drawLevelBar(int level) { meterLevel = level; }

void drawClock() {
  const uint16_t *bg = homeBg();
  if (!bg) return;
  restoreRegion(bg, 10, 24, 220, 62);   // clock
  restoreRegion(bg, 14, 90, 220, 20);   // date
  drawText(F_CLOCK, bg, 14, 80, clockText[0] ? clockText : "--:--", clockText[0] ? 1.0f : 0.35f);
  if (dateText[0]) drawText(F_BODY, bg, 18, 105, dateText, 0.85f);
}

void drawStatus() {
  const uint16_t *bg = homeBg();
  if (!bg) return;
  restoreRegion(bg, 20, 206, 134, 16);
  char status[40];
  snprintf(status, sizeof(status), "%s \x7f %s", linkName[0] ? linkName : "Phone", meterLevel > 60 ? "hearing sound" : "quiet");
  drawText(F_TINY, bg, 24, 218, status, 0.7f);
}

// SPEECH alerts can be turned off on the wristband itself (they fire with any conversation
// nearby): hold the home screen, or BOOT, for 1 s. Saved in flash, so it survives a restart.
Preferences prefs;
bool speechEnabled = true;

void drawIcon(const uint16_t *bg, const char *name, int x, int y, float opacity = 1.0f);

// Top-right of the home screen, beside the clock: speaking-person icon + On/Off.
void drawSpeechToggle() {
  const uint16_t *bg = homeBg();
  if (!bg) return;
  restoreRegion(bg, 240, 40, 70, 28);
  drawIcon(bg, "speech", 246, 44, speechEnabled ? 1.0f : 0.35f);
  drawText(F_SMALL, bg, 270, 59, speechEnabled ? "On" : "Off", speechEnabled ? 0.9f : 0.5f);
}

void toggleSpeech() {
  speechEnabled = !speechEnabled;
  prefs.putBool("speech", speechEnabled);
  Serial.printf("SPEECH alerts %s\n", speechEnabled ? "on" : "off");
  vibrate(VIB_LOW);
  if (screen == Screen::Listening) drawSpeechToggle();
}

// Alert icon (alpha mask from icons.h) blended over the background.
void drawIcon(const uint16_t *bg, const char *name, int x, int y, float opacity) {
  const uint8_t *mask = nullptr;
  for (int i = 0; i < ICON_COUNT; i++) if (strcmp(ICONS[i].name, name) == 0) mask = ICONS[i].alpha;
  if (!mask) return;
  uint16_t op = uint16_t(opacity * 256);
  for (int j = 0; j < ICON_SIZE; j++)
    for (int i = 0; i < ICON_SIZE; i++)
      glyphBuffer[j * ICON_SIZE + i] = blend565(bg[(y + j) * 320 + x + i], 255, 255, 255, (mask[j * ICON_SIZE + i] * op) >> 8);
  gfx->draw16bitRGBBitmap(x, y, glyphBuffer, ICON_SIZE, ICON_SIZE);
}

void drawLastAlert() {
  const uint16_t *bg = homeBg();
  if (!bg) return;
  restoreRegion(bg, 170, 156, 134, 66);
  char ago[24], count[24];
  if (lastAlertTitle[0]) {
    uint32_t mins = (millis() - lastAlertMs) / 60000;
    if (mins == 0) snprintf(ago, sizeof(ago), "just now");
    else if (mins < 60) snprintf(ago, sizeof(ago), "%lu min ago", (unsigned long)mins);
    else snprintf(ago, sizeof(ago), "%lu h ago", (unsigned long)(mins / 60));
    int tx = 174;
    if (lastAlertIcon) { drawIcon(bg, lastAlertIcon, 174, 162); tx = 200; }
    drawText(F_TITLE, bg, tx, 179, lastAlertTitle);
  } else {
    snprintf(ago, sizeof(ago), "Nothing yet");
    drawText(F_TITLE, bg, 174, 179, "All quiet", 0.9f);
  }
  snprintf(count, sizeof(count), "%lu alert%s so far", (unsigned long)alertCount, alertCount == 1 ? "" : "s");
  drawText(F_SMALL, bg, 174, 197, ago, 0.8f);
  drawText(F_TINY, bg, 174, 218, count, 0.6f);
  lastAgoDrawMs = millis();
}

void showWaiting() {
  screen = Screen::Waiting;
  const uint16_t *img = screenImage("waiting");
  if (img) {
    gfx->draw16bitRGBBitmap(0, 0, img, 320, 240);
    return;
  }
  gfx->fillScreen(C_BLACK);
  drawCentered("FortWatch", 50, 4, C_WHITE);
  drawCentered("Waiting for Mac...", 120, 2, C_GREY);
  drawCentered("Bluetooth: FortWatch", 160, 2, C_GREY);
  drawCentered("or plug in USB", 190, 2, C_GREY);
}

void showListening() {
  screen = Screen::Listening;
  lastLevel = -1;
  const uint16_t *img = homeBg();
  if (img) {
    gfx->draw16bitRGBBitmap(0, 0, img, 320, 240);
    memset(barHeight, 0, sizeof(barHeight));
    drawClock();
    drawStatus();
    drawLastAlert();
    drawSpeechToggle();
    return;
  }
  gfx->fillScreen(C_BLACK);
  drawCentered("LISTENING...", 40, 3, C_GREEN);
  char footer[32];
  snprintf(footer, sizeof(footer), "Alerts: %lu  |  %s", (unsigned long)alertCount, linkName);
  drawCentered(footer, 205, 2, C_GREY);
}

// Alert drawing reuses glyphBuffer; no full-screen RAM or PSRAM buffer is needed.
const uint16_t ALERT_BASE = 0x0862;  // charcoal under the original category tint
const uint16_t ALERT_MUTED = 0xC638;
uint16_t alertBackground = ALERT_BASE;
uint16_t alertRule = 0x2126;

int alertTextWidth(const AtlasFont &font, const char *text) {
  int width = 0;
  for (const char *p = text; *p; p++) {
    const uint8_t code = uint8_t(*p);
    if (code >= font.first && code <= font.last)
      width += font.glyphs[code - font.first].adv + font.tracking;
  }
  return width;
}

// Scaled Inter glyphs on a solid surface. Text positions are baselines, as above.
void drawAlertText(const AtlasFont &font, uint16_t bg, int x, int y,
                   const char *text, uint16_t colour, float scale = 1.0f) {
  float pen = x;
  const uint8_t r = (colour >> 11) << 3;
  const uint8_t g = ((colour >> 5) & 0x3F) << 2, b = (colour & 0x1F) << 3;
  for (const char *p = text; *p; p++) {
    const uint8_t code = uint8_t(*p);
    if (code < font.first || code > font.last) continue;
    const Glyph &gl = font.glyphs[code - font.first];
    const int gx = int(roundf(pen + gl.xoff * scale));
    const int gy = y + int(roundf(gl.yoff * scale));
    const int w = int(roundf(gl.w * scale)), h = int(roundf(gl.h * scale));
    if (w && h && w * h <= int(sizeof(glyphBuffer) / 2) &&
        gx >= 0 && gy >= 0 && gx + w <= 320 && gy + h <= 240) {
      for (int row = 0; row < h; row++) {
        const int sourceY = min(int(row / scale), int(gl.h) - 1);
        for (int col = 0; col < w; col++) {
          const int sourceX = min(int(col / scale), int(gl.w) - 1);
          const uint8_t a = font.alpha[gl.offset + sourceY * gl.w + sourceX];
          glyphBuffer[row * w + col] = blend565(bg, r, g, b, a);
        }
      }
      gfx->draw16bitRGBBitmap(gx, gy, glyphBuffer, w, h);
    }
    pen += (gl.adv + font.tracking) * scale;
  }
}

void drawAlertWrapped(const AtlasFont &font, const char *text, int x, int baseline,
                      int width, int lineHeight, uint16_t colour) {
  // Event names are at most 23 characters; known hints are short, static strings.
  char part[48];
  while (*text) {
    int count = 0, lastSpace = -1;
    while (text[count] && count < int(sizeof(part)) - 1) {
      part[count] = text[count];
      part[count + 1] = '\0';
      if (alertTextWidth(font, part) > width && count > 0) break;
      if (text[count] == ' ') lastSpace = count;
      count++;
    }
    if (text[count] && lastSpace > 0) count = lastSpace;
    part[count] = '\0';
    drawAlertText(font, alertBackground, x, baseline, part, colour);
    text += count;
    while (*text == ' ') text++;
    baseline += lineHeight;
  }
}

void drawAlertBadge(const char *iconName, int cx, int cy, uint16_t accent) {
  const uint16_t badge = blend565(alertBackground, (accent >> 11) << 3,
                                ((accent >> 5) & 0x3F) << 2,
                                (accent & 0x1F) << 3, 100);
  gfx->fillCircle(cx, cy, 17, alertBackground);
  gfx->fillCircle(cx, cy, 15, badge);
  gfx->drawCircle(cx, cy, 15, accent);
  const uint8_t *alpha = nullptr;
  for (int i = 0; iconName && i < ICON_COUNT; i++) {
    if (strcmp(ICONS[i].name, iconName) == 0) alpha = ICONS[i].alpha;
  }
  if (alpha) {
    for (int i = 0; i < ICON_SIZE * ICON_SIZE; i++)
      glyphBuffer[i] = blend565(badge, 255, 255, 255, alpha[i]);
    gfx->draw16bitRGBBitmap(cx - ICON_SIZE / 2, cy - ICON_SIZE / 2,
                          glyphBuffer, ICON_SIZE, ICON_SIZE);
  } else {
    gfx->fillCircle(cx, cy, 4, C_WHITE);
  }
}

void drawAlertDirection(const fortwatch::AlertMessage &message,
                        const EventStyle &style, uint16_t accent) {
  const int cx = 227, cy = 119, radius = 54;
  gfx->drawCircle(cx, cy, radius, alertRule);
  gfx->drawCircle(cx, cy, radius - 10, alertRule);
  // Reticle marks the phone reference; it is not a second sound source.
  gfx->drawLine(cx - 12, cy, cx - 5, cy, ALERT_MUTED);
  gfx->drawLine(cx + 5, cy, cx + 12, cy, ALERT_MUTED);
  gfx->drawLine(cx, cy - 12, cx, cy - 5, ALERT_MUTED);
  gfx->drawLine(cx, cy + 5, cx, cy + 12, ALERT_MUTED);
  gfx->drawCircle(cx, cy, 2, C_WHITE);

  char label[32];
  if (fortwatch::hasUsableDirection(message)) {
    // A single fixed-width, tapered cue: its width does not claim an error bound.
    // Zero points up/front, positive angles clockwise/right. Captured at alert
    // time, not continuously tracked and not isolated to the classified source.
    for (int offset = -33; offset <= 33; offset++) {
      const float a = (message.angleDegrees + offset) * 0.01745329252f;
      const int thickness = 1 + (33 - abs(offset)) * 4 / 33;
      gfx->fillCircle(cx + int(roundf(sinf(a) * radius)),
                      cy - int(roundf(cosf(a) * radius)), thickness, accent);
    }
    const float a = message.angleDegrees * 0.01745329252f;
    drawAlertBadge(style.image, cx + int(roundf(sinf(a) * radius)),
                   cy - int(roundf(cosf(a) * radius)), accent);
    const int degrees = int(roundf(fabsf(message.angleDegrees)));
    const char *side = degrees == 0 ? "AHEAD" : degrees == 180 ? "BEHIND" :
                       message.angleDegrees < 0 ? "LEFT" : "RIGHT";
    snprintf(label, sizeof(label), "%d deg %s", degrees, side);
  } else {
    // No arc or perimeter badge without a usable measurement.
    gfx->fillCircle(cx, cy, 17, alertBackground);
    drawAlertText(F_TITLE, alertBackground, cx - alertTextWidth(F_TITLE, "?") / 2,
                   cy + 7, "?", ALERT_MUTED);
    strcpy(label, "Direction uncertain");
  }
  drawAlertText(F_TINY, alertBackground, cx - alertTextWidth(F_TINY, "PHONE") / 2,
                 cy + 31, "PHONE", ALERT_MUTED);
  drawAlertText(F_SMALL, alertBackground, cx - alertTextWidth(F_SMALL, label) / 2,
                 200, label, C_WHITE);
}

void drawAlertScreen(const fortwatch::AlertMessage &message, const EventStyle &style) {
  // The original category colour supplies the whole card's dark, saturated tint.
  alertBackground = blend565(ALERT_BASE, (style.colour >> 11) << 3,
                             ((style.colour >> 5) & 0x3F) << 2,
                             (style.colour & 0x1F) << 3, 96);
  alertRule = blend565(alertBackground, 255, 255, 255, 28);
  // Lift the existing category colours so even low-priority colours read on dark.
  const uint16_t accent = blend565(style.colour, 255, 255, 255, 64);
  const uint16_t pill = blend565(alertBackground, (accent >> 11) << 3,
                               ((accent >> 5) & 0x3F) << 2,
                               (accent & 0x1F) << 3, 55);
  const bool safety = style.vibration == VIB_SAFETY;
  const bool attention = style.vibration == VIB_ATTENTION;
  const char *priority = safety ? "SAFETY" : attention ? "ATTENTION" : "LOW PRIORITY";
  const int pillWidth = alertTextWidth(F_TINY, priority) + 29;
  gfx->fillScreen(alertBackground);
  gfx->fillRoundRect(16, 14, pillWidth, 24, 12, pill);
  gfx->fillCircle(25, 26, 2, accent);
  drawAlertText(F_TINY, pill, 33, 30, priority, C_WHITE);
  drawAlertText(F_TINY, alertBackground, 218, 29, "VIB", ALERT_MUTED);
  const int pulseCount = safety ? 3 : attention ? 2 : 1;
  for (int i = 0; i < pulseCount; i++)
    gfx->fillRoundRect(247 + i * 20, 22, safety ? 14 : 8, 5, 2, accent);
  gfx->drawFastHLine(16, 46, 288, alertRule);

  const int titleWidth = alertTextWidth(F_TITLE, style.title);
  if (titleWidth <= 134) {
    const float scale = min(1.5f, 134.0f / max(titleWidth, 1));
    drawAlertText(F_TITLE, alertBackground, 16, 90, style.title, C_WHITE, scale);
  } else {
    // Keep arbitrary valid protocol names visible, including a 23-character name.
    drawAlertWrapped(F_SMALL, style.title, 16, 77, 134, 14, C_WHITE);
  }
  drawAlertWrapped(F_BODY, style.hint, 16, 129, 132, 16, ALERT_MUTED);
  drawAlertDirection(message, style, accent);

  char scoreText[8];
  snprintf(scoreText, sizeof(scoreText), "%d%%", int(message.score * 100));
  drawAlertText(F_TINY, alertBackground, 16, 172, "CONFIDENCE", ALERT_MUTED);
  drawAlertText(F_TINY, alertBackground, 148 - alertTextWidth(F_TINY, scoreText),
                 172, scoreText, C_WHITE);
  gfx->fillRoundRect(16, 181, 132, 4, 2, alertRule);
  const int scoreWidth = constrain(int(roundf(132 * message.score)), 0, 132);
  if (scoreWidth > 0) gfx->fillRect(16, 181, scoreWidth, 4, accent);

  const char *reference = "Captured dominant sound / phone";
  drawAlertText(F_TINY, alertBackground, (320 - alertTextWidth(F_TINY, reference)) / 2,
                 215, reference, ALERT_MUTED);
  gfx->drawFastHLine(16, 222, 288, alertRule);
  const char *dismiss = "Tap screen or press BOOT to dismiss";
  drawAlertText(F_TINY, alertBackground, (320 - alertTextWidth(F_TINY, dismiss)) / 2,
                 236, dismiss, ALERT_MUTED);
}

void showAlert(const fortwatch::AlertMessage &message) {
  const char *eventName = message.event;
  const float score = message.score;
  const EventStyle *style = nullptr;
  for (const EventStyle &candidate : EVENT_STYLES) {
    if (strcmp(candidate.name, eventName) == 0) style = &candidate;
  }
  EventStyle fallback;
  char fallbackTitle[24];
  if (style == nullptr) {
    // Unknown name: show it as-is ("WATER_TAP" -> "WATER TAP").
    strncpy(fallbackTitle, eventName, sizeof(fallbackTitle) - 1);
    fallbackTitle[sizeof(fallbackTitle) - 1] = '\0';
    for (char *c = fallbackTitle; *c; c++) {
      if (*c == '_') *c = ' ';
    }
    fallback = {eventName, fallbackTitle, "Sound detected", C_UNKNOWN, VIB_LOW};
    style = &fallback;
  }

  screen = Screen::Alert;
  alertStartedMs = millis();
  alertCount++;
  strncpy(lastAlertTitle, style->title, sizeof(lastAlertTitle) - 1);
  lastAlertTitle[sizeof(lastAlertTitle) - 1] = '\0';
  lastAlertMs = millis();
  lastAlertIcon = style->image;
  analyticsAlert(eventName, score);
  drawAlertScreen(message, *style);
  vibrate(style->vibration);
}

void handleLine(char *text) {
  lastMessageMs = millis();
  if (text[0] == 'L' && text[1] == ',') {
    int level = constrain(atoi(text + 2), 0, 100);
    analyticsStatus(level, strcmp(linkName, "USB") == 0 ? "usb" : "ble");
    if (screen == Screen::Waiting) showListening();
    if (screen == Screen::Listening && level != lastLevel) {
      bool crossed = (level > 60) != (lastLevel > 60);
      drawLevelBar(level);
      lastLevel = level;
      if (crossed && homeBg()) drawStatus();
    }
  } else if (text[0] == 'T' && text[1] == ',') {
    // T,HH:MM,<date>  — local time from the Mac (the board has no clock of its own)
    char *time = text + 2;
    char *comma = strchr(time, ',');
    if (comma) *comma = '\0';
    bool changed = strcmp(clockText, time) != 0 || (comma && strcmp(dateText, comma + 1) != 0);
    strncpy(clockText, time, sizeof(clockText) - 1);
    if (comma) strncpy(dateText, comma + 1, sizeof(dateText) - 1);
    if (changed && screen == Screen::Listening) drawClock();
  } else if (text[0] == 'E' && text[1] == ',') {
    fortwatch::AlertMessage message;
    if (!fortwatch::parseAlert(text, message)) return;
    if (!speechEnabled && strcmp(message.event, "SPEECH") == 0) return;
    showAlert(message);
  }
}

void readSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      line[lineLength] = '\0';
      if (!droppingSerialLine && lineLength > 0) {
        linkName = "USB";
        handleLine(line);
      }
      lineLength = 0;
      droppingSerialLine = false;
    } else if (droppingSerialLine) {
      continue;
    } else if (c == '\0') {
      lineLength = 0;
      droppingSerialLine = true;
    } else if (lineLength < sizeof(line) - 1) {
      line[lineLength++] = c;
    } else {
      lineLength = 0;
      droppingSerialLine = true;  // discard the entire overlong line, not just its prefix
    }
  }
}

void readBluetooth() {
  BleMessage message;
  while (xQueueReceive(bleQueue, &message, 0) == pdTRUE) {
    // Tolerate a trailing newline in case the sender adds one.
    message.text[strcspn(message.text, "\r\n")] = '\0';
    if (message.text[0] != '\0') {
      linkName = "Bluetooth";
      handleLine(message.text);
    }
  }
}

void startBluetooth() {
  bleQueue = xQueueCreate(16, sizeof(BleMessage));
  BLEDevice::init(BLE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(BLE_SERVICE_UUID);
  BLECharacteristic *rx = service->createCharacteristic(
      BLE_RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCallbacks());
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.printf("BLE advertising as %s (%s)\n", BLE_NAME, BLEDevice::getAddress().toString().c_str());
}

// CST816 touch: registers 0x02 = number of fingers, 0x03-0x06 = X/Y (12-bit, raw panel
// coordinates in portrait). touchX/touchY hold the last raw point while a finger is down.
bool touchReady = false;
int touchX = -1, touchY = -1;
bool screenTouched() {
  if (!touchReady) return false;
  Wire.beginTransmission(TOUCH_ADDR);
  Wire.write(0x02);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(TOUCH_ADDR, 5) != 5) return false;
  uint8_t fingers = Wire.read() & 0x0F;
  uint8_t xh = Wire.read(), xl = Wire.read(), yh = Wire.read(), yl = Wire.read();
  if (fingers == 0) return false;
  touchX = ((xh & 0x0F) << 8) | xl;
  touchY = ((yh & 0x0F) << 8) | yl;
  return true;
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT_BUTTON, INPUT_PULLUP);
  pinMode(PIN_MOTOR, OUTPUT);
  digitalWrite(PIN_MOTOR, LOW);

  if (!gfx->begin()) {
    Serial.println("gfx->begin() failed!");
  }
  pinMode(PIN_LCD_BL, OUTPUT);
  digitalWrite(PIN_LCD_BL, HIGH);
  touchReady = Wire.begin(PIN_TOUCH_SDA, PIN_TOUCH_SCL, 400000);
  Wire.beginTransmission(TOUCH_ADDR);
  Serial.printf("Touch controller %s\n", Wire.endTransmission() == 0 ? "found" : "not answering (asleep until touched?)");
  prefs.begin("fortwatch", false);
  speechEnabled = prefs.getBool("speech", true);
  startBluetooth();
  startAnalytics();
  showWaiting();
  vibrate(VIB_SELFTEST);
}

void loop() {
  readSerial();
  readBluetooth();
  updateVibration();
  updateMeter();
  uint32_t now = millis();
  if (screen == Screen::Listening && lastAlertTitle[0] && now - lastAgoDrawMs > 30000) drawLastAlert();

  static bool wasTouched = false;
  bool touched = screenTouched();
  bool tap = touched && !wasTouched;
  wasTouched = touched;
  if (tap) Serial.printf("Touch: raw x=%d y=%d\n", touchX, touchY);  // for mapping the panel

  // Hold the home screen (or BOOT) for 1 s to turn SPEECH alerts on/off. Only presses that
  // start on the home screen count, so the tap that dismisses an alert can't toggle it.
  static uint32_t holdStartMs = 0;
  static bool holdUsed = false;
  bool pressed = touched || digitalRead(PIN_BOOT_BUTTON) == LOW;
  if (!pressed) {
    holdStartMs = 0;
    holdUsed = false;
  } else if (holdStartMs == 0) {
    holdStartMs = now;
    holdUsed = screen != Screen::Listening;
  } else if (!holdUsed && screen == Screen::Listening && now - holdStartMs >= 1000) {
    holdUsed = true;
    toggleSpeech();
  }

  if (screen == Screen::Alert) {
    bool dismissed = digitalRead(PIN_BOOT_BUTTON) == LOW || (tap && now - alertStartedMs > 300);
    if (dismissed || now - alertStartedMs >= ALERT_MS) showListening();
  } else if (screen == Screen::Listening && now - lastMessageMs > LINK_TIMEOUT_MS) {
    showWaiting();
  }
  delay(5);
}
