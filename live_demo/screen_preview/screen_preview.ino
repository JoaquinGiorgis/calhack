// SoundSense screen preview: slideshow of the Figma designs on the real wristband.
//
// Shows each 320x240 screen exported from Figma (docs/design/screens), so the team can
// judge colours, legibility and contrast on the actual 2" display before the designs are
// wired into the live firmware (live_demo/soundsense_display).
//
//   - Auto-advances every SLIDE_MS.
//   - BOOT button: next screen (pauses auto-advance for PAUSE_MS).
//   - Serial (115200): "n" next, "p" previous, "a" toggle autoplay.
//   - Alert screens also play their vibration pattern on the motor (GPIO17), so you can
//     feel the difference between Safety / Attention / Low.
//
// Regenerate screens.h after changing the designs:
//   python png_to_rgb565.py ../../docs/design/screens screens.h

#include <Arduino_GFX_Library.h>
#include "screens.h"

#define PIN_LCD_SCLK 39
#define PIN_LCD_MOSI 38
#define PIN_LCD_MISO 40
#define PIN_LCD_DC 42
#define PIN_LCD_RST -1
#define PIN_LCD_CS 45
#define PIN_LCD_BL 1
#define PIN_BOOT_BUTTON 0
#define PIN_MOTOR 17

const uint32_t SLIDE_MS = 3000;
const uint32_t PAUSE_MS = 10000;

Arduino_DataBus *bus = new Arduino_ESP32SPI(
    PIN_LCD_DC, PIN_LCD_CS, PIN_LCD_SCLK, PIN_LCD_MOSI, PIN_LCD_MISO);
Arduino_GFX *gfx = new Arduino_ST7789(
    bus, PIN_LCD_RST, 1 /* rotation: landscape, same as soundsense_display */, true /* IPS */, 240, 320);

// Same patterns as soundsense_display.ino (on/off ms, 0-terminated).
const uint16_t VIB_SAFETY[] = {400, 150, 400, 150, 400, 0};
const uint16_t VIB_ATTENTION[] = {150, 120, 150, 0};
const uint16_t VIB_LOW[] = {150, 0};

const uint16_t *vibPattern = nullptr;
uint8_t vibStep = 0;
uint32_t vibStepStartedMs = 0;

void vibrate(const uint16_t *pattern) {
  vibPattern = pattern;
  vibStep = 0;
  vibStepStartedMs = millis();
  digitalWrite(PIN_MOTOR, pattern ? HIGH : LOW);
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

const uint16_t *patternFor(const char *name) {
  // names look like "10_alarm", "15_knock"...
  const char *n = strchr(name, '_');
  n = n ? n + 1 : name;
  if (!strcmp(n, "alarm") || !strcmp(n, "car_horn") || !strcmp(n, "glass") || !strcmp(n, "shout")) return VIB_SAFETY;
  if (!strcmp(n, "baby") || !strcmp(n, "knock") || !strcmp(n, "doorbell") || !strcmp(n, "phone")) return VIB_ATTENTION;
  if (!strcmp(n, "dog") || !strcmp(n, "speech")) return VIB_LOW;
  return nullptr;  // system screens: no vibration
}

int current = 0;
bool autoplay = true;
uint32_t shownAtMs = 0;
uint32_t pausedUntilMs = 0;
bool lastButton = HIGH;

void show(int index) {
  current = (index + SCREEN_COUNT) % SCREEN_COUNT;
  gfx->draw16bitRGBBitmap(0, 0, SCREENS[current].pixels, 320, 240);
  shownAtMs = millis();
  vibrate(patternFor(SCREENS[current].name));
  Serial.printf("[%d/%d] %s\n", current + 1, SCREEN_COUNT, SCREENS[current].name);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT_BUTTON, INPUT_PULLUP);
  pinMode(PIN_MOTOR, OUTPUT);
  digitalWrite(PIN_MOTOR, LOW);
  if (!gfx->begin()) Serial.println("gfx->begin() failed!");
  pinMode(PIN_LCD_BL, OUTPUT);
  digitalWrite(PIN_LCD_BL, HIGH);
  show(0);
}

void loop() {
  uint32_t now = millis();
  updateVibration();

  bool button = digitalRead(PIN_BOOT_BUTTON);
  if (lastButton == HIGH && button == LOW) {  // press edge
    pausedUntilMs = now + PAUSE_MS;
    show(current + 1);
  }
  lastButton = button;

  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'n') show(current + 1);
    if (c == 'p') show(current - 1);
    if (c == 'a') { autoplay = !autoplay; Serial.printf("autoplay %s\n", autoplay ? "on" : "off"); }
  }

  if (autoplay && now > pausedUntilMs && now - shownAtMs >= SLIDE_MS) show(current + 1);
  delay(10);
}
