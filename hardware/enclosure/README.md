# Carcasa SoundSense

Modelo paramétrico en OpenSCAD: [soundsense_case.scad](soundsense_case.scad). Medidas de la placa del dibujo oficial de Waveshare (`docs/hardware/waveshare-size.jpg`).

**Todo va adentro:** placa + pantalla, motor vibrador y driver. Solo sale el cable USB-C al power bank del bolsillo.

> **Arquitectura actual:** el micrófono es el de la Mac/iPhone (ver PROJECT_STATUS), así que el compartimento del micrófono queda libre: ahí van el transistor y los cables. La rejilla y los 4 postes no molestan.
**Sin tornillos:** la tapa trasera cierra por encastre (clic) con 4 lengüetas flexibles diseñadas con las reglas de PLA de [wilsonwaters/3d-printing](https://github.com/wilsonwaters/3d-printing): deformación 0,4 % (máx. 1–1,5 %), largo/espesor 10,4:1 (mín. 10:1), enganche 0,4 mm, redondeo en la raíz.

Tamaño: **41,9 × 116 × 33 mm** (57,9 mm de ancho con las orejas del velcro). Es gruesa a propósito: los **cables jumper hembra se enchufan directo en los pines de la placa**, sin cortar ni soldar nada.

```
 vista superior            (+Y = hacia el codo)
 ┌─────────────┐
 │ ░░ rejilla ░│  ← Grove Sound Sensor sobre 4 postes, micrófono pegado a la rejilla, conector hacia la pantalla
 │ [  motor  ]=o│  ← motor en la cuna + contrapeso
 ├─────────────┤  ← nervio que frena el vidrio (los cables pasan por debajo)
 │             │
 │  PANTALLA   │
 │             │
 └────[USB]────┘  ← ranura USB-C + botones RST/BOOT
```

## 🖨️ Para la cola de impresión de Cal Hacks
| Campo del formulario | Qué poner |
|---|---|
| STL | **`stl/plate.stl`** (shell + back + 2 contrapesos en un solo archivo) |
| Settings | `PLA, 0.2 mm layer, 3 walls, 20% infill, NO supports. Parts are already oriented flat on the bed — please don't rotate them. Brim optional.` |
| Duración estimada | **2 h** (en la venue hay Bambu P1S y Flashforge Adventurer 5M: ~1,5 h reales + preparación) |

Si rechazan el archivo por tiempo, mandar `shell.stl` y `back.stl` por separado.

## Piezas sueltas (`stl/`)
| Archivo | Qué es |
|---|---|
| `plate.stl` | ⭐ Todo junto, para un solo envío |
| `shell.stl` | Cuerpo + marco + techo con rejilla (cara de pantalla abajo) |
| `back.stl` | Tapa con orejas para el velcro, pared de encastre, 4 pilares y cuna del motor |
| `weight.stl` | Contrapeso que se calza a presión en el eje del motor (es lo que hace vibrar) |
| `fit_test.stl` | Solo el marco frontal (~15 min), si quieren probar el vidrio antes |

## Armado
1. Enchufar los cables jumper hembra en los pines que usamos (3V3, GND, GPIO4, GPIO17). **No hace falta cortar ni soldar.**
2. El vidrio entra por atrás en el `shell` y apoya contra el marco.
3. ~~Grove Sound Sensor~~ (ya no se usa): el transistor con sus jumpers va en ese espacio, envuelto en cinta aislante.
4. Motor acostado sobre su lado plano en la cuna, con el eje hacia el costado libre. Calzar el `weight` en el eje y verificar que gire sin tocar nada.
5. Transistor y diodo soldados en los cables, con cinta o termocontraíble.
6. Cerrar la tapa: entra derecha y hace **clic**. Los 4 pilares aprietan la placa contra el marco.
7. Para abrirla, meter una uña o moneda en la muesca del extremo y hacer palanca.
8. El velcro de 20 mm pasa por las ranuras de las orejas.

## ✅ Verificación automática (`hardware/tools/check_stl.py`)
- Todas las piezas son cerradas (watertight), con normales correctas y un solo cuerpo.
- Apoyan en la cama y entran en camas de 180 mm.
- Ninguna necesita soportes.
- Shell y tapa armadas no se pisan.
- Grove Sound Sensor, 2 filas de jumpers Dupont, conector USB-C enchufado, motor, eje y contrapeso girando entran sin chocar (simulación con sus medidas).
- Lengüetas del encastre dentro de los límites de PLA (deformación y proporción largo/espesor).

## ⚠️ Riesgos conocidos (no verificables sin imprimir ni medir)
| Qué | Si falla | Parámetro |
|---|---|---|
| Ajuste del vidrio (holgura 0,4 mm) | Muy flojo: cinta en el borde. Muy duro: lijar | `clr` |
| Pilares contra los separadores (sale del dibujo) | Placa floja: un trocito de cinta sobre cada pilar | `pcb_y_offset`, `pillar_extra` |
| Motor 130 medido por foto: cuerpo 25 mm + eje ~8 mm. **Cortar el precinto blanco** | Si el eje es más largo, cortarlo o calzar el contrapeso más adentro | `motor_l`, `motor_shaft` |
| Encastre muy duro o muy flojo | Lijar el nervio de la lengüeta o agregar cinta. PLA es frágil: cerrar/abrir con suavidad, pocas veces | `snap_r`, `tab_t` |

## Regenerar y verificar
```bash
cd hardware/tools && npm install && node export-stl.mjs
python3 -m venv .venv && .venv/bin/pip install trimesh manifold3d numpy scipy && .venv/bin/python check_stl.py
```
Ver en 3D: `python3 -m http.server 8765 --directory hardware/enclosure` y abrir http://localhost:8765/viewer.html
