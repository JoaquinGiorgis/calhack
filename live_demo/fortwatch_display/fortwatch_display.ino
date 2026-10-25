// FortWatch wristband display for the Waveshare ESP32-S3-Touch-LCD-2.
//
// Receives text messages from live_demo/mac_listener.py over Bluetooth LE
// (device name "FortWatch") or over the USB cable:
//   L,<0-100>            sound level -> live level bar
//   E,<EVENT>,<score>    detected event -> full-screen alert
//
// Over BLE, each write to the RX characteristic is one message; over USB,
// messages are newline-terminated. Both paths feed the same handler.
//
// Screens are the Figma designs (docs/design, exported to screens.h as RGB565):
// the firmware draws the background image and only the live parts on top
// (confidence bar, level meter, alert count, link name). Unknown alert names fall
// back to the plain text screen.
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
#include <Wire.h>
#include "screens.h"
#include "fonts.h"
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
char line[64];
size_t lineLength = 0;
const char *linkName = "";  // "Bluetooth" or "USB", shown on the listening screen

// BLE callbacks run on the Bluetooth task, so they only queue messages;
// loop() does all drawing, keeping the display on a single task.
struct BleMessage {
  char text[64];
};
QueueHandle_t bleQueue;
volatile bool bleConnected = false;

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    BleMessage message;
    size_t length = min(value.length(), sizeof(message.text) - 1);
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

// Alert icon (alpha mask from icons.h) blended over the background.
void drawIcon(const uint16_t *bg, const char *name, int x, int y, float opacity = 1.0f) {
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
    return;
  }
  gfx->fillScreen(C_BLACK);
  drawCentered("LISTENING...", 40, 3, C_GREEN);
  char footer[32];
  snprintf(footer, sizeof(footer), "Alerts: %lu  |  %s", (unsigned long)alertCount, linkName);
  drawCentered(footer, 205, 2, C_GREY);
}

void showAlert(const char *eventName, float score) {
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
  const uint16_t *img = style->image ? screenImage(style->image) : nullptr;
  if (img) {
    gfx->draw16bitRGBBitmap(0, 0, img, 320, 240);
    // live confidence bar over the empty track from Figma (x85 y196, 219x6)
    int w = constrain(int(219 * score), 6, 219);
    gfx->fillRoundRect(85, 196, w, 6, 3, C_WHITE);
    vibrate(style->vibration);
    return;
  }
  gfx->fillScreen(style->colour);
  drawCentered(style->title, 60, 6, C_WHITE);
  drawCentered(style->hint, 140, 2, C_WHITE);
  char detail[32];
  snprintf(detail, sizeof(detail), "confidence %d%%", (int)(score * 100));
  drawCentered(detail, 175, 2, C_WHITE);
  drawCentered("Press BOOT to dismiss", 215, 1, C_WHITE);
  vibrate(style->vibration);
}

void handleLine(char *text) {
  lastMessageMs = millis();
  if (text[0] == 'L' && text[1] == ',') {
    int level = constrain(atoi(text + 2), 0, 100);
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
    char *eventName = text + 2;
    char *comma = strchr(eventName, ',');
    float score = 0;
    if (comma != nullptr) {
      *comma = '\0';
      score = atof(comma + 1);
    }
    showAlert(eventName, score);
  }
}

void readSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      line[lineLength] = '\0';
      if (lineLength > 0) {
        linkName = "USB";
        handleLine(line);
      }
      lineLength = 0;
    } else if (lineLength < sizeof(line) - 1) {
      line[lineLength++] = c;
    } else {
      lineLength = 0;  // overlong garbage line: drop it
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

// CST816 touch: register 0x02 = number of fingers on the screen.
bool touchReady = false;
bool screenTouched() {
  if (!touchReady) return false;
  Wire.beginTransmission(TOUCH_ADDR);
  Wire.write(0x02);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(TOUCH_ADDR, 1) != 1) return false;
  return (Wire.read() & 0x0F) > 0;
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
  startBluetooth();
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

  if (screen == Screen::Alert) {
    bool dismissed = digitalRead(PIN_BOOT_BUTTON) == LOW || (tap && now - alertStartedMs > 300);
    if (dismissed || now - alertStartedMs >= ALERT_MS) showListening();
  } else if (screen == Screen::Listening && now - lastMessageMs > LINK_TIMEOUT_MS) {
    showWaiting();
  }
  delay(5);
}
