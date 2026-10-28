// Fortwatch Amazon V2, dimension-based FIRST FIT PROTOTYPE, millimetres.
// Z=away from wrist; X=across wrist; strap follows Y. USB exits +X.
// Verify real revision, ports, wiring, actuator heights before powered assembly.
part = "assembly"; // base,lid,tray,button,fit_test,plate,assembly
$fn=40;
W=52; L=50; wall=2; floor_t=2; base_h=22; lid_t=2; corner=6;
tray_z=8.4; tray_t=1.6; tray_w=47.2; tray_l=35;
board_x=-7.5; board_y=0; board_w=26.25; board_l=29.22;
hole_dx=22.55; hole_dy=25.44; module_depth=11.4;
// Actual screen centre / USB shell height must be checked on the received board.
screen_y=2.91; window=24.0; usb_y=0.5; usb_z=14.7;
battery_x=-6; battery_w=35; battery_l=30; battery_t=5;
mic_x=9.5; mic_y=20; mic_z=14.8; mic_w=16.7; mic_h=12.7;
mic_t=1.8; mic_clear=0.35;
motor_x=18; motor_y=-11; motor_d=10; motor_t=3;
button_x=17; button_y=-10; button_seat_h=6.8;
switch_x=-7.5; switch_z=17;
// Case closure uses M2x5 and M2 captive nuts, not self-tapping threads.
closure=[[-22,-20.5],[-22,20.5],[22,-20.5],[22,20.5]];
board_holes=[for(sx=[-1,1],sy=[-1,1])
 [board_x+sx*hole_dx/2,board_y+sy*hole_dy/2]];
eps=0.02;

module rr(w,l,r,h){linear_extrude(h) offset(r=r)
 square([w-2*r,l-2*r],center=true);}
module box_at(x,y,z,w,l,h){translate([x-w/2,y-l/2,z])cube([w,l,h]);}
module side_hole(x,y,z,w,h,depth){
 translate([x,y,z])rotate([0,90,0])linear_extrude(depth,center=true)
 offset(r=1)square([h-2,w-2],center=true);
}
module end_hole(x,y,z,w,h,depth){
 translate([x,y,z])rotate([90,0,0])linear_extrude(depth,center=true)
 offset(r=0.8)square([w-1.6,h-1.6],center=true);
}
module strap_ear(s){difference(){
 translate([0,s*28.5,0])rr(28,10,2.5,3.2);
 box_at(0,s*29.5,-1,20.8,3.2,5.2);
}}
module base(){difference(){union(){
 // 0.6 mm bevel at skin-side perimeter; manually smooth printed edges.
 hull(){rr(W-1.2,L-1.2,corner-0.6,0.01);
  translate([0,0,0.6])rr(W,L,corner,0.01);}
 translate([0,0,0.6])rr(W,L,corner,base_h-0.6);
 for(s=[-1,1])strap_ear(s);
 }
 translate([0,0,floor_t])rr(W-2*wall,L-2*wall,corner-wall,base_h+1);
 }
 // Add independent internal features, then cut ports/screws through all of them.
}
module base_features(){
 for(p=closure)translate([p[0],p[1],floor_t-eps])
  cylinder(r=3.4,h=base_h-floor_t+eps);
 // Tray ledges outside the battery footprint, no pillars through the cell.
 for(s=[-1,1])box_at(0,s*18.3,floor_t-eps,36,3.5,tray_z-floor_t+eps);
 for(x=[-15,10],s=[-1,1])translate([x,s*16.7,tray_z-eps])
  cylinder(d=1.8,h=tray_t+0.6);
 // Low battery edge stops: no pressure lid and no sharp point over pouch.
 for(s=[-1,1])box_at(battery_x,s*15.8,floor_t-eps,23,0.8,1.1);
 // Coin motor sits on the inner floor and couples vibration into the case.
 translate([motor_x,motor_y,floor_t-eps])difference(){
  cylinder(d=12.4,h=1.4);cylinder(d=10.7,h=2);
  translate([-7,-1,0])cube([14,2,2]);}
 // Microphone slides vertically into two edge channels, acoustic face +Y.
 for(s=[-1,1])translate([mic_x+s*(mic_w/2+0.8),mic_y,8.0])
 difference(){
  box_at(0,0,0,2.5,5.5,13.6);
  box_at(-s*0.8,0,0.3,1.8,mic_t+2*mic_clear,14);
 }
 box_at(mic_x,mic_y,7.5,mic_w+3,5.5,0.8);
 box_at(mic_x,22.5,floor_t-eps,mic_w+3,1.4,6.3+eps);
 // Recessed slide-switch shelf; solder leads route into front-side wiring bay.
 box_at(switch_x,-20.5,12.4,22.5,5.2,1.0);
 for(s=[-1,1])box_at(switch_x+s*11,-21.1,13,1.2,5,7.5);
}
module body(){difference(){union(){base();base_features();}
 for(p=closure){
  translate([p[0],p[1],18])cylinder(d=2.4,h=6);
  translate([p[0],p[1],base_h-2.2])rotate([0,0,30])
   cylinder(d=4.3/cos(30),h=2.3,$fn=6);
 }
 side_hole(W/2,usb_y,usb_z,14,8,8);
 end_hole(switch_x,-L/2,switch_z,10.5,3.5,7);
 // Broad grille avoids relying on an unverified microphone port coordinate.
 for(x=[4,9.5,15],z=[10.8,14.8,18.8])translate([x,25,z])
  rotate([90,0,0])cylinder(d=1.8,h=8,center=true);
}}
module lid(){difference(){
 rr(W,L,corner,lid_t);
 translate([board_x,screen_y,-1])rr(window,window,1,4);
 for(p=closure)translate([p[0],p[1],-1])cylinder(d=2.4,h=4);
 translate([button_x,button_y,-1])cylinder(d=3.6,h=4);
}}
module tray(){difference(){union(){
 rr(tray_w,tray_l,2,tray_t);
 // Tact switch rests on an open centre pedestal; bend wires clear of it.
 translate([button_x,button_y,tray_t-eps])difference(){
  rr(7.6,7.6,0.8,button_seat_h+eps);
  box_at(0,0,-1,4,8,button_seat_h+3);
 }
 }
 for(p=board_holes)translate([p[0],p[1],-1])cylinder(d=2.4,h=4);
 for(x=[-15,10],s=[-1,1])translate([x,s*16.7,-1])cylinder(d=2.4,h=4);
 box_at(0,16.2,-1,6,4,4); // battery lead and reworked charging resistor route
 box_at(20,-3,-1,4,5,4);  // motor lead route
}}
module button(){union(){cylinder(d=6,h=0.6);
 translate([0,0,0.6-eps])cylinder(d=3.0,h=2.8+eps);}}
