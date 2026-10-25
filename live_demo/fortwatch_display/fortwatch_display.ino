// FortWatch wristband display for the Waveshare ESP32-S3-Touch-LCD-2.
//
// Receives text messages from live_demo/mac_listener.py over Bluetooth LE
// (device name "FortWatch") or over the USB cable:
//   L,<0-100>            sound level -> live level bar
//   E,<EVENT>,<score>[,<angle>,<quality>] -> full-screen alert + optional direction
//   D,<EVENT>,<score>[,<angle>,<quality>] -> live visual refresh, no new notification
//   P,<EVENT>            manual pattern test, without detection history/analytics
// Angle: degrees relative to phone, positive right; quality: heuristic coherence.
//
// With secrets.h (see secrets.example.h) the wristband also joins Wi-Fi and uploads
// every alert it shows to the analytics dashboard itself (wifi_analytics.h).
//
// Over BLE, each write to the RX characteristic is one message; over USB,
// messages are newline-terminated. Both paths feed the same handler.
//
// Screens use the original Figma backgrounds (docs/design, exported to screens.h).
// Alerts overlay a readable vibration rhythm and a captured-direction strip;
// unknown event names use a plain text fallback.
//
// The alert stays up for ALERT_MS or until the screen is tapped / BOOT is pressed.
// Each alert also vibrates (130 motor on GPIO17 through a PN2222 + 1N4007,
// see hardware/README wiring): the pattern identifies the sound type, so the
// user can learn a distinct rhythm for each sound type without looking.
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
#include "sound_title_font.h"
#include "alert_protocol.h"
#include "event_haptics.h"
#include "analytics_compatibility.h"
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
const uint32_t LIVE_BADGE_MS = 1500; // a stalled display stream becomes RECENT
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
bool liveDisplayActive = false;
bool liveDisplayDismissed = false;
uint16_t liveBadgeColour = C_BLACK;
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

struct EventStyle {
  const char *name;   // as sent by the Mac
  const char *title;  // shown on screen
  const char *hint;
  uint16_t colour;
  const char *image;  // screen name in screens.h
};

// Names the Mac doesn't send yet still show up, using the fallback style below.
const EventStyle EVENT_STYLES[] = {
    {"ALARM", "ALARM!", "Alarm or siren nearby", C_RED, "alarm"},
    {"CAR_HORN", "CAR HORN", "Vehicle honking nearby", C_ORANGE, "car_horn"},
    {"GLASS", "GLASS", "Something broke", C_CRIMSON, "glass"},
    {"SHOUT", "SHOUT!", "Someone is shouting", C_MAGENTA, "shout"},
    {"BABY", "BABY", "Baby crying", C_TEAL, "baby"},
    {"KNOCK", "KNOCK", "Someone at the door", C_BLUE, "knock"},
    {"DOORBELL", "DOORBELL", "Someone at the door", C_PURPLE, "doorbell"},
    {"PHONE", "PHONE", "Phone ringing", C_SLATE, "phone"},
    {"DOG", "DOG", "Dog barking", C_BROWN, "dog"},
    {"SPEECH", "SPEECH", "Someone is talking nearby", C_DARKGREEN, "speech"},
};

// Non-blocking vibration player, stepped from loop().
const fortwatch::HapticPattern *vibPattern = nullptr;
uint8_t vibStep = 0;
uint32_t vibStepStartedMs = 0;

void stopVibration() {
  vibPattern = nullptr;
  vibStep = 0;
  digitalWrite(PIN_MOTOR, LOW);
}

void vibrate(const fortwatch::HapticPattern &pattern) {
  if (pattern.durationCount == 0) { stopVibration(); return; }
  vibPattern = &pattern;
  vibStep = 0;
  vibStepStartedMs = millis();
  digitalWrite(PIN_MOTOR, HIGH);  // even steps are "on"
}

