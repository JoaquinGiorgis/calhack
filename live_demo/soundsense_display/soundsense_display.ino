// SoundSense wristband display for the Waveshare ESP32-S3-Touch-LCD-2.
//
// Receives text messages from live_demo/mac_listener.py over Bluetooth LE
// (device name "SoundSense") or over the USB cable:
//   L,<0-100>            sound level -> live level bar
//   E,<EVENT>,<score>    detected event -> full-screen alert
//
// Over BLE, each write to the RX characteristic is one message; over USB,
// messages are newline-terminated. Both paths feed the same handler.
//
// The alert stays up for ALERT_MS or until the BOOT button is pressed.
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

#define PIN_LCD_SCLK 39
#define PIN_LCD_MOSI 38
#define PIN_LCD_MISO 40
#define PIN_LCD_DC 42
#define PIN_LCD_RST -1
#define PIN_LCD_CS 45
#define PIN_LCD_BL 1
#define PIN_BOOT_BUTTON 0

const uint32_t ALERT_MS = 6000;      // how long an alert stays on screen
const uint32_t LINK_TIMEOUT_MS = 3000;  // no data for this long -> "waiting for Mac"

// Must match BLE_SERVICE_UUID / BLE_RX_UUID in mac_listener.py.
const char *BLE_NAME = "SoundSense";
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

struct EventStyle {
  const char *name;   // as sent by the Mac
  const char *title;  // shown on screen
  const char *hint;
  uint16_t colour;
};

// Names the Mac doesn't send yet still show up, using the fallback style below.
const EventStyle EVENT_STYLES[] = {
    {"ALARM", "ALARM!", "Alarm or siren nearby", C_RED},
    {"CAR_HORN", "CAR HORN", "Vehicle honking nearby", C_ORANGE},
    {"GLASS", "GLASS", "Something broke", C_CRIMSON},
    {"SHOUT", "SHOUT!", "Someone is shouting", C_MAGENTA},
    {"BABY", "BABY", "Baby crying", C_TEAL},
    {"KNOCK", "KNOCK", "Someone at the door", C_BLUE},
    {"DOORBELL", "DOORBELL", "Someone at the door", C_PURPLE},
    {"PHONE", "PHONE", "Phone ringing", C_SLATE},
    {"DOG", "DOG", "Dog barking", C_BROWN},
    {"SPEECH", "SPEECH", "Someone is talking nearby", C_DARKGREEN},
};

void drawCentered(const char *text, int y, uint8_t size, uint16_t colour) {
  // Shrink until the text fits; the built-in font is 6x8 pixels per size step.
  while (size > 1 && (int)strlen(text) * 6 * size > gfx->width() - 10) size--;
  gfx->setTextSize(size);
  gfx->setTextColor(colour);
  int width = strlen(text) * 6 * size;
  gfx->setCursor((gfx->width() - width) / 2, y);
  gfx->print(text);
}

void drawLevelBar(int level) {
  const int x = 20, y = 150, w = gfx->width() - 40, h = 28;
  int filled = w * level / 100;
  uint16_t colour = level > 75 ? C_RED : level > 50 ? C_ORANGE : C_GREEN;
  gfx->fillRect(x, y, filled, h, colour);
  gfx->fillRect(x + filled, y, w - filled, h, C_DARK);
  gfx->drawRect(x - 1, y - 1, w + 2, h + 2, C_GREY);
}

void showWaiting() {
  screen = Screen::Waiting;
  gfx->fillScreen(C_BLACK);
  drawCentered("SoundSense", 50, 4, C_WHITE);
  drawCentered("Waiting for Mac...", 120, 2, C_GREY);
  drawCentered("Bluetooth: SoundSense", 160, 2, C_GREY);
  drawCentered("or plug in USB", 190, 2, C_GREY);
}

void showListening() {
  screen = Screen::Listening;
  lastLevel = -1;
  gfx->fillScreen(C_BLACK);
  drawCentered("LISTENING...", 40, 3, C_GREEN);
  drawCentered("Sound level", 120, 2, C_GREY);
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
    fallback = {eventName, fallbackTitle, "Sound detected", C_UNKNOWN};
    style = &fallback;
  }

  screen = Screen::Alert;
  alertStartedMs = millis();
  alertCount++;
  gfx->fillScreen(style->colour);
  drawCentered(style->title, 60, 6, C_WHITE);
  drawCentered(style->hint, 140, 2, C_WHITE);
  char detail[32];
  snprintf(detail, sizeof(detail), "confidence %d%%", (int)(score * 100));
  drawCentered(detail, 175, 2, C_WHITE);
  drawCentered("Press BOOT to dismiss", 215, 1, C_WHITE);
}

void handleLine(char *text) {
  lastMessageMs = millis();
  if (text[0] == 'L' && text[1] == ',') {
    int level = constrain(atoi(text + 2), 0, 100);
    if (screen == Screen::Waiting) showListening();
    if (screen == Screen::Listening && level != lastLevel) {
      drawLevelBar(level);
      lastLevel = level;
    }
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

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT_BUTTON, INPUT_PULLUP);

  if (!gfx->begin()) {
    Serial.println("gfx->begin() failed!");
  }
  pinMode(PIN_LCD_BL, OUTPUT);
  digitalWrite(PIN_LCD_BL, HIGH);
  startBluetooth();
  showWaiting();
}

void loop() {
  readSerial();
  readBluetooth();
  uint32_t now = millis();

  if (screen == Screen::Alert) {
    bool dismissed = digitalRead(PIN_BOOT_BUTTON) == LOW;
    if (dismissed || now - alertStartedMs >= ALERT_MS) showListening();
  } else if (screen == Screen::Listening && now - lastMessageMs > LINK_TIMEOUT_MS) {
    showWaiting();
  }
  delay(5);
}
