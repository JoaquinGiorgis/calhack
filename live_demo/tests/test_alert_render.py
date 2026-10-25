#!/usr/bin/env python3
"""Render actual firmware alert helpers with ASan/UBSan and a host framebuffer.

The redesigned alert is a full 320x240 composition. Geometry checks therefore
compare untouched margins to its graphite surface, not to the retired saturated
Figma cards. Native glyph bounds, neutral states and bearing centroids are checked
separately; the renderer never substitutes a screenshot for production drawing.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIRMWARE = ROOT / "live_demo/fortwatch_display"

STATE = r'''
#define PIN_MOTOR 17
#define HIGH 1
#define LOW 0
int serialLogs=0; struct SerialMock {template<typename...T>void printf(const char*,T...){serialLogs++;}} Serial;
uint16_t blitBuffer[320*16];uint32_t fakeMillis=0;bool motorOn=false;int motorWrites=0;
uint32_t millis(){return fakeMillis;}
void digitalWrite(int pin,int value){assert(pin==17);motorOn=value==HIGH;motorWrites++;}
enum class Screen {Waiting,Listening,Alert};Screen screen=Screen::Waiting;
uint32_t alertStartedMs=0,alertCount=0,lastAlertMs=0,lastMessageMs=0;
const uint32_t LIVE_BADGE_MS=1500;bool liveDisplayActive=false,liveDisplayDismissed=false;uint16_t liveBadgeColour=0;
char lastAlertTitle[16]={},clockText[8]={},dateText[32]={};
const char*lastAlertIcon=nullptr;const char*linkName="Bluetooth";
int analyticsCalls=0,lastLevel=-1;bool speechEnabled=true;float lastAnalyticsScore=0;std::string lastAnalyticsEvent;
void analyticsAlert(const char*event,float score){analyticsCalls++;lastAnalyticsScore=score;lastAnalyticsEvent=event;}
void analyticsStatus(int,const char*){}void showListening(){screen=Screen::Listening;}
void drawLevelBar(int){}void drawStatus(){}void drawClock(){}
const uint16_t*screenImage(const char*);const uint16_t*homeBg(){return screenImage("home");}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="keep software previews in this folder")
    args = parser.parse_args()
    sketch = (FIRMWARE / "fortwatch_display.ino").read_text()
    chunks = [
        sketch[sketch.index("// RGB565 colours"):sketch.index("Arduino_DataBus *bus")],
        sketch[sketch.index("struct EventStyle {"):sketch.index("void drawCentered(")],
        sketch[sketch.index("void drawCentered("):sketch.index("// Redraw a rectangle")],
        sketch[sketch.index("uint16_t glyphBuffer"):sketch.index("// ---- Home screen")],
        sketch[sketch.index("uint16_t catalogColour("):sketch.index("void readSerial()")],
    ]
    with tempfile.TemporaryDirectory(prefix="fortwatch-alert-render-") as directory:
        temp = Path(directory)
        source = temp / "render.cpp"
        source.write_text('#include "host_display.h"\n' + STATE + "\n".join(chunks) +
                          '\n#include "alert_render_cases.h"\n')
        executable = temp / "render"
        subprocess.run(["xcrun", "clang++", "-std=c++17", "-O1", "-g", "-fsanitize=address,undefined",
                        "-I", str(FIRMWARE), "-I", str(Path(__file__).parent), str(source),
                        "-o", str(executable)], check=True)
        command = [str(executable)]
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            command.append(str(args.output))
        subprocess.run(command, check=True)
    if args.output:
        from PIL import Image
        for bitmap in args.output.glob("*.bmp"):
            with Image.open(bitmap) as frame:
                frame.save(bitmap.with_suffix(".png"))
            bitmap.unlink()
        print("Software previews:", args.output)


if __name__ == "__main__":
    main()
