#!/usr/bin/env python3
"""Exercise actual sketch dispatch/player functions with hardware/UI stubs."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SKETCH = ROOT / "live_demo/fortwatch_display/fortwatch_display.ino"


def main():
    sketch = SKETCH.read_text()
    colours = sketch[sketch.index("// RGB565 colours"):sketch.index("Arduino_DataBus *bus")]
    styles_player = sketch[sketch.index("struct EventStyle {"):sketch.index("void drawCentered(")]
    dispatch = sketch[sketch.index("void queueCompatibleAnalytics("):sketch.index("void readSerial()")]
    prefix = r'''#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include "alert_protocol.h"
#include "event_haptics.h"
#include "analytics_compatibility.h"
#define PIN_MOTOR 17
#define HIGH 1
#define LOW 0
template<typename T>T constrain(T value,T low,T high){return value<low?low:value>high?high:value;}
uint32_t now=0;
uint32_t millis(){return now;}
int motorWrites=0;bool motorOn=false;
void digitalWrite(int pin,int value){assert(pin==17);motorWrites++;motorOn=value==HIGH;}
struct SerialMock {template<typename...T>void printf(const char*,T...) {}} Serial;
enum class Screen {Waiting,Listening,Alert};Screen screen=Screen::Listening;
const uint32_t LIVE_BADGE_MS=1500;
uint32_t alertStartedMs=0,alertCount=0,lastMessageMs=0,lastAlertMs=0;
bool liveDisplayActive=false,liveDisplayDismissed=false,speechEnabled=true;
uint16_t liveBadgeColour=0;
char lastAlertTitle[16]={},clockText[8]={},dateText[32]={};
const char*lastAlertIcon=nullptr;const char*linkName="Bluetooth";int lastLevel=-1;
int analyticsCalls=0;std::string analyticsEvent,badge,renderedEvent;bool renderedDirection=false;
void analyticsAlert(const char*event,float){analyticsCalls++;analyticsEvent=event;}
void analyticsStatus(int,const char*){}
void showListening(){screen=Screen::Listening;badge="HOME";}
void drawLevelBar(int){}void drawStatus(){}void drawClock(){}
struct GFXMock {
 void fillRoundRect(int,int,int,int,int,uint16_t){}
 void fillScreen(uint16_t){badge="ALERT";}
 void draw16bitRGBBitmap(int,int,const uint16_t*,int,int){badge="ALERT";}
} graphics;auto*gfx=&graphics;
constexpr int F_BODY=1;
void drawText(int,const uint16_t*,int,int,const char*text,float=1,int=255,int=255,int=255,uint16_t=0){badge=text;}
void drawCentered(const char*,int,int,uint16_t){}
const uint16_t*screenImage(const char*name){static const uint16_t pixel=0;return name?&pixel:nullptr;}
const uint16_t*homeBg(){return screenImage("home");}
uint16_t catalogColour(uint32_t){return 0;}
const char*catalogImage(const SoundCatalogEntry&){return "family";}
void catalogHistoryTitle(const char*title){strncpy(lastAlertTitle,title,15);lastAlertTitle[15]=0;}
void drawCatalogCard(const SoundCatalogEntry&,const uint16_t*){badge="FAMILY";}
void drawAlertDirection(const fortwatch::AlertMessage&m,const uint16_t*){renderedEvent=m.event;renderedDirection=m.hasDirection;}
void drawAlertBrand(const uint16_t*,uint16_t){}
void drawAlertVibration(const fortwatch::HapticPattern&,const uint16_t*,uint16_t){}
void drawPatternTest(const fortwatch::HapticPattern&,const uint16_t*,uint16_t){badge="TEST";}
void drawAlertRhythm(const fortwatch::HapticPattern&,const uint16_t*,uint16_t){}
uint16_t alertPillColour(const uint16_t*,uint16_t){return 0;}
'''
    tests = r'''
void wire(const char*text){char copy[64];assert(strlen(text)<sizeof(copy));strcpy(copy,text);handleLine(copy);}
int main(){
 strcpy(lastAlertTitle,"BEFORE");lastAlertIcon="before";lastAlertMs=42;
 wire("D,Y283,.8,45,.8");
 assert(screen==Screen::Alert&&badge=="LIVE"&&renderedEvent=="Y283"&&renderedDirection);
 assert(alertCount==0&&analyticsCalls==0&&motorWrites==0&&strcmp(lastAlertTitle,"BEFORE")==0&&lastAlertMs==42);
 now=1499;expireLiveDisplay();assert(badge=="LIVE");now=1500;expireLiveDisplay();assert(badge=="RECENT");
 wire("E,DOG,.9");assert(motorOn&&vibPattern&&alertCount==1&&analyticsCalls==1);
 const auto*playing=vibPattern;uint32_t started=vibStepStartedMs;int writes=motorWrites;now+=100;
 wire("D,Y076,.9"); // Cat shares DOG/ANIMAL rhythm; do not truncate or restart.
 assert(vibPattern==playing&&motorOn&&motorWrites==writes&&vibStepStartedMs==started);
 assert(alertCount==1&&analyticsCalls==1&&strcmp(lastAlertTitle,"DOG")==0&&badge=="LIVE");
 wire("D,Y148,.9");assert(!vibPattern&&!motorOn&&motorWrites==writes+1&&renderedEvent=="Y148");
 assert(alertCount==1&&analyticsCalls==1);
 dismissAlert();writes=motorWrites;wire("D,Y283,.9");
 assert(screen==Screen::Listening&&liveDisplayDismissed&&badge=="HOME"&&motorWrites==writes&&analyticsCalls==1);
 wire("E,KNOCK,.9");assert(screen==Screen::Alert&&!liveDisplayDismissed&&alertCount==2&&analyticsCalls==2&&motorOn);
 wire("D,Y283,.9");assert(badge=="LIVE"&&!motorOn&&alertCount==2&&analyticsCalls==2);
 const auto beforeBadge=badge;writes=motorWrites;
 for(const char*invalid:{"D,Y521,.9","D,Y0000,.9","D,Y00,.9","D,Y283,nan","DD,Y283,.9"}){
  wire(invalid);assert(badge==beforeBadge&&motorWrites==writes&&alertCount==2&&analyticsCalls==2);
 }
 wire("P,Y007");assert(badge=="TEST"&&motorOn&&alertCount==2&&analyticsCalls==2&&strcmp(lastAlertTitle,"KNOCK")==0);
 now+=2000;expireLiveDisplay();assert(badge=="TEST");
 wire("D,Y494,.9,90,.9");assert(!motorOn&&!vibPattern&&!renderedDirection&&badge=="LIVE");
 wire("P,Y494");assert(!motorOn&&!vibPattern&&badge=="TEST"&&alertCount==2&&analyticsCalls==2);
 speechEnabled=false;wire("D,Y001,.9");assert(badge=="TEST");
 std::cout << "PASS: actual D/E/P dispatch, LIVE expiry, dismissal suppression, same-rhythm continuation, different-rhythm stop, quiet and history/analytics isolation\n";
}
'''
    with tempfile.TemporaryDirectory(prefix="fortwatch-display-runtime-") as directory:
        temp = Path(directory)
        source = temp / "runtime.cpp"
        source.write_text(prefix + colours + styles_player + dispatch + tests)
        executable = temp / "runtime"
        subprocess.run(["xcrun", "clang++", "-std=c++11", "-fsanitize=address,undefined",
                        "-I", str(ROOT / "live_demo/fortwatch_display"), str(source),
                        "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
