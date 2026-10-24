// SoundSense — wrist enclosure for Waveshare ESP32-S3-Touch-LCD-2
// Parametric OpenSCAD model. Units: mm. No screws: snap-fit back plate.
//
// Coordinate system: X = across the wrist (strap direction),
// Y = along the forearm (long side of the display; +Y = towards the elbow),
// Z = up (away from skin).
//
// Layout (everything inside, only the USB-C cable goes out):
//   [ display section ]  board + glass, captured behind the bezel lip
//   [ bay ]              microphone module under a grille + vibration motor in a cradle
//
// Parts:
//   shell       — front frame, walls and bay roof with acoustic grille.
//   back        — back plate: strap ears, snap-fit skirt, 4 pillars pressing the
//                 board's brass standoffs, motor cradle.
//   weight      — eccentric weight that presses on the motor shaft (makes it vibrate).
//   fit_test    — thin top slice of the shell: quick print to check the glass fit.
//   plate       — everything laid out flat for ONE print job.
//
// Export:  cd ../tools && node export-stl.mjs

part = "assembly"; // [assembly, shell, back, weight, fit_test, plate]

$fn = 48;

// ---------- Printing ----------
clr  = 0.4;   // fit clearance per side
wall = 2.0;   // side wall thickness

// ---------- Waveshare ESP32-S3-Touch-LCD-2 (official drawing, docs/hardware/waveshare-size.jpg) ----------
glass_w = 37.10;
glass_l = 58.80;
glass_r = 2.60;
glass_t = 1.10;
active_w = 31.00;
active_l = 41.20;
active_y0 = 10.29;    // glass bottom edge (USB side) -> active area
pcb_w = 35.00;
pcb_l = 48.20;
hole_dx = 29.00;      // M2 standoff spacing X
hole_dy = 42.20;      // M2 standoff spacing Y
pcb_y_offset = 0.0;   // PCB centre vs glass centre along Y. MEASURE with a ruler.
module_depth   = 7.20; // glass front -> PCB back face
standoff_depth = 9.70; // glass front -> end of the brass M2 standoffs

// ---------- Enclosure ----------
lip          = 1.2;  // bezel thickness in front of the glass
lip_overlap  = 1.6;  // how much the bezel covers the glass edge
gap_below    = 18.0; // space behind the standoffs: female Dupont jumpers plug straight onto the
                     // header pins (housing ~14 mm + wire bend). No cutting or soldering needed.
back_t       = 2.5;  // back plate thickness
plug_h       = 1.5;  // pillar base offset (kept for stack-up)
pillar_d     = 6.0;
pillar_extra = 0.0;  // 0 = nominal. If the board rattles, put a bit of tape on the pillar tops.

// Snap-fit: low locating skirt + 4 tall flexible tabs (slit free from the skirt).
// PLA rules (wilsonwaters/3d-printing): strain <= 1-1.5 %, cantilever L:T >= 10:1,
// undercut 0.3-0.5 mm, root fillet >= 1 mm.
// Here: strain = 3*t*d/(2*L^2) = 3*1.35*0.4/(2*14^2) ≈ 0.4 %, L:T = 14/1.35 ≈ 10.4, undercut 0.4.
skirt_t   = 1.2;     // locating skirt wall on the back plate
skirt_h   = 5.0;
tab_t     = 1.35;    // flexible tab thickness (3 extrusion lines @ 0.45)
tab_h     = 15.5;    // flexible tab height above the plate
tab_len   = 12.0;    // tab length (along the wall)
tab_slit  = 0.8;     // slits that free the tab from the skirt
tab_fillet = 1.0;    // root fillet on the inner side
snap_r    = 0.8;     // ridge radius; ridge protrudes snap_r, engages snap_r - clr = 0.4 mm
snap_z_on_tab = 14.0; // ridge height above the plate
edge_ch   = 0.6;     // chamfer on bed-facing outer edges (elephant foot + skin comfort)

// USB-C + RST/BOOT access slot (short wall at -Y)
usb_slot_w = 24.0;
usb_slot_h = 7.5;

// Strap (velcro)
strap_w = 20.0;
strap_t = 3.2;
ear     = 8.0;

