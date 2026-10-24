# Diseño — SoundSense Wristband UI

Archivo Figma: https://www.figma.com/design/cH0vUVYbWNC08hdZPzTIaw

| Sección en Figma | Qué tiene |
|---|---|
| **Cover** | Foto de la pulsera en la muñeca (IA) con **nuestra pantalla KNOCK real del firmware** superpuesta en el display |
| **Scenarios** | 5 escenas (puerta, alarma, bocina, bebé, vidrio): foto + texto "oye → muestra → vibra" + pulsera con la alerta correcta |
| **Prototype** | Flujo navegable (▶ Present): Waiting → Listening → Hearing → KNOCK → ALARM, toque para descartar |
| **Components** | `Alert screen` (10 variantes, 320×240), `System screen` (Waiting/Listening/Hearing), `Vibration pattern` (Safety/Attention/Low), `Wristband device` (mockup), íconos |
| Variables `SoundSense` | Colores por alerta (contraste AA con texto blanco) |

Fotos de referencia en esta carpeta: generadas con la IA de Figma (no son fotos reales del prototipo). En `hero-wrist-knock.png` la pantalla es inventada por la IA; en la portada de Figma está tapada por la pantalla real.

## Probarlas en la pulsera (slider)
Las 13 pantallas exportadas están en `screens/` (320×240). Para verlas en el display real:
```bash
cd live_demo/screen_preview && pio run -t upload
```
Pasan solas cada 3 s; **BOOT** avanza a mano. Las alertas vibran con su patrón.
Si cambian el diseño en Figma: re-exportar a `screens/` y correr `python png_to_rgb565.py ../../docs/design/screens screens.h`.
