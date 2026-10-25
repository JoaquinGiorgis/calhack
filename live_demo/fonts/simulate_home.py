"""Preview the firmware-drawn Home screen on the PC, using the same atlases and layout
constants as fortwatch_display.ino. Usage: python simulate_home.py out.png"""
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
from make_font_atlas import FONTS, render

ROOT = Path(__file__).resolve().parents[2]
FONTS_BY = {f[0]: render(*f) for f in FONTS}

def draw_text(img, font, x, y_base, text, opacity=1.0, color=(255, 255, 255)):
    name, first, last, tracking, asc, desc, glyphs, data = FONTS_BY[font]
    px = img.load()
    for ch in text:
        code = 0x7F if ch == "·" else ord(ch)
        if not (ord(first) <= code <= ord(last)):
            continue
        off, w, h, xo, yo, adv = glyphs[code - ord(first)]
        for j in range(h):
            for i in range(w):
                a = data[off + j * w + i] / 255 * opacity
                if a <= 0:
                    continue
                X, Y = x + xo + i, y_base + yo + j
                if 0 <= X < img.width and 0 <= Y < img.height:
                    r, g, b = px[X, Y][:3]
                    px[X, Y] = (round(r + (color[0] - r) * a), round(g + (color[1] - g) * a), round(b + (color[2] - b) * a))
        x += adv + tracking

def bars(img, heights, color=(255, 255, 255), opacity=0.9, x0=24, bottom=200, w=6, step=9):
    px = img.load()
    for k, h in enumerate(heights):
        for j in range(h):
            for i in range(w):
                X, Y = x0 + k * step + i, bottom - 1 - j
                r, g, b = px[X, Y][:3]
                px[X, Y] = tuple(round(c + (t - c) * opacity) for c, t in zip((r, g, b), color))

img = Image.open(ROOT / "docs/design/firmware_screens/home.png").convert("RGB")
draw_text(img, "F_CLOCK", 14, 80, "10:24")
draw_text(img, "F_BODY", 18, 105, "Saturday, Oct 25", 0.85)
bars(img, [8, 12, 18, 26, 22, 30, 36, 28, 20, 24, 16, 11, 8, 6])
draw_text(img, "F_TINY", 24, 218, "iPhone mic · quiet", 0.7)
draw_text(img, "F_TITLE", 174, 179, "KNOCK")
draw_text(img, "F_SMALL", 174, 197, "2 min ago", 0.8)
draw_text(img, "F_TINY", 174, 218, "3 alerts today", 0.6)
ref = Image.open(ROOT / "docs/design/screens/01_home_sample.png").convert("RGB")
both = Image.new("RGB", (660, 240), (255, 255, 255)); both.paste(ref, (0, 0)); both.paste(img, (340, 0))
both.resize((1320, 480)).save(sys.argv[1])
