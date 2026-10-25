# Diseño — FortWatch Wristband UI

Archivo Figma: https://www.figma.com/design/cH0vUVYbWNC08hdZPzTIaw

| Sección en Figma | Qué tiene |
|---|---|
| **Cover** | Foto (IA) de la **carcasa v3.1** (4,2 × 9,2 cm) con el **power bank atravesado en la muñeca y pegado a la punta**, y la **pantalla KNOCK real** en el área activa 4:3 del display |
| **Scenarios** | 5 escenas (puerta, alarma, bocina, bebé, vidrio): foto + texto "oye → muestra → vibra" + pulsera con la alerta correcta |
| **Prototype** | Flujo navegable (▶ Present): Waiting → Listening → Hearing → KNOCK → ALARM, toque para descartar |
| **Home screen (Liquid Glass)** | Pantalla principal estilo iOS: wallpaper fotográfico, reloj, widgets de vidrio *Listening* (barras en vivo) y *Last alert* (ícono + nombre + hace cuánto). La variante *Home (firmware)* es el fondo que usa la pulsera; el resto lo dibuja el firmware con Inter |
| **Components** | `Alert screen` (10 variantes, 320×240), `System screen` (Waiting/Listening/Hearing), `Vibration pattern` (Safety/Attention/Low), `Wristband device` (mockup), íconos |
| Variables `SoundSense` (nombre viejo, sigue así en Figma) | Colores por alerta (contraste AA con texto blanco) |

Fotos de referencia en esta carpeta: generadas con la IA de Figma (no son fotos reales del prototipo). `hero-v3-knock.png` es la portada actual (base: `hero-v3.png`). Las demás `hero-*` son versiones anteriores.

## Probarlas en la pulsera (slider)
Las 13 pantallas exportadas están en `screens/` (320×240). Para verlas en el display real:
```bash
cd live_demo/screen_preview && pio run -t upload
```
Pasan solas cada 3 s; **BOOT** avanza a mano. Las alertas vibran con su patrón.
Si cambian el diseño en Figma: re-exportar a `screens/` y correr `python png_to_rgb565.py ../../docs/design/screens screens.h`.
