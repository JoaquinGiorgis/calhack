# Inventario de hardware — FortWatch

> **Arquitectura actual (24/10):** el micrófono es el de la Mac/iPhone y YAMNet clasifica en la Mac (ver [PROJECT_STATUS](../../PROJECT_STATUS.md)).
> En la pulsera solo van: la placa Waveshare, el **motor + PN2222 + 1N4007 + 1 kΩ**, y el power bank por USB-C.
> Los sensores Grove y el KY-037 quedan **sin uso**.

## ✅ Lo que ya tenemos (kit del equipo)
| Cant. | Componente | Uso en FortWatch |
|---|---|---|
| 1 | Waveshare **ESP32-S3-Touch-LCD-2** (pantalla 2" táctil, IMU QMI8658 incluida) | Cerebro + pantalla. Núcleo del proyecto |
| 1 | Grove Sound Sensor | ~~Sensor V1~~ — sin uso: su amplificador satura con alarmas/bocinas |
| 1 | Grove Touch Sensor | Sin uso (la pantalla ya es táctil) |
| 1 | Grove Button | Botón físico de respaldo |
| 1 | Grove LED Socket Kit | Flash visual extra en alertas |
| 1 | Grove Rotary Angle Sensor | (Opcional) perilla de sensibilidad |
| 1 | Grove 3-Axis Accelerometer | No hace falta (la placa ya trae IMU) |
| — | Cables Grove, jumpers M/M, M/F, F/F, breadboards, resistencias | Cableado y pruebas |
| 1 | Power bank USB-C | Alimentación (va en el bolsillo) |
| — | Sensor ultrasónico, NFC tag | No se usan |

## 🛒 Pedido al hardware desk de Cal Hacks (máx. 5 unidades)
| Cant. | Nombre exacto en el catálogo | Para qué |
|---|---|---|
| 1 | **Microphone sound sensor module** | ⭐ Prioridad. Si trae chip MAX4466/MAX9814 → habilita V2 (clasificar sonidos) |
| 1 | **Sensitive microphone sensor module** | Mic de respaldo, más chico |
| 1 | **DC motor (3–6V, fan motor)** | Vibración (háptica) |
| 1 | **NPN transistor PN2222** | "Interruptor" para el motor (el GPIO no aguanta la corriente del motor) |
| 1 | **Rectifier diode 1N4007** | Protege la placa de los picos de voltaje del motor |

Si el carrito lo permite: 2× PN2222 y 2× 1N4007 como repuesto (hay más de 80 de cada uno).
**No pedir:** MPU6050/GY-6500 (ya hay IMU), buzzers (el usuario es sordo), Arduino/ESP32 (ya tenemos la Waveshare).

## ❓ Confirmar dentro de la venue (no está en el catálogo)
| Qué | Plan B |
|---|---|
| Cable USB-C **de datos** laptop → placa (para programar) | Pedir a otro equipo / mentor |
| Cable power bank → placa | El mismo cable de datos |
| Impresora 3D | Montar con cinta doble faz / precintos sobre el velcro |
| Velcro 20 mm | Banda elástica o cinta |
| Micrófono I2S INMP441, motor vibrador de moneda, LiPo 3.7 V MX1.25 | Preguntar a otros equipos; si no, V2 = "visión" en el pitch |

## 📦 Recibido del hardware desk (24/10) — fotos: `parts-received-*.jpg`
| Pieza | Identificación | Conclusión |
|---|---|---|
| Módulo micrófono rojo (pines AO · G · + · DO, trimmer azul, chip 8 patas) | Tipo **KY-037**: cápsula electret + comparador **LM393** (no es un amplificador MAX4466/MAX9814) | **V2 (clasificar sonidos) no es viable con este módulo** → V2 queda como visión. Útil como sensor de respaldo: **DO** da un "sonido fuerte sí/no" con umbral ajustable en el trimmer |
| Motor plateado con tapa blanca | Motor "130" estándar (coincide con lo asumido en la carcasa) | Háptica OK con PN2222 + 1N4007 |
| Transistor negro 3 patas | PN2222 (TO-92) | Driver del motor |
| Diodo negro con franja | 1N4007 | Protección del motor (la franja va al + del motor) |

**Micrófono:** el de la Mac/iPhone (YAMNet). Grove y KY-037 quedan sin uso.
