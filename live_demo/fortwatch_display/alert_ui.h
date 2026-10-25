#pragma once
#include "brand_fonts.h"

// 320x240 alert geometry. The ring owns x14..126/y54..166; precise sound names
// own x142..306/y65..139. Direction copy is below the name, rhythm at y195..221.
// All states use these same zones; no artwork is allowed to obscure live text.
int catalogTextWidth(const AtlasFont &font, const char *text) {
  int width = 0;
  for (const char *p = text; *p; p++) {
    const uint8_t c = uint8_t(*p);
    if (c >= font.first && c <= font.last) width += font.glyphs[c - font.first].adv + font.tracking;
  }
  return width;
}

int catalogTitleLines(const AtlasFont &font, const char *text, char lines[3][48], bool allowWordBreak = false) {
  int lineCount = 0;
  while (*text && lineCount < 3) {
    char *part = lines[lineCount];
    int count = 0, lastSpace = -1;
    while (text[count] && count < 47) {
      part[count] = text[count]; part[count + 1] = '\0';
      if (catalogTextWidth(font, part) > 164 && count > 0) break;
      if (text[count] == ' ') lastSpace = count;
      count++;
    }
    if (!allowWordBreak && text[count] && text[count] != ' ' && lastSpace < 0) return 4;
    if (text[count] && text[count] != ' ' && lastSpace > 0) count = lastSpace;
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
    if (overhang < 0) return 142 - overhang;
  }
  return 142;
}

bool catalogTitleFits(const AtlasFont &font, const char lines[3][48], int count,
                      int firstBaseline, int lineSpacing) {
  if (count < 1 || count > 3) return false;
  for (int line = 0; line < count; line++) {
    int x = catalogTitleX(font, lines[line]);
    const int baseline = firstBaseline + line * lineSpacing;
    for (const char *p = lines[line]; *p; p++) {
      const uint8_t c = uint8_t(*p);
      if (c < font.first || c > font.last) return false;
      const Glyph &g = font.glyphs[c - font.first];
      if (g.w && g.h && (x + g.xoff < 142 || x + g.xoff + g.w > 307 ||
                        baseline + g.yoff < 65 || baseline + g.yoff + g.h > 140)) return false;
      x += g.adv + font.tracking;
    }
  }
  return true;
}

const AtlasFont &catalogTitleLayout(const char *title, char lines[3][48], int &count,
                                   int &firstBaseline, int &lineSpacing) {
  count = catalogTitleLines(F_ALERT_TITLE, title, lines);
  firstBaseline = count == 1 ? 112 : 90;
  lineSpacing = 34;
  if (count <= 2 && catalogTitleFits(F_ALERT_TITLE, lines, count, firstBaseline, lineSpacing))
    return F_ALERT_TITLE;
  count = catalogTitleLines(F_ALERT_COMPACT, title, lines);
  firstBaseline = count == 1 ? 110 : count == 2 ? 96 : 82;
  lineSpacing = 24;
  if (catalogTitleFits(F_ALERT_COMPACT, lines, count, firstBaseline, lineSpacing)) return F_ALERT_COMPACT;
  // Only extension event names need this last resort. Their single token can be
  // 23 wide letters; all catalog entries are tested to fit the two display sizes.
  count = catalogTitleLines(F_ALERT_BODY, title, lines, true);
  firstBaseline = count == 1 ? 109 : count == 2 ? 99 : 90;
  lineSpacing = 18;
  return F_ALERT_BODY;
}

// Render-only helpers below use the sketch's existing strip and glyph buffers.
// No full framebuffer, new heap allocation, background animation or fake meter.
const uint16_t ALERT_LIME = 0x8EA7; // #8FD63D brand/case-lime from the landing
const uint16_t ALERT_WHITE = 0xF7BE;
const uint16_t ALERT_MUTED = 0xADB6;

bool alertRoundContains(int x, int y, int left, int top, int width, int height, int radius) {
  if (x < left || y < top || x >= left + width || y >= top + height) return false;
  const int localX = x - left, localY = y - top;
  const int dx = localX < radius ? radius - localX : localX >= width - radius ? localX - (width - radius - 1) : 0;
  const int dy = localY < radius ? radius - localY : localY >= height - radius ? localY - (height - radius - 1) : 0;
  return dx * dx + dy * dy <= radius * radius;
}