module fit_test(){difference(){rr(33,35,2,1.6);
 for(p=board_holes)translate([p[0]-board_x,p[1],-1])cylinder(d=2.4,h=4);
 translate([0,0,-1])rr(18,18,1,4);
}}
module envelopes(){
 color([0.65,0.7,0.75,0.8])box_at(battery_x,0,2.3,battery_w,battery_l,battery_t);
 color([0.0,0.5,0.3,0.65])box_at(board_x,0,15.0,board_w,board_l,0.8);
 for(p=board_holes)color("gold")translate([p[0],p[1],10])cylinder(d=3.5,h=5);
 color([0.1,0.2,0.3,0.8])box_at(board_x,screen_y,20.5,23.4,23.4,0.9);
 color([0.1,0.4,0.8,0.7])box_at(board_x,0,10.2,18,17,4);
 color("royalblue")box_at(mic_x,mic_y,mic_z-mic_h/2,mic_w,mic_t,mic_h);
 color("silver")translate([motor_x,motor_y,2.3])cylinder(d=motor_d,h=motor_t);
 color("black")box_at(button_x,button_y,16.8,6,6,4.3);
}
if(part=="base")body();
else if(part=="lid")lid();
else if(part=="tray")tray();
else if(part=="button")button();
else if(part=="fit_test")fit_test();
else if(part=="plate"){
 translate([-30,0,0])body();translate([30,0,0])lid();
 translate([30,48,0])tray();translate([-35,54,0])fit_test();
 translate([0,54,0])button();
}else{color([0.15,0.18,0.25,0.4])body();
 translate([0,0,base_h+8])color("slategray")lid();
 translate([0,0,tray_z])color("ivory")tray();
 translate([button_x,button_y,21.35])color("orange")button();envelopes();}
