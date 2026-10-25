#!/usr/bin/env python3
"""Check the actual firmware title layout against all 521 catalog entries."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIRMWARE = ROOT / "live_demo/fortwatch_display"


def main():
    sketch = (FIRMWARE / "fortwatch_display.ino").read_text()
    parts = [
        sketch[sketch.index("// RGB565 colours"):sketch.index("Arduino_DataBus *bus")],
        sketch[sketch.index("struct EventStyle {"):sketch.index("// Non-blocking vibration player")],
        sketch[sketch.index("int catalogTextWidth("):sketch.index("void catalogHistoryTitle(")],
        sketch[sketch.index("bool catalogSameTitle("):sketch.index("void drawCatalogCard(")],
    ]
    prefix = r'''#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include "sound_title_font.h"
#include "sound_catalog.h"
'''
    tests = r'''
int main() {
  int large=0, small=0, original=0, maxGlyphPixels=0;
  for (int c=F_SOUND_TITLE.first; c<=F_SOUND_TITLE.last; c++) {
    const Glyph &g=F_SOUND_TITLE.glyphs[c-F_SOUND_TITLE.first];
    const int pixels=g.w*g.h;
    assert(pixels<=64*64 && g.offset+pixels<=sizeof(F_SOUND_TITLE_ALPHA));
    if(pixels>maxGlyphPixels)maxGlyphPixels=pixels;
  }
  for (const auto &entry:SOUND_CATALOG) {
    char lines[3][48]={}; int count=0,baseline=0,spacing=0;
    const auto &font=catalogTitleLayout(entry.title,lines,count,baseline,spacing);
    assert(count>=1 && count<=3);
    assert(&font==&F_SOUND_TITLE || &font==&F_TITLE);
    if(&font==&F_SOUND_TITLE){assert(count<=2);large++;}else small++;
    std::string rebuilt;
    for(int row=0;row<count;row++) {
      if(row)rebuilt+=' ';
      rebuilt+=lines[row];
      int x=catalogTitleX(font,lines[row]);
      for(const char *p=lines[row];*p;p++) {
        const int c=static_cast<unsigned char>(*p);
        assert(c>=font.first && c<=font.last);
        const Glyph &g=font.glyphs[c-font.first];
        if(g.w && g.h) {
          if(x+g.xoff<106 || x+g.xoff+g.w>305)
            std::cerr << "Horizontal glyph bounds: " << entry.title << " / " << lines[row]
                      << " char=" << *p << " x=" << x+g.xoff << ".." << x+g.xoff+g.w-1 << '\n';
          assert(x+g.xoff>=106 && x+g.xoff+g.w<=305);
          assert(baseline+row*spacing+g.yoff>=75);
          assert(baseline+row*spacing+g.yoff+g.h<=151);
        }
        x+=g.adv+font.tracking;
      }
    }
    if(rebuilt!=entry.title) {
      std::cerr << "Title words changed: " << entry.title << " -> " << rebuilt << '\n';
      return 1;
    }
    if(catalogUsesOriginalTitle(entry))original++;
    if(strcmp(entry.name,"Glass")==0)assert(!catalogUsesOriginalTitle(entry));
    if(strcmp(entry.name,"Knock")==0)assert(catalogUsesOriginalTitle(entry));
    if(strcmp(entry.title,"Cat")==0 || strcmp(entry.title,"Wind")==0 || strcmp(entry.title,"Piano")==0)
      assert(&font==&F_SOUND_TITLE);
  }
  std::cout << "PASS: all 521 titles preserve full words and ink bounds x106..304/y75..150; "
            << large << " use native 32 px, " << small << " use 20 px (" << original
            << " retain original artwork); max new glyph " << maxGlyphPixels
            << "/4096 scratch pixels; broad Glass uses its exact name.\n";
}
'''
    with tempfile.TemporaryDirectory(prefix="fortwatch-title-layout-") as directory:
        temp = Path(directory)
        source = temp / "layout.cpp"
        source.write_text(prefix + "\n".join(parts) + tests)
        executable = temp / "layout"
        subprocess.run(["xcrun", "clang++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-const-variable", "-fsanitize=address,undefined", "-I", str(FIRMWARE),
                        str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