void updateVibration() {
  if (vibPattern == nullptr) return;
  if (millis() - vibStepStartedMs < vibPattern->durations[vibStep]) return;
  vibStep++;
  vibStepStartedMs = millis();
  if (vibStep >= vibPattern->durationCount) {
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

// Reconstruct only the original title/hint area for a catalog-specific label.
// Smoothed clean corners avoid stretching image grain into vertical stripes.
uint16_t catalogTitleCorners[4];
uint16_t sampleCatalogBackground(const uint16_t *bg, int cx, int cy) {
  uint32_t r = 0, g = 0, b = 0;
  for (int y = cy - 2; y <= cy + 2; y++) for (int x = cx - 4; x <= cx + 4; x++) {
    const uint16_t colour = bg[y * 320 + x];
    r += colour >> 11; g += (colour >> 5) & 63; b += colour & 31;
  }
  return ((r / 45) << 11) | ((g / 45) << 5) | (b / 45);
}
uint16_t mixCatalogColour(uint16_t a, uint16_t b, int amount) {
  return blend565(a, (b >> 11) << 3, ((b >> 5) & 63) << 2, (b & 31) << 3, amount);
}
uint16_t catalogTitlePixel(const uint16_t *bg, int x, int y) {
  if (x < 100 || x >= 310 || y < 75 || y > 151) return bg[y * 320 + x];
  const int across = (x - 100) * 256 / 209;
  const uint16_t top = mixCatalogColour(catalogTitleCorners[0], catalogTitleCorners[1], across);
  const uint16_t bottom = mixCatalogColour(catalogTitleCorners[2], catalogTitleCorners[3], across);
  const uint16_t clean = mixCatalogColour(top, bottom, (y - 75) * 256 / 76);
  const int edge = min(256, min(min(x - 100, 309 - x) * 86, min(y - 75, 151 - y) * 64));
  return mixCatalogColour(bg[y * 320 + x], clean, edge);
}

// Draws text with its left edge at x and its baseline at y; returns the x after the text.
int drawText(const AtlasFont &f, const uint16_t *bg, int x, int y, const char *text,
             float opacity = 1.0f, uint8_t r = 255, uint8_t g = 255, uint8_t b = 255,
             uint16_t solidBackground = 0, bool catalogTitle = false) {
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
          const uint16_t base = bg ? (catalogTitle ? catalogTitlePixel(bg, gx + i, gy + j) :
                                     bg[(gy + j) * 320 + gx + i]) : solidBackground;
          glyphBuffer[j * gl.w + i] = blend565(base, r, g, b, a);
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
  vibrate(fortwatch::kFeedbackHaptics);
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

uint16_t catalogColour(uint32_t rgb) {
  return ((rgb >> 8) & 0xF800) | ((rgb >> 5) & 0x07E0) | ((rgb >> 3) & 0x001F);
}

const char *catalogImage(const SoundCatalogEntry &entry) {
  for (const EventStyle &style : EVENT_STYLES)
    if (strcmp(entry.hapticEvent, style.name) == 0) return style.image;
  if (strcmp(entry.family, "HUMAN") == 0) return "speech";
  if (strcmp(entry.family, "ANIMAL") == 0) return "dog";
  if (strcmp(entry.family, "VEHICLE") == 0) return "car_horn";
  if (strcmp(entry.family, "HOUSEHOLD") == 0) return "knock";
  if (strcmp(entry.family, "MUSIC") == 0) return "doorbell";
  if (strcmp(entry.family, "NATURE") == 0) return "baby";
  return "phone";  // neutral device palette for MACHINE / OTHER
}

int catalogTextWidth(const AtlasFont &font, const char *text) {
  int width = 0;
  for (const char *p = text; *p; p++) {
    const uint8_t c = uint8_t(*p);
    if (c >= font.first && c <= font.last) width += font.glyphs[c - font.first].adv + font.tracking;
  }
  return width;
}

int catalogTitleLines(const AtlasFont &font, const char *text, char lines[3][48]) {
  int lineCount = 0;
  while (*text && lineCount < 3) {
    char *part = lines[lineCount];
    int count = 0, lastSpace = -1;
    while (text[count] && count < 47) {
      part[count] = text[count]; part[count + 1] = '\0';
      if (catalogTextWidth(font, part) > 198 && count > 0) break;
      if (text[count] == ' ') lastSpace = count;
      count++;
    }
    // An oversized word should use the smaller native font, not split into
    // misleading fragments such as "Conversatio" / "n".
    if (text[count] && text[count] != ' ' && lastSpace < 0) return 4;
    if (text[count] && lastSpace > 0) count = lastSpace;
    part[count] = '\0'; text += count;
    while (*text == ' ') text++;
    lineCount++;
  }
  return *text ? 4 : lineCount;
}

int catalogTitleX(const AtlasFont &font, const char *line) {
  const uint8_t first = uint8_t(*line);
  if (first >= font.first && first <= font.last) {
    const int overhang = font.glyphs[first - font.first].xoff;
    if (overhang < 0) return 106 - overhang;
  }
  return 106;
}

bool catalogTitleFits(const AtlasFont &font, const char lines[3][48], int count,
                      int firstBaseline, int lineSpacing) {
  for (int line = 0; line < count; line++) {
    int x = catalogTitleX(font, lines[line]);
    const int baseline = firstBaseline + line * lineSpacing;
    for (const char *p = lines[line]; *p; p++) {
      const uint8_t c = uint8_t(*p);
      if (c < font.first || c > font.last) return false;
      const Glyph &g = font.glyphs[c - font.first];
      if (g.w && g.h && (x + g.xoff < 106 || x + g.xoff + g.w > 305 ||
                        baseline + g.yoff < 75 || baseline + g.yoff + g.h > 151)) return false;
      x += g.adv + font.tracking;
    }
  }
  return true;
}

const AtlasFont &catalogTitleLayout(const char *title, char lines[3][48], int &count,
                                   int &firstBaseline, int &lineSpacing) {
  // Native 32 px glyphs keep short class names as prominent as the original
  // artwork. Long names retain all their words in up to three native 20 px lines.
  count = catalogTitleLines(F_SOUND_TITLE, title, lines);
  firstBaseline = count == 1 ? 124 : 103;
  lineSpacing = 35;
  if (count <= 2 && catalogTitleFits(F_SOUND_TITLE, lines, count, firstBaseline, lineSpacing))
    return F_SOUND_TITLE;
  count = catalogTitleLines(F_TITLE, title, lines);
  firstBaseline = count == 1 ? 117 : count == 2 ? 104 : 91;
  lineSpacing = 23;
  return F_TITLE;
}

void catalogHistoryTitle(const char *title) {
  strncpy(lastAlertTitle, title, sizeof(lastAlertTitle) - 1);
  lastAlertTitle[sizeof(lastAlertTitle) - 1] = '\0';
  if (strlen(title) < sizeof(lastAlertTitle) && catalogTextWidth(F_TITLE, title) <= 130) return;
  size_t n = min(strlen(lastAlertTitle), sizeof(lastAlertTitle) - 4);
  do {
    lastAlertTitle[n] = '\0';
    strcat(lastAlertTitle, "...");
    if (catalogTextWidth(F_TITLE, lastAlertTitle) <= 130 || n == 0) break;
    n--;
  } while (true);
}

void drawCatalogIcon(const SoundCatalogEntry &entry) {
  // Specific legacy exceptions retain their original large icon. The remaining
  // icons identify only a family, never pretend to distinguish all 521 classes.
  if (fortwatch::hapticsForKey(entry.hapticEvent)) {
    for (const EventStyle &style : EVENT_STYLES)
      if (strcmp(entry.hapticEvent, style.name) == 0) return;
  }
  const bool music = strcmp(entry.family, "MUSIC") == 0;
  const bool nature = strcmp(entry.family, "NATURE") == 0;
  const bool machine = strcmp(entry.family, "MACHINE") == 0;
  const bool home = strcmp(entry.family, "HOUSEHOLD") == 0;
  const bool other = strcmp(entry.family, "OTHER") == 0;
  if (!music && !nature && !machine && !home && !other) return;
  const uint16_t colour = catalogColour(entry.colorHex);
  gfx->fillCircle(54, 114, 33, colour);
  if (music) {
    gfx->fillRect(48, 99, 3, 27, C_WHITE); gfx->fillRect(66, 95, 3, 27, C_WHITE);
    gfx->fillTriangle(48, 99, 69, 95, 69, 102, C_WHITE);
    gfx->fillTriangle(48, 99, 48, 106, 69, 102, C_WHITE);
    gfx->fillCircle(44, 126, 6, C_WHITE); gfx->fillCircle(62, 122, 6, C_WHITE);
  } else if (nature) {
    gfx->fillTriangle(39, 128, 42, 105, 70, 98, C_WHITE);
    gfx->fillTriangle(39, 128, 70, 98, 65, 120, C_WHITE);
    gfx->drawLine(42, 124, 65, 104, colour); gfx->drawLine(43, 124, 66, 104, colour);
  } else if (machine) {
    gfx->fillCircle(54, 114, 13, C_WHITE);
    for (int i = 0; i < 8; i++) {
      const float a = i * 0.7853981634f;
      gfx->fillCircle(54 + int(roundf(sinf(a) * 15)), 114 - int(roundf(cosf(a) * 15)), 3, C_WHITE);
    }
    gfx->fillCircle(54, 114, 6, colour);
  } else if (home) {
    gfx->fillTriangle(35, 110, 54, 95, 73, 110, C_WHITE);
    gfx->fillRect(40, 108, 28, 23, C_WHITE); gfx->fillRect(50, 117, 8, 14, colour);
  } else {
    gfx->fillRoundRect(40, 106, 4, 16, 2, C_WHITE);
    gfx->fillRoundRect(52, 99, 4, 30, 2, C_WHITE);
    gfx->fillRoundRect(64, 103, 4, 22, 2, C_WHITE);
    if (entry.isQuiet) {
      gfx->drawLine(36, 98, 72, 130, colour);
      gfx->drawLine(36, 99, 72, 131, C_WHITE);
      gfx->drawLine(36, 100, 72, 132, C_WHITE);
    }
  }
}

bool catalogSameTitle(const char *a, const char *b) {
  while (*a && *b) {
    char ac = *a >= 'a' && *a <= 'z' ? *a - 'a' + 'A' : *a;
    char bc = *b >= 'a' && *b <= 'z' ? *b - 'a' + 'A' : *b;
    if (ac != bc) return false;
    a++; b++;
  }
  if (*a == '!') a++;
  if (*b == '!') b++;
  return !*a && !*b;
}

bool catalogUsesOriginalTitle(const SoundCatalogEntry &entry) {
  // YAMNet's broad Glass class includes clinks; the legacy card's baked-in
  // "Something broke" hint is only retained for the explicit E,GLASS alert.
  if (strcmp(entry.name, "Glass") == 0) return false;
  for (const EventStyle &style : EVENT_STYLES)
    if (strcmp(entry.hapticEvent, style.name) == 0 &&
        (catalogSameTitle(entry.title, style.title) || catalogSameTitle(entry.title, style.hint))) return true;
  return false;
}

void drawCatalogCard(const SoundCatalogEntry &entry, const uint16_t *bg) {
  gfx->draw16bitRGBBitmap(0, 0, bg, 320, 240);
  // Retain the original large artwork when it already names this exact class;
  // descendants such as Bellow must display their own name, not just SHOUT.
  if (!catalogUsesOriginalTitle(entry)) {
    catalogTitleCorners[0] = sampleCatalogBackground(bg, 100, 75);
    catalogTitleCorners[1] = sampleCatalogBackground(bg, 309, 75);
    catalogTitleCorners[2] = sampleCatalogBackground(bg, 100, 151);
    catalogTitleCorners[3] = sampleCatalogBackground(bg, 309, 151);
    for (int row = 75; row <= 150; row += 16) {
      const int rows = min(16, 151 - row);
      for (int y = 0; y < rows; y++) for (int x = 0; x < 210; x++)
        blitBuffer[y * 210 + x] = catalogTitlePixel(bg, 100 + x, row + y);
      gfx->draw16bitRGBBitmap(100, row, blitBuffer, 210, rows);
    }
    char lines[3][48] = {};
    int count, firstBaseline, lineSpacing;
    const AtlasFont &font = catalogTitleLayout(entry.title, lines, count, firstBaseline, lineSpacing);
    for (int i = 0; i < min(count, 3); i++)
      drawText(font, bg, catalogTitleX(font, lines[i]), firstBaseline + i * lineSpacing,
               lines[i], 1.0f, 255, 255, 255, 0, true);
  }
  const uint16_t pill = blend565(catalogColour(entry.colorHex), 0, 0, 0, 70);
  gfx->fillRoundRect(15, 12, 102, 27, 13, pill);
  drawText(F_SMALL, nullptr, 26, 29, entry.family, 1.0f, 255, 255, 255, pill);
  drawCatalogIcon(entry);
}

const char *alertDirectionLabel(float angle) {
  const float magnitude = fabsf(angle);
  if (magnitude < 22.5f) return "AHEAD";
  if (magnitude < 67.5f) return angle < 0 ? "AHEAD LEFT" : "AHEAD RIGHT";
  if (magnitude < 112.5f) return angle < 0 ? "LEFT" : "RIGHT";
  if (magnitude < 157.5f) return angle < 0 ? "BEHIND LEFT" : "BEHIND RIGHT";
  return "BEHIND";
}

void drawAlertDirection(const fortwatch::AlertMessage &message, const uint16_t *bg) {
  // Preserve the original Figma title/icon. A filled 32px arrow and a large
  // eight-sector label use only y153..185; degrees are secondary to orientation.
  const int cx = 28, cy = 169;
  const bool hasDirection = fortwatch::hasUsableDirection(message);
  const char *label = hasDirection ? alertDirectionLabel(message.angleDegrees) : "DIRECTION UNKNOWN";
  if (hasDirection) {
    const float a = message.angleDegrees * 0.01745329252f;
    const float dx = sinf(a), dy = -cosf(a), px = -dy, py = dx;
    const int tx = cx - int(roundf(dx * 12)), ty = cy - int(roundf(dy * 12));
    const int bx = cx + int(roundf(dx * 3)), by = cy + int(roundf(dy * 3));
    const int sx = int(roundf(px * 3)), sy = int(roundf(py * 3));
    gfx->fillTriangle(tx + sx, ty + sy, tx - sx, ty - sy, bx + sx, by + sy, C_WHITE);
    gfx->fillTriangle(tx - sx, ty - sy, bx - sx, by - sy, bx + sx, by + sy, C_WHITE);
    gfx->fillTriangle(cx + int(roundf(dx * 16)), cy + int(roundf(dy * 16)),
                      bx + int(roundf(px * 9)), by + int(roundf(py * 9)),
                      bx - int(roundf(px * 9)), by - int(roundf(py * 9)), C_WHITE);
  } else if (bg) {
    drawText(F_TITLE, bg, 22, 177, "?", 0.85f);
  }
  if (bg) {
    drawText(F_TITLE, bg, 54, 172, label);
    // This is the dominant sound captured with the alert, not live tracking or
    // a source isolated to the sound category. Unknown never implies a bearing.
    drawText(F_BODY, bg, 54, 184, hasDirection ? "CAPTURED / RELATIVE TO PHONE" :
                                              "NO RELIABLE DIRECTION");
  } else {
    drawCentered(label, 154, 2, C_WHITE);
    drawCentered(hasDirection ? "CAPTURED / RELATIVE TO PHONE" : "NO RELIABLE DIRECTION",
                  178, 1, C_WHITE);
  }
}

void drawAlertBrand(const uint16_t *bg, uint16_t fallback) {
  // Original priority and VIB pills leave this top-center gap free.
  drawText(F_SMALL, bg, 125, 29, "fortwatch", 0.95f, 255, 255, 255, fallback);
}

uint16_t alertPillColour(const uint16_t *bg, uint16_t fallback) {
  return blend565(bg ? bg[40 * 320 + 260] : fallback, 0, 0, 0, 90);
}

void drawAlertVibration(const fortwatch::HapticPattern &pattern, const uint16_t *bg,
                         uint16_t fallback) {
  // Cover the baked priority-based VIB pill with the actual type-specific rhythm.
  // The larger rounded capsule encloses every old VIB pill; the rest is untouched.
  const uint16_t pill = alertPillColour(bg, fallback);
  gfx->fillRoundRect(190, 12, 116, 27, 13, pill);
  drawText(F_TINY, nullptr, 199, 29, "VIB", 0.95f, 255, 255, 255, pill);
  if (pattern.durationCount == 0) {
    drawText(F_TINY, nullptr, 252, 29, "OFF", 1.0f, 255, 255, 255, pill);
    return;
  }
  int width = 0;
  for (int i = 0; i < pattern.durationCount; i += 2) {
    width += pattern.durations[i] >= 300 ? 15 : 7;
    if (i + 1 < pattern.durationCount) width += pattern.durations[i + 1] >= 300 ? 11 : 5;
  }
  int x = 263 - width / 2;
  for (int i = 0; i < pattern.durationCount; i += 2) {
    const int pulseWidth = pattern.durations[i] >= 300 ? 15 : 7;
    gfx->fillRoundRect(x, 23, pulseWidth, 5, 2, C_WHITE);
    x += pulseWidth;
    if (i + 1 < pattern.durationCount) x += pattern.durations[i + 1] >= 300 ? 11 : 5;
  }
}

void drawAlertRhythm(const fortwatch::HapticPattern &pattern, const uint16_t *bg,
                      uint16_t fallback) {
  // Deliberately replace the tiny, uncalibrated confidence visualization with
  // the learnable motor rhythm. The classification score still reaches analytics.
  const uint16_t pill = alertPillColour(bg, fallback);
  gfx->fillRoundRect(13, 190, 294, 18, 5, pill);
  drawText(F_SMALL, nullptr, 23, 202, "VIBRATION", 0.90f, 255, 255, 255, pill);
  drawText(F_BODY, nullptr, 99, 202, pattern.label, 1.0f, 255, 255, 255, pill);
}

void drawPatternTest(const fortwatch::HapticPattern &pattern, const uint16_t *bg,
                      uint16_t fallback) {
  const uint16_t pill = alertPillColour(bg, fallback);
  gfx->fillRoundRect(15, 12, 102, 27, 13, pill);
  drawText(F_BODY, nullptr, 34, 30, "TEST", 1.0f, 255, 255, 255, pill);
  if (bg) {
    drawText(F_TITLE, bg, 16, 172, "PATTERN TEST");
    drawText(F_BODY, bg, 16, 183, pattern.label);
  } else {
    drawCentered("PATTERN TEST", 154, 2, C_WHITE);
    drawCentered(pattern.label, 178, 1, C_WHITE);
  }
  // Hide both the baked CONFIDENCE text and score track on manual tests.
  gfx->fillRoundRect(13, 190, 294, 18, 5, pill);
  drawText(F_BODY, nullptr, 60, 203, "Manual test - no sound detected", 1.0f,
           255, 255, 255, pill);
}

void queueCompatibleAnalytics(const char *event, float score) {
  if (const char *compatible = fortwatch::dashboardEventForAlert(event)) {
    analyticsAlert(compatible, score);
    return;
  }
  static bool hasLogged = false;
  static uint32_t lastLogMs = 0;
  if (!hasLogged || millis() - lastLogMs >= 30000) {
    Serial.printf("Analytics: %s stays local; catalog dashboard support pending\n", event);
    hasLogged = true;
    lastLogMs = millis();
  }
}

void drawLiveStateBadge(const char *label) {
  gfx->fillRoundRect(15, 12, 102, 27, 13, liveBadgeColour);
  drawText(F_BODY, nullptr, 34, 30, label, 1.0f, 255, 255, 255, liveBadgeColour);
}

void dismissAlert() {
  liveDisplayDismissed = true;
  liveDisplayActive = false;
  showListening();
}

void expireLiveDisplay() {
  if (screen != Screen::Alert) { liveDisplayActive = false; return; }
  if (liveDisplayActive && millis() - alertStartedMs >= LIVE_BADGE_MS) {
    liveDisplayActive = false;
    drawLiveStateBadge("RECENT");
  }
}

void showAlert(const fortwatch::AlertMessage &message, bool isTest = false, bool isLive = false) {
  // A manual test interrupts the previous rhythm before repainting the card.
  if (isTest) stopVibration();
  const char *eventName = message.event;
  const float score = message.score;
  const EventStyle *style = nullptr;
  for (const EventStyle &candidate : EVENT_STYLES) {
    if (strcmp(candidate.name, eventName) == 0) style = &candidate;
  }
  const SoundCatalogEntry *catalog = lookupSoundCatalog(eventName);
  EventStyle fallback;
  if (catalog) {
    fallback = {eventName, catalog->title, catalog->name, catalogColour(catalog->colorHex), catalogImage(*catalog)};
    style = &fallback;
  }
  char fallbackTitle[24];
  if (style == nullptr) {
    // Unknown name: show it as-is ("WATER_TAP" -> "WATER TAP").
    strncpy(fallbackTitle, eventName, sizeof(fallbackTitle) - 1);
    fallbackTitle[sizeof(fallbackTitle) - 1] = '\0';
    for (char *c = fallbackTitle; *c; c++) {
      if (*c == '_') *c = ' ';
    }
    fallback = {eventName, fallbackTitle, "Sound detected", C_UNKNOWN, nullptr};
    style = &fallback;
  }

  screen = Screen::Alert;
  alertStartedMs = millis();
  liveDisplayActive = isLive;
  if (!isTest && !isLive) {
    liveDisplayDismissed = false;
    alertCount++;
    strncpy(lastAlertTitle, style->title, sizeof(lastAlertTitle) - 1);
    lastAlertTitle[sizeof(lastAlertTitle) - 1] = '\0';
    lastAlertMs = millis();
    lastAlertIcon = catalog ? nullptr : style->image;
    if (catalog) catalogHistoryTitle(catalog->title);
    queueCompatibleAnalytics(eventName, score);
  }
  const fortwatch::HapticPattern &pattern = fortwatch::hapticsForEvent(eventName);
  // Keep a still-playing rhythm only when it also describes the new class.
  // Repeated same-family display updates must not cut that learned rhythm short.
  if (isLive && vibPattern && !fortwatch::sameHapticRhythm(*vibPattern, pattern)) stopVibration();
  fortwatch::AlertMessage visualMessage = message;
  if (catalog && catalog->isQuiet) visualMessage.hasDirection = false;
  const uint16_t *img = style->image ? screenImage(style->image) : nullptr;
  if (img) {
    if (catalog) drawCatalogCard(*catalog, img);
    else gfx->draw16bitRGBBitmap(0, 0, img, 320, 240);
    if (!isTest) drawAlertDirection(visualMessage, img);
  } else {
    gfx->fillScreen(style->colour);
    drawCentered(style->title, 60, 6, C_WHITE);
    drawCentered(style->hint, 125, 2, C_WHITE);
    if (!isTest) drawAlertDirection(visualMessage, nullptr);
    drawCentered("Tap screen or press BOOT to dismiss", 225, 1, C_WHITE);
  }
  drawAlertBrand(img, style->colour);
  drawAlertVibration(pattern, img, style->colour);
  if (isTest) drawPatternTest(pattern, img, style->colour);
  else drawAlertRhythm(pattern, img, style->colour);
  if (isLive) {
    liveBadgeColour = alertPillColour(img, style->colour);
    drawLiveStateBadge("LIVE");
  } else {
    vibrate(pattern);
  }
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
  } else if (text[0] == 'P' && text[1] == ',') {
    const fortwatch::HapticPattern *pattern = nullptr;
    if (!fortwatch::parsePatternTest(text, pattern)) return;
    fortwatch::AlertMessage message;
    strncpy(message.event, text + 2, sizeof(message.event) - 1);
    showAlert(message, true);
  } else if ((text[0] == 'E' || text[0] == 'D') && text[1] == ',') {
    const bool isLive = text[0] == 'D';
    if (isLive && liveDisplayDismissed) return;
    fortwatch::AlertMessage message;
    if (!(isLive ? fortwatch::parseDisplay(text, message) : fortwatch::parseAlert(text, message))) return;
    const SoundCatalogEntry *catalog = lookupSoundCatalog(message.event);
    if (!speechEnabled && (strcmp(message.event, "SPEECH") == 0 ||
                          (catalog && strcmp(catalog->hapticEvent, "SPEECH") == 0))) return;
    showAlert(message, false, isLive);
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
  vibrate(fortwatch::kBootHaptics);
}

void loop() {
  readSerial();
  readBluetooth();
  updateVibration();
  expireLiveDisplay();
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
    if (dismissed) dismissAlert();
    else if (now - alertStartedMs >= ALERT_MS) showListening();
  } else if (screen == Screen::Listening && now - lastMessageMs > LINK_TIMEOUT_MS) {
    showWaiting();
  }
  delay(5);
}
