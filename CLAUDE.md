# FortWatch — Cal Hacks 13.0

Pulsera de accesibilidad para personas sordas/hipoacúsicas. **Arquitectura actual:** el micrófono de la Mac (o iPhone por Continuity) → YAMNet en la Mac clasifica 10 alertas → Bluetooth LE → pulsera Waveshare ESP32-S3-Touch-LCD-2 que muestra la alerta a pantalla completa y vibra.

- Estado, decisiones y limitaciones (fuente de verdad técnica): [PROJECT_STATUS.md](PROJECT_STATUS.md)
- Setup y uso: [README.md](README.md)
- Tablero de tareas: [BOARD.md](BOARD.md) — mantenerlo actualizado al terminar cada tarea; se ve en `dashboard.html`
- Firmware de la pulsera: `live_demo/fortwatch_display/` (Arduino IDE, arduino-cli o `pio run -t upload` desde esa carpeta)
- Inventario de hardware: [docs/hardware/INVENTORY.md](docs/hardware/INVENTORY.md)
- Carcasa 3D (OpenSCAD paramétrico, encastre sin tornillos): [hardware/enclosure/](hardware/enclosure/) — tras cambiar el `.scad`: `node hardware/tools/export-stl.mjs` y correr `hardware/tools/check_stl.py`

## ⚠️ El equipo NO tiene experiencia en hardware — Claude actúa como mentor
- Explicar en español, paso a paso, sin asumir conocimientos de electrónica. Decir **qué cable va a qué pin** con el número/nombre impreso en la placa.
- Antes de cualquier conexión: indicar riesgos y pedir que desconecten el USB mientras cablean. Pedir foto del cableado antes de enchufar.
- Reglas de seguridad no negociables:
  - Los GPIO del ESP32 son de **3,3 V**: nunca meter 5 V a un pin GPIO.
  - Nunca alimentar un motor directo desde un GPIO: siempre transistor + diodo.
  - Verificar GND común entre todo.
- Preferir la solución más simple que funcione en la demo.
- Ser honesto sobre límites: la clasificación corre en la Mac; los umbrales se midieron en ESC-50 (grabaciones limpias).

## Pines usados (header de 28 pines)
| Señal | Pin placa | Notas |
|---|---|---|
| Motor (vía 1 kΩ → base PN2222) | **GPIO17** (impreso "17", columna izquierda, 5° desde la punta opuesta al USB) | Motor entre 5V y colector, 1N4007 en paralelo |
| 5V / GND del motor | "5V" / "G" (columna izquierda, abajo) | |
| Botón BOOT (descartar alerta) | GPIO0 | Accesible por la ranura del USB en la carcasa |
| **No usar** | GPIO47 / GPIO48 | Son el I2C del touch (CST816, addr 0x15) |
| Pantalla ST7789 (interna) | SCLK 39, MOSI 38, MISO 40, DC 42, CS 45, BL 1 | |
