# FortWatch — Tablero de accionables (Cal Hacks 13.0)

> Fuente de verdad del equipo. Mover tareas cambiando el estado: `TODO` → `DOING` → `DONE` (o `CUT`).
> Contexto técnico y decisiones: [PROJECT_STATUS.md](PROJECT_STATUS.md) · Setup: [README.md](README.md) · Carcasa: [hardware/enclosure](hardware/enclosure/)
> Dashboard en vivo: `python3 -m http.server 8765` en la raíz → http://localhost:8765/dashboard.html

## 🧭 Arquitectura actual (definida 24/10)
```
Mic de la Mac / iPhone ─► YAMNet en la Mac (10 alertas) ─► Bluetooth LE ─► Pulsera ESP32-S3: alerta a pantalla completa + vibración
```
El Grove Sound Sensor **ya no se usa** (su amplificador satura con alarmas/bocinas y no sirve para clasificar). Ver "Key decisions" en PROJECT_STATUS.

## 🎯 Definición de "terminado" para la demo
Pulsera en la muñeca (carcasa impresa + power bank) conectada por Bluetooth a la Mac: ante golpes en la puerta, una alarma o una bocina muestra la alerta a pantalla completa y **vibra** con un patrón según la prioridad. Video de backup grabado.

## ⏱️ Hitos (checkpoints duros)
| Hito | Qué tiene que existir |
|---|---|
| M1 | ✅ Pipeline Mac → BLE → pulsera funcionando (Pedro) · ✅ `plate.stl` verificado |
| M2 | Motor vibrando con las alertas · carcasa impresa |
| M3 | Todo montado en la muñeca con power bank, prueba en vivo de cada alerta |
| M4 | **Feature freeze.** Video de backup grabado · Devpost en borrador |
| M5 | Pitch ensayado 3 veces · Devpost enviado |

---

## 🛒 0. Compras / hardware desk
| ID | Estado | Tarea | Owner | Done cuando |
|---|---|---|---|---|
| P1 | DONE | Retirado: KY-037, DC motor 130, PN2222, 1N4007 (ver [INVENTORY](docs/hardware/INVENTORY.md)) | Joaquin | En mano |
| P2 | DONE | Chip del mic leído: KY-037 (LM393) → no sirve para clasificar | Joaquin | — |
| P3 | TODO | (Opcional, roadmap) Conseguir **INMP441** para clasificación en la pulsera | | Conseguido o descartado |
| P4 | DONE | Impresoras de la venue identificadas: Bambu P1S y Flashforge Adventurer 5M | Joaquin | — |
| P5 | TODO | 2 tiras de velcro de 20 mm | | En mano |

## 🔌 1. Hardware / electrónica
| ID | Estado | Tarea | Owner | Depende | Done cuando |
|---|---|---|---|---|---|
| H1 | CUT | ~~Grove Sound Sensor en GPIO4~~ → el mic es la Mac/iPhone | | — | — |
| H4 | TODO | Probar power bank → USB-C de la placa 15 min (¿se apaga por bajo consumo?) | | — | Funciona 15 min seguidos |
| H5 | CUT | ~~Recortar pines~~ → la carcasa deja lugar para jumpers Dupont | | — | — |
| H6 | DONE | Motor en breadboard: GPIO17 → 1 kΩ → base PN2222, emisor a GND, motor entre **5V** y colector, **1N4007** en paralelo al motor (franja al 5V) | Joaquin | P1 | ✅ Probado 24/10: vibra (foto `docs/hardware/motor-breadboard-working.jpg`) |
| H7 | TODO | Pasar el circuito del motor a formato "sin breadboard" (jumpers hembra + cinta, diodo en los terminales del motor) | | H6 | Entra en la carcasa |

