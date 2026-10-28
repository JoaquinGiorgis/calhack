# Fortwatch V2 — Amazon component cart

Checked October 27, 2026, approximately 10:41 p.m. Pacific, signed in with the
existing Amazon destination San Francisco 94109. User authorized filling the
cart after confirming requirements; **no order was placed**.

**14 listings, quantity 1 each, subtotal $134.43 before tax.** Every active cart
line showed free delivery Thursday October 29, with about 1 hour 19 minutes
remaining to order. No morning time slot was shown. These are cart estimates,
not a delivery guarantee or a reserved inventory allocation. Recheck at checkout.

[Amazon cart](https://www.amazon.com/gp/cart/view.html) · [Screenshot](evidence/cart.png)

## Exact cart

| Item / Amazon link | Price | Purpose and quantity used |
| --- | ---: | --- |
| [Waveshare ESP32-S3-LCD-1.3](https://www.amazon.com/dp/B0F3337VBN) | $21.11 | One processor/display assembly; 16 MB flash, 8 MB PSRAM, 240×240 LCD, USB-C, onboard charger. Bare standard version with supplied headers. |
| [Adafruit SPH0645LM4H microphone, 3421](https://www.amazon.com/dp/B06XNL2GBW) | $11.58 | One digital I2S mic. |
| [DRV2605L breakout](https://www.amazon.com/dp/B0FZ8J9N86) | $12.99 | One haptic controller, compatible with 3.3 V power and logic. Replaces the earlier two-pack offer that slipped to Friday. |
| [tatoko 10×3 mm 3 V coin motors, 20 pack](https://www.amazon.com/dp/B07Q1ZV4MJ) | $12.99 | Use one; remaining motors are spares. Rated 85 mA. |
| [KBT 503035 3.7 V 500 mAh protected LiPo](https://www.amazon.com/dp/B0BJPG4B72) | $8.99 | One 35×30×5 mm nominal cell. Connector and polarity require inspection before connection. |
| [Fermerry 28 AWG silicone wire, six colors, 5 ft each](https://www.amazon.com/dp/B089CR4SDM) | $8.29 | Short soldered interconnects; no tall breadboard harness. |
| [10 kΩ 1/4 W resistors, 10 pack](https://www.amazon.com/dp/B0BRKMHRVP) | $3.99 | One for the mandatory charger-current modification below. Leaded part is an electrically suitable rework component, not a matching SMD footprint. |
| [1.25 mm 2-pin prewired connector pairs, 20 pack](https://www.amazon.com/dp/B0DCNYN4Q5) | $7.29 | Removable battery/switch adapter and spares. Generic names do not prove housing compatibility; compare received housings and meter polarity. |
| [DHOOZ heat-shrink assortment, 900 pieces](https://www.amazon.com/dp/B0BG6V4HV4) | $6.99 | Insulate wire joints; includes 1 mm and 2 mm sizes. |
| [M2 Phillips screws and nuts assortment](https://www.amazon.com/dp/B0GK9LF2P2) | $9.99 | Case closure and captive nuts; 4/5/6/8/10 mm lengths. Final lengths follow the new case design. |
| [Benchmark one-piece nylon strap, **20 mm black**](https://www.amazon.com/dp/B01FEY1EOC) | $9.95 | One pass-through strap. Selected size verified in the cart; no spring bars needed for printed strap loops. |
| [Noqlyur 10 mm polyimide insulation tape, two rolls](https://www.amazon.com/dp/B0HD7W5WKQ) | $5.49 | One-time purchase, not subscription. Electrical insulation between boards/cell and strain relief. |
| [WMYCONGCONG 0.5 A slide switches, 100 pack](https://www.amazon.com/dp/B06XFXWLJP) | $8.99 | One battery disconnect, remaining switches are spares. |
| [DAOKI 6×6×4.3 mm momentary buttons, 100 pack](https://www.amazon.com/dp/B07X8S99RH) | $5.79 | One dismiss/test button, remaining switches are spares. |
| **Subtotal** | **$134.43** | One retail pack of each listing, not 14 finished watches. |

No soldering iron, meter, programmer, breadboard, extra screen, microSD card,
extra USB cable or filament was added. Reuse the user's USB-C data cable and
printing material. Borrow solder/flux, fine-tip iron, tweezers, wire stripper,
cutters, multimeter, suitable current-measurement setup, calipers and screwdriver.
The generic assortment packaging includes many spares because single components
are not generally sold individually with the same delivery options.

The user also has free printer/filament access through an angel investor and
owns a printer. See the new [assembly guide](ASSEMBLY.md) and
[first-fit case design](case/README.md). The old PN2222 motor circuit is replaced
by the DRV2605L; no standalone transistor is needed or added to this cart.

## Compatibility and assembly plan

This is a soldered prototype, **not a plug-together kit**. The manufacturer's
[schematic](https://files.waveshare.com/wiki/ESP32-S3-LCD-1.3/ESP32S3_1.3inch.pdf)
dated March 19, 2025 establishes the following routing and power design. Check the
received revision against it before assembly.

- GPIO1–5 and GPIO7–14 are exposed general-purpose pins. LCD uses GPIO38–42,
  backlight GPIO20; IMU uses GPIO47/48. Avoid GPIO3's strapping role.
- Proposed free-pin assignment: mic BCLK GPIO4, LRCLK GPIO5, DOUT GPIO9;
  haptic SDA GPIO7, SCL GPIO8; dismiss button GPIO10 to ground with input pull-up.
  This is a schematic-based allocation, not tested firmware.
- Power mic and haptic breakout from **3.3 V** and common ground. Tie mic SEL to
  ground for the left I2S slot. Use the required I2S slot width/clocking for this
  microphone; verify continuous 16 kHz capture before adding inference.
- Connect motor only to the DRV2605L motor outputs. Configure it for an ERM motor
  and approximately 3 V rated drive; do not blindly run default LRA settings or
  connect a motor directly to a GPIO. Physical vibration strength remains untested.
- Battery positive goes through the common and one throw of the slide switch to
  BAT1 positive. Battery negative goes to BAT1 ground. Leave the unused throw
  disconnected; do not connect it to ground. Meter polarity end-to-end, not just
  wire colors. Make adapters with the battery unplugged; do not cut live cell leads.
- Match connector housings before applying force. If generic pigtails do not
  mate with the received board, wire the matching connector pair to BAT1 pads
  during assembly instead; this is additional soldering, not a confirmed fit.

## Charging modification — required before charging this small cell

The schematic shows a **PL4054 charger** with **R5 = 1 kΩ** from PROG to ground.
That setting is not accepted for the selected 500 mAh cell. Its manufacturer
datasheet's demonstration circuit specifies approximately **100 mA with 10 kΩ**.
See the [Pulan PL4054 datasheet](https://datasheet4u.com/download_new.php?id=1251766),
demo-board instructions (page 12).

1. Keep USB and battery disconnected while doing rework.
2. Identify the actual charger and PROG resistor on the received revision.
   Replace R5 with **10 kΩ**, rather than adding it in parallel. The leaded part
   needs short insulated leads and strain relief; it is not a drop-in SMD part.
   An experienced assembler may use their own matching-footprint 10 kΩ instead.
3. Verify resistance, polarity and charge current (target approximately 100 mA)
   using suitable bench equipment before normal cell charging. Verify the
   charger terminates at the correct 4.2 V single-cell limit. Stop if the
   installed charger differs and resolve its documentation first.
4. Until verified, develop on USB with the battery disconnected. The power switch
   can isolate the battery, but its wiring also needs verification first.

This small-component rework requires appropriate soldering skill, beyond merely
borrowing an iron. No separate charger was added because the board contains one;
an unmodified high-current TP4056 board would not resolve this issue.

## Remaining product work

- Port quantized full 521-class YAMNet and the matching log-mel frontend to ESP32-S3;
  memory capacity is plausible, but current 480 ms cadence and accuracy are not
  verified on this hardware. No smaller sound vocabulary has been approved.
- Maintain microphone capture while the screen sleeps. No phone or internet during use.
- Dry-fit and refine the **new first-fit enclosure** in [case/](case/README.md)
  around the board, battery, mic, driver, switch, button, wiring and charging
  resistor. It uses M2 captive nuts and the 20 mm strap; physical fit is unverified.
- Provide a bottom-mic acoustic opening, strain relief, battery clearance and smooth
  wrist-facing surfaces. Comfort, temperature and runtime require physical trials.
- The cart establishes Thursday parts estimates, not Thursday-morning arrival or
  a finished, reliable standalone demonstration. Nothing has been purchased.
