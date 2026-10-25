// Host rasterizer for production firmware UI tests; no Arduino/device access.

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>
#include "fonts.h"
#include "icons.h"
#include "screens.h"
#include "alert_protocol.h"
#include "event_haptics.h"
#include "analytics_compatibility.h"
using std::min; using std::max;
template <typename T> T constrain(T v,T lo,T hi) { return min(max(v,lo),hi); }
struct HostGFX {
  std::vector<uint16_t> pixels = std::vector<uint16_t>(320*240);
  int outOfBounds = 0;
  int cursorX=0,cursorY=0,textSize=1; uint16_t textColor=0xFFFF;
  int width() const {return 320;}
  void setTextSize(int size){textSize=size;}
  void setTextColor(uint16_t color){textColor=color;}
  void setCursor(int x,int y){cursorX=x;cursorY=y;}
  void print(const char* text) { assert(!text || !*text); }

  void pixel(int x,int y,uint16_t c) {
    if(x<0 || y<0 || x>=320 || y>=240) { outOfBounds++; return; }
    pixels[y*320+x]=c;
  }
  void fillScreen(uint16_t c) { std::fill(pixels.begin(),pixels.end(),c); }
  void fillRect(int x,int y,int w,int h,uint16_t c) { for(int j=y;j<y+h;j++) for(int i=x;i<x+w;i++) pixel(i,j,c); }
  void drawFastHLine(int x,int y,int w,uint16_t c) { fillRect(x,y,w,1,c); }
  void drawLine(int x0,int y0,int x1,int y1,uint16_t c) {
    int dx=abs(x1-x0), sx=x0<x1?1:-1, dy=-abs(y1-y0), sy=y0<y1?1:-1, e=dx+dy;
    for(;;) { pixel(x0,y0,c); if(x0==x1&&y0==y1) break; int e2=2*e; if(e2>=dy){e+=dy;x0+=sx;} if(e2<=dx){e+=dx;y0+=sy;} }
  }
  void fillTriangle(int x0,int y0,int x1,int y1,int x2,int y2,uint16_t c) {
    auto cross=[](int ax,int ay,int bx,int by,int px,int py){return (bx-ax)*(py-ay)-(by-ay)*(px-ax);};
    for(int y=min(y0,min(y1,y2));y<=max(y0,max(y1,y2));y++)
      for(int x=min(x0,min(x1,x2));x<=max(x0,max(x1,x2));x++) {
        int a=cross(x0,y0,x1,y1,x,y),b=cross(x1,y1,x2,y2,x,y),d=cross(x2,y2,x0,y0,x,y);
        if((a>=0&&b>=0&&d>=0)||(a<=0&&b<=0&&d<=0)) pixel(x,y,c);
      }
  }
  void fillCircle(int cx,int cy,int r,uint16_t c) {
    for(int y=-r;y<=r;y++) for(int x=-r;x<=r;x++) if(x*x+y*y<=r*r) pixel(cx+x,cy+y,c);
  }
  void drawCircle(int cx,int cy,int r,uint16_t c) {
    int x=r,y=0,e=1-r;
    while(x>=y) {
      pixel(cx+x,cy+y,c);pixel(cx+y,cy+x,c);pixel(cx-y,cy+x,c);pixel(cx-x,cy+y,c);
      pixel(cx-x,cy-y,c);pixel(cx-y,cy-x,c);pixel(cx+y,cy-x,c);pixel(cx+x,cy-y,c);
      y++; if(e<0) e+=2*y+1; else {x--;e+=2*(y-x)+1;}
    }
  }
  void fillRoundRect(int x,int y,int w,int h,int r,uint16_t c) {
    r=min(r,min(w,h)/2);
    for(int j=0;j<h;j++) for(int i=0;i<w;i++) {
      int dx=i<r?r-i:i>=w-r?i-(w-r-1):0;
      int dy=j<r?r-j:j>=h-r?j-(h-r-1):0;
      if(dx*dx+dy*dy<=r*r) pixel(x+i,y+j,c);
    }
  }
  void draw16bitRGBBitmap(int x,int y,const uint16_t* data,int w,int h) {
    assert(w*h<=320*240);
    for(int j=0;j<h;j++) for(int i=0;i<w;i++) pixel(x+i,y+j,data[j*w+i]);
  }
};
HostGFX display; HostGFX *gfx=&display;
void bmp(const char* path,const std::vector<uint16_t>& p,int w,int h) {
  std::ofstream f(path,std::ios::binary); auto u16=[&](uint16_t v){f.write((const char*)&v,2);}; auto u32=[&](uint32_t v){f.write((const char*)&v,4);};
  const int stride=(w*3+3)&~3; f.put('B');f.put('M');u32(54+stride*h);u32(0);u32(54);u32(40);u32(w);u32(h);u16(1);u16(24);u32(0);u32(stride*h);u32(2835);u32(2835);u32(0);u32(0);
  for(int y=h-1;y>=0;y--) {for(int x=0;x<w;x++){uint16_t c=p[y*w+x];f.put((c&31)*255/31);f.put(((c>>5)&63)*255/63);f.put((c>>11)*255/31);}for(int i=w*3;i<stride;i++) f.put(0);}
}