## 💾 2. Software (Mac + pulsera)
| ID | Estado | Tarea | Owner | Depende | Done cuando |
|---|---|---|---|---|---|
| S1 | DONE | `mac_listener.py`: mic → YAMNet → 10 alertas con umbrales elegidos con ESC-50 | Pedro | — | Ver README |
| S2 | DONE | Firmware pulsera: alertas a pantalla completa + barra de nivel + BLE/USB | Pedro | — | Probado en la placa |
| S3 | DONE | Vibración por prioridad en el firmware (seguridad 3 largas · atención 2 cortas · baja 1 corta · autotest al encender) | Joaquin | — | Compila; falta probar con el motor (H6) |
| S4 | DOING | Probar en vivo cada alerta con sonidos reales y ajustar con `--set`. ✅ Mic iPhone + USB: CAR_HORN 0.57–0.87, SPEECH 0.90–0.98 llegan a la pulsera. ❌ Golpes en la mesa → "Basketball bounce", no KNOCK (probar con una puerta) | Joaquin | S1 | Tabla alerta → score típico |
| S5 | TODO | Modo ensayo: pasar una grabación fija por el mismo pipeline (demo reproducible) | | S1 | Demo idéntica cada vez |
| S6 | DOING | (Implementado, falta probar) Descartar alerta tocando la pantalla (touch CST816 en I2C SDA 48 / SCL 47) — dentro de la carcasa el BOOT queda en la ranura del USB | | S2 | Toque descarta |
| S7 | DONE | Diseño Figma de las 13 pantallas + escenarios + prototipo ([docs/design](docs/design/README.md)) y **slider** en la pulsera (`live_demo/screen_preview`) para verlas en el display real | Joaquin | — | Slider corriendo en la placa |
| S8 | DONE | Pantallas de Figma en el firmware real (`fortwatch_display`): imagen de cada alerta + barra de confianza real, ecualizador en vivo, nº de alertas | Joaquin | S7 | Alertas en vivo con el diseño nuevo |
| S9 | DONE | Analytics en vivo con SpacetimeDB (`analytics/`): `mac_listener.py` sube cada alerta (nunca audio) y el dashboard muestra los últimos 3 min, gráficos por período y si la alerta llegó a la pulsera | Nico | S1 | Falta probar en una corrida real con micrófono |

## 🧊 3. Carcasa 3D ([hardware/enclosure](hardware/enclosure/))
| ID | Estado | Tarea | Owner | Depende | Done cuando |
|---|---|---|---|---|---|
| C1 | DONE | Carcasa paramétrica, encastre sin tornillos (reglas PLA), todo adentro, verificada con `check_stl.py` | Joaquin | — | `hardware/enclosure/stl/plate.stl` |
| C2 | DOING | **Reenviar `plate.stl` (v3: sin Grove, repisa del power bank, STL binario limpio)** a la cola de impresión. v1/v2 dieron "file error" en la Adventurer 5M (form Cal Hacks, 2 h, settings en [README](hardware/enclosure/README.md)) | | — | Aparece en el spreadsheet de la cola |
| C3 | DONE | Motor medido (130: 25 mm + eje) | Joaquin | — | — |
| C5 | TODO | Montaje: vidrio → shell, motor + contrapeso en la cuna, transistor/cables en el compartimento, tapa a presión, velcro | | C2, H7 | Se usa en la muñeca 10 min sin moverse |

## 🧪 4. Validación (números reales para el pitch)
| ID | Estado | Tarea | Owner | Done cuando |
|---|---|---|---|---|
| V1 | TODO | Latencia sonido → alerta en la pulsera (video a 60 fps) | | Número en ms |
| V2 | TODO | Falsas alertas: 5 min en zona tranquila + 5 min en zona ruidosa | | Tabla en PROJECT_STATUS |
| V3 | DOING | Hablar con ≥1 persona sorda/hipoacúsica (o mentor de accesibilidad). ✅ Sierra (Sierra College): no le alcanza para un Apple Watch y espera compañía para salir sola ([docs/user-research](docs/user-research/README.md)) | Nico | 3 learnings |
| V4 | TODO | Alcance Bluetooth en la venue llena | | Metros anotados |

## 🎤 5. Demo / Devpost
| ID | Estado | Tarea | Owner | Done cuando |
|---|---|---|---|---|
| D1 | TODO | Grabar **video de backup** de la demo | | Video guardado |
| D2 | TODO | Devpost: texto, fotos de la pulsera, diagrama Mac → BLE → pulsera, limitaciones honestas | | Enviado |
| D3 | TODO | Elegir tracks: Hardware Hack + People-First Social Impact (verificar reglas) | | Inscritos |
| D4 | TODO | Ensayar pitch 3 min con cronómetro ×3 | | <3:00 |

---

## ✂️ Plan de recorte (si vamos tarde, cortar en este orden)
1. Touch para descartar (S6) → queda el botón BOOT
2. Modo ensayo (S5) → usar el video de backup
3. Motor dentro de la carcasa → motor afuera pegado a la correa, o sin vibración
4. **Nunca cortar:** pipeline Mac → pulsera + carcasa en la muñeca + video backup

## 🚫 Reglas de honestidad
- La clasificación corre en la **Mac**, no en la pulsera: decirlo así en el pitch.
- Los umbrales se midieron en grabaciones limpias (ESC-50); en una sala real rinde peor.
- No es un dispositivo de emergencia certificado.
