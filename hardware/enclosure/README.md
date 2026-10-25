# Carcasa FortWatch

Modelo paramétrico en OpenSCAD: [fortwatch_case.scad](fortwatch_case.scad). Medidas de la placa del dibujo oficial de Waveshare (`docs/hardware/waveshare-size.jpg`).

**Todo va adentro:** placa + pantalla, motor vibrador y driver (transistor, diodo, resistencia y jumpers).
**Sin cables:** el power bank USB-C (tipo ARMADIN mini) se enchufa **de costado** directo en la placa, como en el banco de pruebas, y apoya sobre una **repisa** en la punta de la tapa.
**Sin tornillos:** la tapa trasera cierra por encastre (clic) con 4 lengüetas flexibles diseñadas con las reglas de PLA de [wilsonwaters/3d-printing](https://github.com/wilsonwaters/3d-printing): deformación 0,4 % (máx. 1–1,5 %), largo/espesor 10,4:1 (mín. 10:1), enganche 0,4 mm, redondeo en la raíz.

Tamaño: **41,9 × 92 × 33 mm** de cuerpo + repisa del power bank (78 mm de ancho × 40 mm). Los **jumpers hembra se enchufan directo** en los pines de la placa, sin cortar ni soldar.

```
 vista superior            (+Y = hacia el codo)
      ┌─────────────┐
      │ [  motor  ]=o│  ← motor en la cuna + contrapeso
      ├─────────────┤  ← nervio que frena el vidrio (los cables pasan por debajo)
      │  PANTALLA   │  ← debajo de la placa: transistor, 1 kΩ y diodo (entre las filas de pines)
      └──── USB ────┘  ← punta abierta: termina en el borde del vidrio
 ┌──────────────────────────┐
 │   POWER BANK (de costado)│  ← apoya en la repisa; velcro/gomita por las 2 ranuras
 └──────────────────────────┘
```

## 🖨️ Para la cola de impresión de Cal Hacks
| Campo del formulario | Qué poner |
|---|---|
| STL | **`stl/plate.stl`** (shell + back + 2 contrapesos en un solo archivo) |
| Settings | `PLA, 0.2 mm layer, 3 walls, 20% infill, NO supports. Parts are already oriented flat on the bed — please don't rotate them. Brim optional.` |
| Duración estimada | **2 h** (Bambu P1S o Flashforge Adventurer 5M: ~1,5 h reales + preparación) |
| Nota | Los STL son **binarios y sin triángulos degenerados** (`clean_stl.py`): la versión ASCII anterior daba "file error" en la Adventurer 5M |

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
0. **Desconectar el power bank y el USB** antes de tocar cables.
1. Enchufar los cables jumper hembra en los 3 pines que usa el motor, todos en la columna izquierda del header: **"17"** (señal, va a la resistencia de 1 kΩ → base del PN2222), **"5V"** (motor) y **"G"** (emisor del transistor). Mismo circuito que el de la breadboard (H6). **No hace falta cortar ni soldar.**
2. El vidrio entra por atrás en el `shell` y apoya contra el marco.
3. El transistor, la resistencia y el diodo van **debajo de la placa**, entre las dos filas de pines (hay 18 mm de alto libres), envueltos en cinta aislante.
4. Motor acostado sobre su lado plano en la cuna, con el eje hacia el costado libre. Calzar el `weight` en el eje y verificar que gire sin tocar nada.
5. Enchufar el power bank de costado en el USB-C, apoyado en la repisa. Si queda flojo (power bank más fino que 28 mm), una tira de cinta en la repisa; asegurarlo con velcro o una gomita por las 2 ranuras.
6. Cerrar la tapa: entra derecha y hace **clic**. Los 4 pilares aprietan la placa contra el marco.
7. Para abrirla, meter una uña o moneda en la muesca del extremo y hacer palanca.
8. El velcro de 20 mm pasa por las ranuras de las orejas.

## 🔋 Prueba antes de cerrar la tapa
Con todo adentro pero la tapa abierta, enchufar el power bank y verificar:
1. Al encender, el motor da **un pulso corto** (autotest) y la pantalla muestra *Waiting for Mac*.
2. Con el hotspot del iPhone prendido ("Maximizar compatibilidad"), correr `mac_listener.py`: la pantalla pasa a la home y la Mac dice `Connected to FortWatch over Bluetooth`.
3. Hablar unos segundos: aparece **SPEECH** (persona hablando), vibra 1 vez, y la alerta aparece en el dashboard de Mana. Si no aparece, conectar el USB y mirar el monitor serie (`Wi-Fi: ...` / `Analytics: ...`).
4. Tocar la pantalla a través del vidrio descarta la alerta (si no, usar BOOT por la ranura del USB).
5. Dejarlo 15 min con el power bank (tarea H4): que no se apague solo.

Recién ahí cerrar la tapa (clic).

## ✅ Verificación automática (`hardware/tools/check_stl.py`)
- Todas las piezas son cerradas (watertight), con normales correctas y un solo cuerpo.
- Apoyan en la cama y entran en camas de 180 mm.
- Ninguna necesita soportes.
- Shell y tapa armadas no se pisan.
- Power bank enchufado de costado (25 y 28 mm), 2 filas de jumpers Dupont, transistor/resistencia/diodo bajo la placa, motor, eje y contrapeso girando entran sin chocar (simulación con sus medidas).
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
cd hardware/tools && npm install && node export-stl.mjs && python clean_stl.py   # clean_stl: binary STL sin triángulos degenerados
python3 -m venv .venv && .venv/bin/pip install trimesh manifold3d numpy scipy && .venv/bin/python check_stl.py
```
Ver en 3D: `python3 -m http.server 8765 --directory hardware/enclosure` y abrir http://localhost:8765/viewer.html
