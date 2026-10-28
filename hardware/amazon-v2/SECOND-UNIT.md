# Stock remaining after one build

Prices rechecked in the signed-in Amazon cart October 27, 2026, approximately
11:05 p.m. Pacific. Cart still $134.43 before tax, 14 listings, all showing
Thursday October 29 delivery and an order countdown of about 55 minutes.
No items were added for a second unit and no order was placed.

## Buy again for unit two

| Item | Additional purchase |
| --- | ---: |
| Waveshare ESP32-S3-LCD-1.3 processor/display | $21.11 |
| Adafruit SPH0645 microphone | $11.58 |
| DRV2605L breakout, single module | $12.99 |
| KBT 500 mAh battery | $8.99 |
| Benchmark 20 mm nylon strap | $9.95 |
| **Additional cash for unit two** | **$64.62 before tax** |

This is a repeat of today's retail choices, assuming prices, stock and delivery
remain available. Printer/filament access and borrowed tools cost the user zero.
Wire, insulation, fasteners and motor/controls for unit two come from existing
packs. It excludes labor, replacement parts after mistakes, shipping fees if any,
firmware development and tool wear. It is an incremental purchase total, not
the complete per-unit manufacturing cost.

First cart plus that repeat purchase would be $199.05 before tax for two units
and leftover stock. Do not buy unit two now merely because the spare packs exist;
complete the first prototype's charging rework, fit and functionality checks first.

## Expected leftovers from the first cart

| Pack | First build uses | Remaining |
| --- | --- | --- |
| 20 coin motors | 1 | **19 motors** |
| 100 slide switches | 1 | **99 switches** |
| 100 tactile switches | 1 | **99 buttons** |
| 10 resistors, 10 kΩ | 1 | **9 resistors** (10 if workshop supplies the SMD replacement) |
| 20 pairs of prewired 1.25 mm connectors | 1 pair planned | **19 pairs**, unless the adapter needs another pair |
| 500 M2 screws, 100 nuts | 4×M2×4, 4×M2×5, 4 nuts | **492 screws and 96 nuts**; 96 each of the 4 mm and 5 mm screws |
| 30 ft total silicone wire, six colors | Short cut lengths | Most remains; exact consumption follows routing |
| 900 heat-shrink pieces | Several cut pieces | Most remains |
| Two 33 m rolls of polyimide tape | Short strips | Most remains |

No spare processor/display, microphone, haptic controller, battery or strap is
included. Exact leftovers change with rework, print fitting and mistakes.

## Original versus V2 size

The comparison uses the **saved original STL files**, not the latest SCAD
parameter values, which differ in dock width. The original is the 2-inch Waveshare
design with a large motor and a sideways USB-C power-bank shelf, in
`hardware/enclosure/`.

| Printed geometry | Original | V2 |
| --- | --- | --- |
| Main body, width × length × height | 41.9×92.3×32.9 mm | 52×50×24 mm |
| Complete printed assembly, including dock / strap ears | 77.8×135.3×32.9 mm | 52×67×24 mm |

The new main body is **24% wider, 46% shorter and 27% thinner**. Including the old
power-bank shelf and both designs' printed strap features, the printed footprint
is about **67% smaller**. These are outer-envelope comparisons, not solid volume,
weight or measured comfort. The old bank is only an approximate box in the preview
and may project above its printed case. The V2 battery is inside.

[Equal-scale CAD preview](case/original-vs-v2.png) · [Measured mesh bounds](case/size-comparison.json)

## Purchase decision

The cart is a documented prototype parts list, with **small-component charger
rework still required**, generic connector/switch fit checks and unfinished
standalone firmware. An experienced assembler must be able to perform or assist
with the R5 change and charge-current verification. Buying the cart does not
establish a ready-to-wear or Thursday-morning working prototype. Review delivery
again at checkout; do not treat the cart countdown as a guarantee.
