# FortWatch Listener — interfaz iPhone

Lectura del diseño: una herramienta de escucha accesible para usar el iPhone
junto a la pulsera, con fondo carbón, tarjetas azules, tipografía blanca e íconos
de línea. Conserva FortWatch y toma la referencia de las pantallas existentes de
la pulsera, sin añadir alertas ni mediciones ficticias.

Implementación nativa en SwiftUI para el proyecto iOS 26 existente.
Variación visual 5/10, movimiento 1/10, densidad 5/10. No hay animación decorativa.

- Base `#12141A`, superficie `#1C1F26`, texto secundario `#BAC2D1`.
- Panel de dirección y acción principal: azul `#294FD1` a `#122461`.
- Verde identifica la confirmación real de la pulsera; rojo, detener la captura.
- Tarjetas de 20 pt de radio, campos de 12 pt y acciones principales de 14 pt.
- Jerarquía: dirección → estado del enlace → conexión → instrucciones.
- El inicio/parada queda visible abajo. Con letra de accesibilidad se integra
  al contenido desplazable para no cubrir la mayor parte de la pantalla.
- Los campos tienen etiquetas accesibles, foco visible y controles de teclado.
  El texto crece con Dynamic Type; los controles tienen al menos 44 pt.
- Se conservan los estados de espera, captura, calibración, dirección incierta,
  permiso denegado con acceso a Configuración y pulsera sin confirmar.
- No se modificaron la captura, la caducidad del ángulo ni el protocolo.

## Verificación, 24 de octubre de 2026

- Compilación para simulador iPhone 17 Pro / iOS 26.5: PASS.
- Compilación para dispositivo iOS, sin firma: PASS.
- Tests existentes de contrato y audio: PASS, 9 tests y 0 fallos.
- Inspección visual de la pantalla inicial con tamaño de letra normal y máximo
  de accesibilidad: PASS; corregido el espacio ocupado por el botón fijo.
- Revisión independiente por lectura de controles, estados y accesibilidad:
  sin hallazgos concretos. VoiceOver e interacción completa con teclado no
  verificados manualmente.
- Instalación de este rediseño en el iPhone físico: pendiente; el dispositivo
  figura como no disponible. Precisión angular y vibración física: pendientes.

Referencia de accesibilidad: [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility).

![Pantalla inicial en el simulador](listener.png)
