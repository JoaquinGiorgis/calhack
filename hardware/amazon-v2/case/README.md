# First-fit case for the Amazon V2 parts

**A printable nominal design, not a physically verified enclosure.** The user
already has printers and filament, including free printing access through an
investor; no printer or filament purchase is required. The old enclosure is not
used as dimensional ground truth.

The body is **52×50×24 mm assembled**, excluding the strap ears; with ears it is
**52×67×24 mm**. This is a fairly bulky development prototype. It accommodates
retail breakout boards and short soldered wiring, not tall plug-in headers.
Physical comfort and final fit remain to be established.

## Files

- [Editable OpenSCAD source](fortwatch_v2.scad)
- [Base](stl/base.stl), [lid](stl/lid.stl), [internal tray](stl/tray.stl),
  [button cap](stl/button.stl), [mounting fit coupon](stl/fit_test.stl)
- [All parts on one plate](stl/plate.stl)
- [Assembly guide](../ASSEMBLY.md)
- [Geometry report](validation.json) and [preview](preview.png)

The exported parts are watertight with consistent winding; the combined plate
contains five separate solids within 112×105 mm. Thirty-six Boolean checks found
zero intersection between the **nominal** component envelopes and printed parts,
and nominal components do not intersect each other. These envelopes simplify
real parts: they do not include a fully modeled wiring harness, tolerances,
connectors, all PCB components, nuts or screws. This is not physical-fit proof.

## Dimensions and evidence

The [official Waveshare outline drawing](reference/board-drawing.jpg) specifies
26.25×29.22 mm board outline, 22.55×25.44 mm M2 mounting centres, 23.4×23.4 mm
display area and 11.4 mm total front-to-standoff depth. Source:
[manufacturer product page](https://www.waveshare.com/esp32-s3-lcd-1.3.htm),
image `ESP32-S3-LCD-1.3-details-size.jpg`. Its mechanical archive is
[here](https://www.waveshare.net/w/upload/9/92/ESP32-S3-1.3-size.rar).
The supplied board STEP triangulates to a 26.2449×29.22 mm PCB outline but omits
the complete display/USB mechanical assembly. It is not a full collision model.
`reference/board-meshes.json` records the imported mesh bounds.

Other envelopes:

| Component | Nominal dimensions | Status |
| --- | --- | --- |
| KBT cell | 35×30×5 mm | Selected listing; measure actual cell including protection, wrap and lead exit. |
| Adafruit 3421 mic | 16.7×12.7×1.8 mm | [Manufacturer dimensions](https://www.adafruit.com/product/3421); mounted vertically. |
| Generic haptic breakout | 18×17 mm, 4 mm populated/wiring allowance | Listing gives 18×17×2 mm bare module; measure populated height. |
| Coin motor | Ø10×3 mm | Selected listing; cradle has clearance. |
| Tactile switch | 6×6×4.3 mm | Selected variant; wire/actuator travel need checking. |
| Slide switch | approximately 20×5.5 mm body and 5–6 mm body height | Provisional pocket; generic listing geometry is not an engineering drawing. |
| Strap | 20 mm wide | 20.8 mm wide slots; verify thickness and threading. |

The default screen centre is offset +2.91 mm in Y from PCB centre, inferred from
the outline drawing. USB exits the **+X side**; its cutout centre height is a
provisional parameter. Both must be checked on the received module. Brass standoff
diameter, thread depth, mic rails, switch pocket, haptic stack height, actual cell
clearance and solder bends remain fit checks. The R5 charging rework also needs
insulation and routing; use the peripheral wire space, never the battery gap.

## Print sequence

1. Print **fit_test.stl** to test the four board mounting holes, and **lid.stl**
   to check the display opening. The coupon's 18 mm centre opening is a material
   saving cutout, not a display-window gauge. Use no battery in these tests.
2. Confirm/adjust the source parameters and regenerate before a powered build.
3. Print base with wrist side on the bed, opening up; lid and tray flat; button
   flange on the bed. The combined plate already uses these orientations.

Start at **100% millimetres, 0.2 mm layers, 3–4 walls**, with the available PLA
or PETG. Exact printer, nozzle and material are not yet specified. Inspect slicer
preview: the USB roof, microphone-channel lips and switch shelf may need local
supports; remove them before assembly. Do not generate supports in the small nut
pockets where they cannot be removed. Smooth wrist-facing edges and clear holes
by hand. Slot/screw clearances may need adjustment for the actual printer.

Closure: four **M2×5** screws and four M2 captive nuts. Board-to-tray: four
**M2×4** screws into the existing brass standoffs, subject to measured thread depth.
Both sizes are in the cart. No heat-set inserts, adhesives or extra strap bars
are required by the design. Tape retention is provisional for the switch and
button; revise their pockets if the bought variants differ.

## Rebuild

The existing `hardware/tools` package provides OpenSCAD WASM. Run exports in tmux:

```sh
node hardware/amazon-v2/case/export.mjs
uv run --no-project --with trimesh --with numpy --with matplotlib --with manifold3d --with networkx python hardware/amazon-v2/case/verify.py
```

The reference STEP was inspected with `occt-import-js@0.0.23` in an isolated
temporary Bun environment. Original vendor mechanical files are retained as
references with vendor ownership; the printable design is our new OpenSCAD source.
Mesh/nominal-envelope checks do not establish real fit, print success, acoustics,
skin comfort, temperature or recognition reliability.