// ---------- Bay: mic + motor ----------
with_motor = true;
rib_t    = 1.5;      // rib that stops the glass sliding into the bay
roof_t   = 1.6;      // bay roof thickness (top face)
// Mic: Grove Sound Sensor (1x1 Grove: 20 x 20 mm board, ~22 mm with mounting ears, ~8.5 mm tall).
// Lies on the floor, mic facing up under the grille, Grove connector towards the display.
mic_zone = 21;       // length (Y) of the mic area, next to the display
// Motor: 130 motor from the hardware desk (measured: body ~25 mm incl. white cap). Cut the zip tie off.
motor_w  = 20.4;     // body width lying on its flat side
motor_h  = 15.0;     // height lying on its flat side
motor_l  = 25.0;     // body length incl. white end cap
motor_nub = 3.0;     // bearing boss on the back of the white cap
motor_shaft = 8.0;   // shaft sticking out the front
shaft_d  = 2.0;
rail_h   = 6.0;
rail_t   = 1.6;
bay_l    = with_motor ? mic_zone + motor_w + 2*rail_t + 6 : mic_zone + 2; // inner length of the bay (Y); +6 keeps the end snap tab free to flex
sens_h   = 8.6;      // Grove sensor height (PCB + mic capsule)
mic_gap  = 1.5;      // air gap between mic capsule and the grille
post_d   = 5.0;      // posts that lift the Grove sensor up to the grille

// ---------- Derived ----------
in_w  = glass_w + 2*clr;
in_l  = glass_l + 2*clr;
in_r  = glass_r + clr;
bay_total = with_motor || bay_l > 0 ? rib_t + bay_l : 0;
body_in_l = in_l + bay_total;          // full inner length
yc        = bay_total / 2;              // body centre (glass centre is y = 0)
out_w = in_w + 2*wall;
out_l = body_in_l + 2*wall;
out_r = in_r + wall;

z_flange = back_t;
z_plug   = back_t + plug_h;
z_glass  = z_plug + gap_below + standoff_depth;
z_top    = z_glass + lip;
z_pcb    = z_glass - module_depth;
z_usb    = z_pcb - 1.6;
z_snap   = back_t + snap_z_on_tab;

win_w = glass_w - 2*lip_overlap;
win_l = glass_l - 2*lip_overlap;

bay_y0  = in_l/2 + rib_t;                // bay starts here
mic_yc  = bay_y0 + mic_zone/2;
motor_yc = bay_y0 + mic_zone + (bay_l - mic_zone)/2;
skirt_in_w = in_w - 2*clr - 2*skirt_t;   // usable inner width at the floor
motor_x0 = -in_w/2 + clr + motor_nub + 0.3; // motor body start (-X side, nub behind it); shaft towards +X
motor_notch_l = motor_w + 2*rail_t + 2;     // skirt is cut away here so motor + shaft fit the full width
post_h   = z_top - roof_t - mic_gap - sens_h - back_t; // sensor sits on top of the posts

holes = [for (sx=[-1,1], sy=[-1,1]) [sx*hole_dx/2, pcb_y_offset + sy*hole_dy/2]];
// tabs: [x, y, angle] — long sides at the mic zone, short ends at the centre.
// All clear of the header Dupont rows (|y| < 17.8), the pillars and the motor.
tabs = [ [ (in_w/2 - clr), mic_yc, 0], [-(in_w/2 - clr), mic_yc, 180],
         [0, -(in_l/2 - clr), 270], [0, in_l/2 + bay_total - clr, 90] ];

// ---------- Helpers ----------
module rrect2(w, l, r) { offset(r) square([w-2*r, l-2*r], center=true); }
module rrect(w, l, r, h) { linear_extrude(h) rrect2(w, l, r); }
module slot_y(w, h, r, depth) { rotate([90,0,0]) linear_extrude(depth, center=true) rrect2(w, h, r); }
module rod_y(r, len) { rotate([90,0,0]) cylinder(r=r, h=len, center=true); }

