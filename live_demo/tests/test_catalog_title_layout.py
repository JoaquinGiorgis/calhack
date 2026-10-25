#!/usr/bin/env python3
"""Check the actual firmware title layout against all 521 catalog entries."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIRMWARE = ROOT / "live_demo/fortwatch_display"


def main():
    helpers = (FIRMWARE / "alert_ui.h").read_text()
    parts = [helpers[helpers.index("int catalogTextWidth("):helpers.index("// Render-only helpers")]]
    prefix = r'''#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include "brand_fonts.h"
#include "sound_catalog.h"
'''
    tests = r'''
int main() {
  int large=0, small=0, maxGlyphPixels=0;
  for (int c=F_ALERT_TITLE.first; c<=F_ALERT_TITLE.last; c++) {
    const Glyph &g=F_ALERT_TITLE.glyphs[c-F_ALERT_TITLE.first];
    const int pixels=g.w*g.h;
    assert(pixels<=64*64 && g.offset+pixels<=sizeof(F_ALERT_TITLE_ALPHA));
    if(pixels>maxGlyphPixels)maxGlyphPixels=pixels;
  }
  for (const auto &entry:SOUND_CATALOG) {
    char lines[3][48]={}; int count=0,baseline=0,spacing=0;
    const auto &font=catalogTitleLayout(entry.title,lines,count,baseline,spacing);
    assert(count>=1 && count<=3);
    assert(&font==&F_ALERT_TITLE || &font==&F_ALERT_COMPACT);
    if(&font==&F_ALERT_TITLE){assert(count<=2);large++;}else small++;
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
          if(x+g.xoff<142 || x+g.xoff+g.w>307)
            std::cerr << "Horizontal glyph bounds: " << entry.title << " / " << lines[row]
                      << " char=" << *p << " x=" << x+g.xoff << ".." << x+g.xoff+g.w-1 << '\n';
          assert(x+g.xoff>=142 && x+g.xoff+g.w<=307);
          assert(baseline+row*spacing+g.yoff>=65);
          assert(baseline+row*spacing+g.yoff+g.h<=140);
        }
        x+=g.adv+font.tracking;
      }
    }
    if(rebuilt!=entry.title) {
      std::cerr << "Title words changed: " << entry.title << " -> " << rebuilt << '\n';
      return 1;
    }
    if(strcmp(entry.title,"Cat")==0 || strcmp(entry.title,"Wind")==0 || strcmp(entry.title,"Piano")==0)
      assert(&font==&F_ALERT_TITLE);
  }
  char lines[3][48]={};int count,baseline,spacing;
  const auto&font=catalogTitleLayout("WWWWWWWWWWWWWWWWWWWWWWW",lines,count,baseline,spacing);
  assert(count<=3 && catalogTitleFits(font,lines,count,baseline,spacing));
  std::string rebuilt;for(int i=0;i<count;i++)rebuilt+=lines[i];assert(rebuilt=="WWWWWWWWWWWWWWWWWWWWWWW");
  std::cout << "PASS: all 521 titles preserve full words and ink bounds x142..306/y65..139; "
            << large << " use native Gabarito 32 px, " << small << " use 20 px; max new glyph " << maxGlyphPixels
            << "/4096 scratch pixels; 23-character extension token remains complete.\n";
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
