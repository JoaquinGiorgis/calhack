// Intended writable zones of the redesigned 320x240 composition. Margins must
// exactly retain alertBasePixel; a crossing text/icon/arc fails this assertion.
void verifyGeometry() {
  assert(display.outOfBounds==0);
  for(int y=0;y<240;y++)for(int x=0;x<320;x++) {
    const bool brand=x>=16&&x<=135&&y>=12&&y<=35;
    const bool status=x>=214&&x<=305&&y>=12&&y<=36;
    const bool ring=x>=14&&x<=126&&y>=54&&y<=166;
    const bool phone=x>=30&&x<=126&&y>=168&&y<=186;
    const bool name=x>=142&&x<=306&&y>=43&&y<=139;
    const bool direction=x>=142&&x<=306&&y>=145&&y<=186;
    const bool rhythm=x>=23&&x<=303&&y>=201&&y<=218;
    const bool footer=x>=88&&x<=305&&y>=226&&y<=239;
    if(!brand&&!status&&!ring&&!phone&&!name&&!direction&&!rhythm&&!footer &&
       display.pixels[y*320+x]!=alertBasePixel(x,y)) {
      fprintf(stderr,"Unexpected drawing outside specified geometry: x=%d y=%d\n",x,y);abort();
    }
  }
}

void verifyBearing(bool known,float angle=0) {
  int count=0;double dx=0,dy=0;
  for(int y=54;y<=166;y++)for(int x=14;x<=126;x++) {
    const uint16_t c=display.pixels[y*320+x];
    const int r=(c>>11)*8,g=((c>>5)&63)*4,b=(c&31)*8;
    if(g>r+24&&g>b+48){count++;dx+=x-70;dy+=y-110;}
  }
  if(!known){assert(count==0);return;}
  assert(count>200);double measured=atan2(dx,-dy)*180/3.141592653589793;
  double error=fmod(measured-angle+540,360)-180;assert(fabs(error)<2);
}

void wire(const char*text){char buffer[64];assert(strlen(text)<64);strcpy(buffer,text);handleLine(buffer);}

int main(int argc,char**argv) {
  int frames=0;
  for(unsigned i=0;i<SOUND_CATALOG_COUNT;i++) {
    char id[5];snprintf(id,sizeof(id),"Y%03u",i);
    fortwatch::AlertMessage m;strcpy(m.event,id);m.score=.82;m.hasDirection=true;m.angleDegrees=45;m.directionQuality=.8;
    const auto&entry=SOUND_CATALOG[i];
    const int analytics=analyticsCalls;const auto count=alertCount;
    showAlert(m,false,true);verifyGeometry();verifyBearing(!entry.isQuiet,45);frames++;
    assert(analyticsCalls==analytics&&alertCount==count);
    m.hasDirection=false;showAlert(m);verifyGeometry();verifyBearing(false);frames++;
    const auto history=alertCount;const int after=analyticsCalls;const std::string title=lastAlertTitle;
    m.hasDirection=true;showAlert(m,true);verifyGeometry();verifyBearing(false);frames++;
    assert(alertCount==history&&analyticsCalls==after&&title==lastAlertTitle);
  }
  for(const auto&style:EVENT_STYLES) {
    fortwatch::AlertMessage m;strcpy(m.event,style.name);m.score=.82;m.hasDirection=true;m.angleDegrees=-90;m.directionQuality=.8;
    showAlert(m);verifyGeometry();verifyBearing(true,-90);frames++;
    showAlert(m,true);verifyGeometry();verifyBearing(false);frames++;
    m.directionQuality=.59;showAlert(m);verifyGeometry();verifyBearing(false);frames++;
  }
  for(int angle=-180;angle<=180;angle++) {
    fortwatch::AlertMessage m;strcpy(m.event,"KNOCK");m.hasDirection=true;m.angleDegrees=angle;m.directionQuality=.8;
    showAlert(m);verifyGeometry();verifyBearing(true,angle);frames++;
  }
  wire("E,WWWWWWWWWWWWWWWWWWWWWWW,.9");verifyGeometry();verifyBearing(false);frames++;
  wire("D,Y283,.9,90,.8");verifyBearing(true,90);auto fresh=display.pixels;
  fakeMillis+=1499;expireLiveDisplay();assert(display.pixels==fresh);
  fakeMillis++;expireLiveDisplay();verifyGeometry();verifyBearing(false);frames++;
  // Only status and the direction zones may change when a live bearing expires.
  for(int y=0;y<240;y++)for(int x=0;x<320;x++) {
    bool status=x>=214&&x<=305&&y>=12&&y<=36;
    bool direction=(x>=14&&x<=126&&y>=54&&y<=186)||(x>=142&&x<=306&&y>=145&&y<=186);
    if(!status&&!direction)assert(fresh[y*320+x]==display.pixels[y*320+x]);
  }
  wire("P,Y283");verifyBearing(false);auto manual=display.pixels;fakeMillis+=2000;expireLiveDisplay();assert(display.pixels==manual);
  printf("PASS: %d production alert frames, all 521 classes + legacy, all 361 bearings, no ink outside defined geometry, neutral uncertainty/test/quiet/recent and no stale bearing.\n",frames);

  if(argc>1) {
    std::vector<uint16_t>sheet(960*1440);int index=0;
    for(const char*sample:{"E,KNOCK,.8,-45,.8","E,ALARM,.8,90,.8","E,Y020,.8,0,.8","E,Y076,.8,-90,.8","E,Y106,.8,135,.8","E,Y148,.8,45,.8","E,Y210,.8,180,.8","E,Y277,.8,-135,.8","E,Y283,.8,0,.8","E,Y301,.8,90,.8","E,Y319,.8,-45,.8","E,Y349,.8,45,.8","E,Y371,.8,-90,.8","E,Y382,.8,0,.8","E,Y383,.8,180,.8","E,Y435,.8,90,.8","E,Y494,.8","E,Y520,.8"}) {
      wire(sample);for(int y=0;y<240;y++)for(int x=0;x<320;x++)sheet[(y+(index/3)*240)*960+x+(index%3)*320]=display.pixels[y*320+x];
      std::string path=std::string(argv[1])+"/card-"+std::to_string(index)+".bmp";bmp(path.c_str(),display.pixels,320,240);index++;
    }
    bmp((std::string(argv[1])+"/brand-catalog-preview.bmp").c_str(),sheet,960,1440);
    std::vector<uint16_t>states(640*480);index=0;
    for(const char*sample:{"D,Y283,.8,90,.8","RECENT","E,Y283,.8","P,Y283"}) {
      if(strcmp(sample,"RECENT")==0){fakeMillis+=1500;expireLiveDisplay();}else wire(sample);
      for(int y=0;y<240;y++)for(int x=0;x<320;x++)states[(y+(index/2)*240)*640+x+(index%2)*320]=display.pixels[y*320+x];index++;
    }
    bmp((std::string(argv[1])+"/brand-states-preview.bmp").c_str(),states,640,480);
    std::vector<uint16_t>legacy(1600*480);index=0;
    for(const auto&style:EVENT_STYLES) {
      fortwatch::AlertMessage m;strcpy(m.event,style.name);m.hasDirection=true;m.angleDegrees=45;m.directionQuality=.8;showAlert(m);
      for(int y=0;y<240;y++)for(int x=0;x<320;x++)legacy[(y+(index/5)*240)*1600+x+(index%5)*320]=display.pixels[y*320+x];index++;
    }
    bmp((std::string(argv[1])+"/brand-legacy-preview.bmp").c_str(),legacy,1600,480);
  }
}