// ---------- Shell ----------
module shell() {
    difference() {
        translate([0, yc, z_flange]) rrect(out_w, out_l, out_r, z_top - z_flange);

        // display cavity
        translate([0,0,z_flange-1]) rrect(in_w, in_l, in_r, z_glass - z_flange + 1);

        if (bay_total > 0) {
            // bay cavity (under the roof)
            translate([0, bay_y0 + bay_l/2, z_flange-1]) rrect(in_w, bay_l, in_r, z_top - roof_t - z_flange + 1);
            // wire passage under the rib
            translate([0, in_l/2 + rib_t/2, (z_flange + z_glass - 3)/2])
                cube([in_w, rib_t + 4, z_glass - 3 - z_flange + 2], center=true); // full width: skirt passes under the rib
            // acoustic grille over the mic zone
            for (x=[-14:3:14], y=[-mic_zone/2+3:3:mic_zone/2-3])
                translate([x + ((round(y/3)%2==0)?0:1.5), mic_yc + y, z_top - roof_t - 1])
                    cylinder(d=1.8, h=roof_t + 2, $fn=16);
        }

        // display window, chamfered for finger access
        hull() {
            translate([0,0,z_glass-0.01]) rrect(win_w, win_l, 1.5, 0.01);
            translate([0,0,z_top])        rrect(win_w + 2*0.8*lip, win_l + 2*0.8*lip, 1.5 + 0.8*lip, 0.01);
        }
        translate([0,0,z_top-0.01]) rrect(win_w + 2*0.8*lip, win_l + 2*0.8*lip, 1.5 + 0.8*lip, 1);

        // USB-C + RST/BOOT slot
        translate([0, -(in_l/2 + wall/2), z_usb]) slot_y(usb_slot_w, usb_slot_h, 2, wall*3);

        // snap grooves (match the ridges on the back plate tabs)
        for (t = tabs) translate([t[0], t[1], z_snap]) rotate([0,0,t[2]]) rod_y(snap_r + 0.15, tab_len + 1);
        // chamfer on the bed-facing (front) outer edge
        translate([0, yc, z_top]) difference() {
            rrect(out_w + 2, out_l + 2, out_r + 1, 2*edge_ch);
            hull() {
                translate([0,0,-edge_ch - 0.01]) rrect(out_w, out_l, out_r, 0.01);
                translate([0,0,-0.01]) rrect(out_w - 2*edge_ch, out_l - 2*edge_ch, out_r - edge_ch, 0.01);
                translate([0,0,2*edge_ch]) rrect(out_w - 2*edge_ch, out_l - 2*edge_ch, out_r - edge_ch, 0.01);
            }
        }
        // lead-in chamfer at the bottom inner edge
        translate([0, yc, z_flange - 0.01]) hull() {
            rrect(in_w + 1.2, body_in_l + 1.2, in_r + 0.6, 0.01);
            translate([0,0,0.8]) rrect(in_w, body_in_l, in_r, 0.01);
        }
        // pry notch to open (far end, +Y)
        translate([0, yc + out_l/2 - wall/2, z_flange]) cube([10, wall*3, 2.4], center=true);
    }
}

// ---------- Strap ears ----------
module strap_plate(w, l, r, t) {
    difference() {
        union() {
            rrect(w, l, r, t);
            rrect(w + 2*ear, strap_w + 8, 3, t);
        }
        for (sx=[-1,1])
            translate([sx*(w/2 + ear/2), 0, -1]) rrect(strap_t, strap_w + 1, strap_t/2 - 0.01, t + 2);
    }
}

