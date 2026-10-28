# Assemble the Amazon Fortwatch V2 prototype

This guide matches [the 14-item cart](ORDER.md). No printer, filament, standalone
transistor or tools need to be purchased: the user has printing access and can
borrow tools. The wiring is designed from documentation; no physical assembly
or firmware operation has been verified yet.

## Why the old circuit had a transistor

The old enclosure README describes GPIO → 1 kΩ → PN2222 base, with a 1N4007
flyback diode, to switch the older motor. The microcontroller pin could control
the transistor but could not supply the motor's current directly.

The new **DRV2605L breakout replaces that discrete motor-drive circuit**. It
contains the power output stage and controls both motor terminals. Connect the
coin motor to its motor pads, not to a processor pin. No additional PN2222,
base resistor or flyback diode belongs across this driver's output. Its
[manufacturer documentation](https://www.ti.com/product/DRV2605L) covers ERM
motors, differential drive, braking and configuration. The 10 kΩ resistor in the
cart serves the **battery charger**, a separate job.

## 1. Inventory and inspect before soldering

Use one of each part; motor, switch, resistor and fastener packs leave spares.
Check the board says **ESP32-S3-LCD-1.3**, the mic says **SPH0645**, the haptic
board says **DRV2605L**, and the cell is a protected **3.7 V / 4.2 V, 500 mAh**
LiPo. Compare the board revision with the
[Waveshare schematic](https://files.waveshare.com/wiki/ESP32-S3-LCD-1.3/ESP32S3_1.3inch.pdf).
Identify pads from their printed labels, not left/right positions on photographs.

Borrow a fine-tip iron, solder/flux, tweezers, cutters/stripper, multimeter,
calipers, suitable charging-current test equipment and small screwdriver. The
charging change below is small-component rework and needs appropriate skill;
get an experienced hardware builder to perform it if needed.

Keep the battery unplugged throughout soldering. Do not solder the cell's pouch
tabs or cut its live leads. Build the removable adapter separately.

## 2. Test the untouched display board on USB

With no battery connected, use the existing USB-C **data** cable to connect the
board to the development computer. Check that it enumerates and the factory
display operates. Record its revision. No extra programmer is required.

Do **not** install the supplied tall pin headers for this enclosure. Use short,
directly soldered wires; tall headers and Dupont plugs will not fit its stack.
Unplug USB again before wiring.

## 3. Change the charger setting before battery charging

Follow the [charging modification in ORDER.md](ORDER.md#charging-modification--required-before-charging-this-small-cell).
In the documented revision, replace the existing **R5 = 1 kΩ** from PL4054 PROG
to ground with **10 kΩ**, targeting approximately **100 mA**. Do not put 10 kΩ
in parallel with the original resistor. A matching SMD resistor from the
borrowed workshop is preferable; the cart's leaded resistor can be installed
with short insulated connections and secured so its leads cannot flex the pads.

The 10 kΩ value follows the PL4054 manufacturer's demonstration instructions;
verify the received charger, resistance, actual charge current and 4.2 V charge
termination with suitable equipment. Until that is done, continue USB-only
development with the battery disconnected. A different charger/revision needs
its own documented setting.

## 4. Wire the microphone, haptics and test button

Use this proposed GPIO allocation in the eventual firmware. All peripheral
power and digital signals below are **3.3 V**. All grounds are common.

| Device pad / lead | Connect to Waveshare board |
| --- | --- |
| Microphone **3V** | **3V3** |
| Microphone **GND** | **GND** |
| Microphone **BCLK** | **GPIO4** |
| Microphone **LRCLK** | **GPIO5** |
| Microphone **DOUT** | **GPIO9** |
| Microphone **SEL** | **GND** (left channel) |
| DRV2605L **VIN** | **3V3** |
| DRV2605L **GND** | **GND** |
| DRV2605L **SDA** | **GPIO7** |
| DRV2605L **SCL** | **GPIO8** |
| DRV2605L **IN/TRIG** | Leave unconnected for I2C-controlled operation |
| Motor's two wires | DRV2605L **motor + / motor −** output pads |
| Dismiss/test button, one contact | **GPIO10**, firmware input pull-up |
| Dismiss/test button, opposite contact | **GND** |

On a four-leg tactile button, two legs on one contact are already connected.
Use a meter to select two contacts that become connected **only when pressed**.
Do not connect the button between 3V3 and GND. I2C pull-ups must go to 3.3 V;
check the breakout provides them. Keep the haptic controller's two motor outputs
separate from ground. Insulate each solder joint and provide slack/strain relief.

The microphone uses **I2S**, not PDM. Its firmware must supply the correct BCLK,
word-select and slot format. At 16 kHz with two 32-bit slots BCLK is 1.024 MHz;
verify the selected driver/channel alignment and PCM scaling against the
[Adafruit mic guide](https://learn.adafruit.com/adafruit-i2s-mems-microphone-breakout).
Missing or shifted samples can look like model errors later.

## 5. Bench tests before adding battery or closing the case

Power from USB, with the cell disconnected. Test in this order:

1. Display and serial log.
2. Microphone: nonzero changing PCM/RMS, then a short intelligible recording.
3. I2C: DRV2605L should respond at its documented address **0x5A**.
4. Haptics: explicitly select an **ERM** motor configuration and approximately
   3 V rated drive appropriate to the motor; verify before increasing strength.
   Do not use an LRA example's calibration unchanged.
5. Button: released reads high; pressed reads low.
6. Run audio and haptics together, checking for brownouts and motor self-noise.

These are bring-up steps, not a claim that test firmware is already supplied.
The existing phone/Mac recognizer and receiver firmware are not the standalone
ESP32-S3 recognizer. Flashing and validating that port is separate work.

## 6. Battery and on/off switch

Build an adapter using the prewired mating pair and switch:

```text
Battery positive ── switch COMMON
                       one outer terminal ── board BAT1 positive
                       other outer terminal: leave isolated
Battery negative ─────────────────────────── board BAT1 GND
```

Map COMMON and the selected throw with continuity mode. Never wire the spare
throw to ground: that could short the cell in one switch position. Compare
connector keying/pitch with the real board and cell, and meter actual polarity
through the **finished adapter**. Red/black colors alone are insufficient.
If the pigtail housing differs, adapt the matching pair at the board's BAT1 pads
with the battery disconnected, rather than forcing a connector.

After the charger modification is verified, test battery operation and then
charging on the bench. Check for excess current or unexpected warmth before
placing the battery inside plastic or wearing it. Turning off this battery
switch does not switch off USB power while the cable is attached.

## 7. Print and dry-fit the enclosure

Use [case/README.md](case/README.md) and start with **fit_test.stl** plus **lid.stl**.
The first design is a nominal mechanical prototype, not a demonstrated fit.
Check mounting-hole spacing, visible display position and the actual board stack.
Then check the battery, driver, switch and microphone against the dimensional
checklist before printing/using the whole case. Keep the cell out of fit tests.

Final intended order, once the dimensions are confirmed:

1. Place the motor in the base cradle. Route its wires away from the mic.
2. Place the insulated battery in its shallow bay. The tray must leave clearance
   above the pouch; never use closure force to flatten the cell or wiring.
3. Mount the directly wired haptic board on the tray between the four main-board
   standoffs. Keep its populated height within the reserved 4 mm envelope.
4. With the tray still outside the case, attach the display module's brass
   standoffs using **M2×4** screws through the tray. Verify protrusion/thread depth
   before tightening; the modeled tray is 1.6 mm thick. Do not force a bottomed screw.
5. Fit the tactile switch on its tray pedestal and route its wires. Fit the slide
   switch into the front-end shelf. Insulation tape can retain these for first fit;
   revise the pockets if the purchased generic parts differ.
6. Seat the tray on its locating pins. Slide the mic into the rear channels with
   its acoustic port facing the grille, not the battery or a solid wall.
7. Place the printed button cap over the tactile actuator. Insert four M2 nuts
   into the base's top hex pockets. Close the lid with **M2×5** screws. The lid
   must seat without squeezing the glass, pressing the button or trapping wires.
8. Thread the **20 mm one-piece strap** through the printed loops. Keep buckle
   and folded excess outside the slots. Smooth every wrist-contact edge.

Repeat microphone/vibration/button/USB tests inside the case. Start with a short
wearing trial and check pressure, wrist motion, false alerts and heat. This design
does not provide waterproofing, validated all-day runtime or sound direction.