uint16_t alertBasePixel(int x, int y) {
  // A quiet graphite/smoke surface, brighter near the upper-left glass edge.
  // Integer falloff keeps the material inexpensive and deterministic on-device.
  const int dx = x - 68, dy = y - 48;
  const int glow = max(0, 28 - dx * dx / 1700 - dy * dy / 1100);
  // Ordered subpixel quantization avoids broad RGB565 colour bands; it is a
  // fixed material texture, not an animation or measured signal.
  static const uint8_t dither[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
  const int noise = dither[(y & 3) * 4 + (x & 3)];
  int r = 15 + glow / 3 + noise / 2, g = 19 + glow / 3 + noise / 4, b = 26 + glow / 3 + noise / 2;
  if (alertRoundContains(x, y, 214, 12, 92, 25, 12)) { r = 32; g = 38; b = 45; }
  if (alertRoundContains(x, y, 14, 195, 292, 27, 10)) {
    const bool edge = !alertRoundContains(x, y, 15, 196, 290, 25, 9);
    r = edge ? 48 : 29; g = edge ? 55 : 35; b = edge ? 63 : 43;
  }
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

void restoreAlertRegion(int x, int y, int width, int height) {
  for (int row = 0; row < height; row += 16) {
    const int rows = min(16, height - row);
    for (int j = 0; j < rows; j++) for (int i = 0; i < width; i++)
      blitBuffer[j * width + i] = alertBasePixel(x + i, y + row + j);
    gfx->draw16bitRGBBitmap(x, y + row, blitBuffer, width, rows);
  }
}

int drawAlertText(const AtlasFont &font, int x, int baseline, const char *text,
                  uint16_t colour = ALERT_WHITE) {
  for (const char *p = text; *p; p++) {
    const uint8_t code = uint8_t(*p);
    if (code < font.first || code > font.last) continue;
    const Glyph &g = font.glyphs[code - font.first];
    const int gx = x + g.xoff, gy = baseline + g.yoff;
    if (g.w && g.h && g.w * g.h <= int(sizeof(glyphBuffer) / 2) &&
        gx >= 0 && gy >= 0 && gx + g.w <= 320 && gy + g.h <= 240) {
      for (int j = 0; j < g.h; j++) for (int i = 0; i < g.w; i++)
        glyphBuffer[j * g.w + i] = blend565(alertBasePixel(gx + i, gy + j),
            (colour >> 11) << 3, ((colour >> 5) & 63) << 2, (colour & 31) << 3,
            font.alpha[g.offset + j * g.w + i]);
      gfx->draw16bitRGBBitmap(gx, gy, glyphBuffer, g.w, g.h);
    }
    x += g.adv + font.tracking;
  }
  return x;
}

void drawAlertBadge(const char *label) {
  restoreAlertRegion(214, 12, 92, 25);
  const int x = 260 - catalogTextWidth(F_ALERT_SMALL, label) / 2;
  drawAlertText(F_ALERT_SMALL, x, 29, label, strcmp(label, "LIVE") == 0 ? ALERT_LIME : ALERT_WHITE);
}

const char *alertDirectionLabel(float angle) {
  const float magnitude = fabsf(angle);
  if (magnitude < 22.5f) return "Ahead";
  if (magnitude < 67.5f) return angle < 0 ? "Ahead left" : "Ahead right";
  if (magnitude < 112.5f) return angle < 0 ? "Left" : "Right";
  if (magnitude < 157.5f) return angle < 0 ? "Behind left" : "Behind right";
  return "Behind";
}

void drawDirectionRing(bool hasDirection, float angleDegrees) {
  const int cx = 70, cy = 110, left = 14, top = 54, size = 113;
  const float angle = angleDegrees * 0.01745329252f;
  const float bearingX = sinf(angle), bearingY = -cosf(angle);
  for (int row = 0; row < size; row += 16) {
    const int rows = min(16, size - row);
    for (int j = 0; j < rows; j++) for (int i = 0; i < size; i++) {
      const int x = left + i, y = top + row + j;
      const float dx = x - cx, dy = y - cy, radius = sqrtf(dx * dx + dy * dy);
      uint16_t pixel = alertBasePixel(x, y);
      if (radius < 41) pixel = blend565(pixel, 39, 47, 54, uint16_t((41 - radius) * 3));
      const float rim = max(0.0f, 1.0f - fabsf(radius - 49.0f));
      if (rim > 0) pixel = blend565(pixel, 103, 113, 122, uint16_t(rim * 155));
      // Broad tapered crescent: zero is front/top; positive rotates clockwise.
      // A neutral ring has no lime segment and conveys no bearing at all.
      if (hasDirection && radius > 42 && radius < 55) {
        const float alignment = (dx * bearingX + dy * bearingY) / radius;
        const float taper = constrain((alignment - 0.819152f) / 0.180848f, 0.0f, 1.0f);
        if (taper > 0) {
          const float coverage = constrain(1.0f + 5.0f * taper - fabsf(radius - 49.0f), 0.0f, 1.0f);
          pixel = blend565(pixel, 143, 214, 61, uint16_t(coverage * 256));
        }
      }
      blitBuffer[j * size + i] = pixel;
    }
    gfx->draw16bitRGBBitmap(left, top + row, blitBuffer, size, rows);
  }
  // Phone silhouette is the coordinate reference, not a second sound marker.
  gfx->fillRoundRect(59, 92, 23, 36, 5, 0xBE18);
  gfx->fillRoundRect(61, 94, 19, 32, 3, 0x2126);
  gfx->fillRoundRect(66, 95, 9, 2, 1, 0xBE18);
  gfx->fillRoundRect(67, 122, 7, 2, 1, 0xBE18);
}

void drawAlertDirection(const fortwatch::AlertMessage &message, bool isTest = false, bool isRecent = false) {
  const bool hasDirection = !isTest && !isRecent && fortwatch::hasUsableDirection(message);
  restoreAlertRegion(14, 168, 113, 19);
  restoreAlertRegion(142, 145, 165, 42);
  drawDirectionRing(hasDirection, hasDirection ? message.angleDegrees : 0);
  drawAlertText(F_ALERT_SMALL, 38, 181, "YOUR PHONE", ALERT_MUTED);
  drawAlertText(F_ALERT_COMPACT, 142, 164,
                isTest ? "Pattern test" : isRecent ? "Recent sound" :
                hasDirection ? alertDirectionLabel(message.angleDegrees) : "Unknown");
  drawAlertText(F_ALERT_BODY, 142, 183,
                isTest ? "No sound detected" : isRecent ? "No live direction" :
                hasDirection ? "Relative to phone" : "No reliable direction", ALERT_MUTED);
}

void drawExpiredDirection() {
  fortwatch::AlertMessage empty;
  drawAlertDirection(empty, false, true);
}

void drawAlertIcon(const char *name, const char *family, uint16_t colour) {
  const uint8_t *mask = nullptr;
  for (int i = 0; i < ICON_COUNT; i++) if (name && strcmp(ICONS[i].name, name) == 0) mask = ICONS[i].alpha;
  if (mask) {
    for (int y = 0; y < ICON_SIZE; y++) for (int x = 0; x < ICON_SIZE; x++)
      glyphBuffer[y * ICON_SIZE + x] = blend565(alertBasePixel(282 + x, 43 + y),
          (colour >> 11) << 3, ((colour >> 5) & 63) << 2, (colour & 31) << 3, mask[y * ICON_SIZE + x]);
    gfx->draw16bitRGBBitmap(282, 43, glyphBuffer, ICON_SIZE, ICON_SIZE);
  } else if (strcmp(family, "MUSIC") == 0) {
    gfx->fillRect(287, 45, 2, 13, colour); gfx->fillRect(298, 43, 2, 13, colour);
    gfx->drawLine(288, 45, 299, 43, colour); gfx->drawLine(288, 46, 299, 44, colour);
    gfx->fillCircle(284, 58, 3, colour); gfx->fillCircle(295, 56, 3, colour);
  } else if (strcmp(family, "NATURE") == 0) {
    gfx->fillTriangle(283, 62, 286, 48, 302, 44, colour);
    gfx->fillTriangle(283, 62, 302, 44, 298, 58, colour);
    gfx->drawLine(285, 59, 298, 47, 0x2946);
  } else if (strcmp(family, "MACHINE") == 0) {
    gfx->fillCircle(292, 53, 7, colour);
    for (int i = 0; i < 8; i++) {
      const float a = i * 0.7853981634f;
      gfx->fillCircle(292 + int(roundf(sinf(a) * 8)), 53 - int(roundf(cosf(a) * 8)), 2, colour);
    }
    gfx->fillCircle(292, 53, 3, 0x2126);
  } else {
    gfx->fillRoundRect(282, 48, 3, 12, 1, colour);
    gfx->fillRoundRect(290, 43, 3, 19, 1, colour);
    gfx->fillRoundRect(298, 46, 3, 15, 1, colour);
  }
}

void drawAlertRhythm(const fortwatch::HapticPattern &pattern) {
  drawAlertText(F_ALERT_SMALL, 24, 212, "VIB", ALERT_MUTED);
  if (pattern.durationCount == 0) drawAlertText(F_ALERT_SMALL, 59, 212, "OFF", ALERT_WHITE);
  else {
    int x = 55;
    for (int i = 0; i < pattern.durationCount; i += 2) {
      const int width = pattern.durations[i] >= 300 ? 12 : 5;
      gfx->fillRoundRect(x, 206, width, 5, 2, ALERT_WHITE);
      x += width;
      if (i + 1 < pattern.durationCount) x += pattern.durations[i + 1] >= 300 ? 8 : 3;
    }
  }
  drawAlertText(F_ALERT_BODY, 116, 213, pattern.label);
}

void drawFortWatchAlert(const EventStyle &style, const SoundCatalogEntry *catalog,
                        const fortwatch::AlertMessage &message,
                        const fortwatch::HapticPattern &pattern, bool isTest, bool isLive) {
  restoreAlertRegion(0, 0, 320, 240);
  gfx->fillCircle(20, 24, 4, ALERT_LIME);
  drawAlertText(F_ALERT_COMPACT, 31, 30, "fortwatch");
  drawAlertBadge(isTest ? "TEST" : isLive ? "LIVE" : "CAPTURED");
  const char *family = catalog ? catalog->family : "SOUND";
  drawAlertText(F_ALERT_SMALL, 142, 55, family, ALERT_MUTED);
  const char *icon = style.image;
  if (catalog) {
    // A family rhythm is not a legacy category: MUSIC must not inherit the
    // doorbell artwork, nor NATURE the baby artwork from the old palette map.
    icon = nullptr;
    for (const EventStyle &legacy : EVENT_STYLES)
      if (strcmp(catalog->hapticEvent, legacy.name) == 0) icon = legacy.image;
    if (!icon) icon = strcmp(family, "HUMAN") == 0 ? "speech" : strcmp(family, "ANIMAL") == 0 ? "dog" :
                      strcmp(family, "VEHICLE") == 0 ? "car_horn" : strcmp(family, "HOUSEHOLD") == 0 ? "knock" : nullptr;
  }
  drawAlertIcon(icon, family, catalog ? catalogColour(catalog->signalHex) : blend565(style.colour, 255, 255, 255, 100));
  char lines[3][48] = {}; int count, baseline, spacing;
  const AtlasFont &font = catalogTitleLayout(style.title, lines, count, baseline, spacing);
  if (count <= 3 && catalogTitleFits(font, lines, count, baseline, spacing)) {
    for (int i = 0; i < count; i++)
      drawAlertText(font, catalogTitleX(font, lines[i]), baseline + i * spacing, lines[i]);
  }
  drawAlertDirection(message, isTest);
  drawAlertRhythm(pattern);
  drawAlertText(F_ALERT_SMALL, 89, 237, "Tap or BOOT to dismiss", ALERT_MUTED);
}