// ---------- Back plate ----------
module back() {
    sk_w = in_w - 2*clr;
    sk_l = body_in_l - 2*clr;
    translate([0, yc, 0]) strap_plate(out_w, out_l, out_r, back_t);
    // locating skirt (with slits around the tabs and a notch for the motor)
    difference() {
        translate([0, yc, back_t - 0.01]) difference() {
            rrect(sk_w, sk_l, in_r - clr, skirt_h);
            translate([0,0,-1]) rrect(sk_w - 2*skirt_t, sk_l - 2*skirt_t, max(in_r - clr - skirt_t, 0.5), skirt_h + 2);
        }
        if (with_motor) for (sx=[-1,1])
            translate([sx*(sk_w/2), motor_yc, back_t + skirt_h/2]) cube([skirt_t*3, motor_notch_l, skirt_h + 2], center=true);
        for (t = tabs, sy=[-1,1]) translate([t[0], t[1], back_t + skirt_h/2]) rotate([0,0,t[2]])
            translate([-skirt_t/2, sy*(tab_len/2 + tab_slit/2), 0]) cube([skirt_t*3, tab_slit, skirt_h + 2], center=true);
    }
    // flexible snap tabs: beam + ridge + inner root fillet (local frame: +X = outward)
    for (t = tabs) translate([t[0], t[1], 0]) rotate([0,0,t[2]]) {
        translate([-tab_t, -tab_len/2, back_t - 0.01]) cube([tab_t, tab_len, tab_h + 0.01]);
        translate([0, 0, z_snap]) intersection() {
            rod_y(snap_r, tab_len);
            translate([snap_r/2 - 0.2, 0, 0]) cube([snap_r + 0.4, tab_len, 2*snap_r], center=true);
        }
        translate([-tab_t + 0.01, tab_len/2, back_t - 0.01]) rotate([90,0,0])
            linear_extrude(tab_len) polygon([[0,0], [-tab_fillet,0], [0,tab_fillet]]);
    }
    // pillars pressing on the brass standoffs
    for (p = holes) translate([p[0], p[1], back_t - 0.01]) cylinder(d=pillar_d, h=plug_h + gap_below + pillar_extra + 0.01);
    // posts lifting the Grove sensor (20 x 20) close to the grille
    for (sx=[-1,1], sy=[-1,1]) translate([sx*7.5, mic_yc + sy*7.5, back_t - 0.01]) cylinder(d=post_d, h=post_h + 0.01);
    // motor cradle: two rails along X + end stop
    if (with_motor) translate([0, motor_yc, back_t - 0.01]) {
        for (sy=[-1,1]) translate([motor_x0 + motor_l/2, sy*(motor_w/2 + clr/2 + rail_t/2), rail_h/2])
            cube([motor_l, rail_t, rail_h], center=true);
    }
}

// ---------- Eccentric weight (press on the motor shaft) ----------
module weight() {
    difference() {
        union() {
            cylinder(d=5, h=5);
            intersection() {
                cylinder(r=5.5, h=5);
                translate([-6, 0, -1]) cube([12, 6, 7]);
            }
        }
        translate([0,0,-1]) cylinder(d=shaft_d, h=7, $fn=24); // printed holes come out ~0.1-0.2 small -> snug press fit
    }
}

// ---------- Visual stand-ins ----------
module ghosts() {
    color("black", 0.9) translate([0,0,z_glass - glass_t]) rrect(glass_w, glass_l, glass_r, glass_t);
    color("steelblue") translate([0, -glass_l/2 + active_y0 + active_l/2, z_glass + 0.05]) cube([active_w, active_l, 0.1], center=true);
    color("darkgreen", 0.8) translate([0, pcb_y_offset, z_pcb]) rrect(pcb_w, pcb_l, 1, 1.6);
    if (with_motor) color("silver") translate([motor_x0, motor_yc, back_t]) {
        translate([0, -motor_w/2, 0]) cube([motor_l, motor_w, motor_h]);
        translate([motor_l, 0, motor_h/2]) rotate([0,90,0]) cylinder(d=shaft_d, h=motor_shaft);
        translate([-motor_nub, 0, motor_h/2]) rotate([0,90,0]) cylinder(d=6, h=motor_nub);
        translate([motor_l + 3, 0, motor_h/2]) rotate([0,90,0]) color("orange") weight();
    }
    color("royalblue", 0.8) translate([0, mic_yc, back_t + post_h + 0.8]) cube([22, 20, 1.6], center=true);
    color("silver") translate([4, mic_yc + 2, back_t + post_h + 1.6]) cylinder(d=9.7, h=sens_h - 1.6);
}

// ---------- Layouts ----------
module shell_print() { translate([0,0,z_top]) mirror([0,0,1]) shell(); }

module assembly() {
    color("#2b2d31") back();
    color("#e8e6e1", 0.85) shell();
    ghosts();
}

module fit_test() {
    intersection() { shell_print(); translate([-100,-100,-1]) cube([200,200, lip + 3 + 1]); }
}

module plate() {
    shell_print();
    translate([out_w/2 + out_w/2 + 2*ear + 8, 0, 0]) back();
    translate([-(out_w/2 + 12), -out_l/2 + yc + 8, 0]) weight();
    translate([-(out_w/2 + 12), -out_l/2 + yc + 22, 0]) weight(); // spare
}

if      (part == "shell")    shell_print();
else if (part == "back")     back();
else if (part == "weight")   weight();
else if (part == "fit_test") fit_test();
else if (part == "plate")    plate();
else assembly();
