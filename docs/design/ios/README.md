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
- Tarjetas de 20 pt de radio y acciones principales de 14 pt.
- Jerarquía: conexión Bluetooth → dirección → estado → último sonido → instrucciones.
- El inicio/parada queda visible abajo. Con letra de accesibilidad se integra
  al contenido desplazable para no cubrir la mayor parte de la pantalla.
- Se quitaron los campos IP/código: hay conexión BLE directa y prueba de vibración.
  El texto crece con Dynamic Type; los controles tienen al menos 44 pt.
- Se conservan los estados de espera, captura, calibración, dirección incierta,
  permiso denegado con acceso a Configuración y pulsera sin confirmar.
- Captura y clasificación corren en el iPhone. Se conservan los mensajes del firmware
  y la caducidad del ángulo; no se muestran resultados sintéticos como alertas reales.

## Verificación, 24 de octubre de 2026

- Compilación para simulador iPhone 17 Pro / iOS 26.5: PASS.
- Compilación para el iPhone conectado con firma local existente: PASS.
- Tests existentes de contrato y audio: PASS, 26 tests y 0 fallos.
- Inspección visual de la pantalla inicial con tamaño de letra normal y máximo
  de accesibilidad: PASS; corregido el espacio ocupado por el botón fijo.
- Revisión independiente por lectura de controles, estados y accesibilidad:
  sin hallazgos concretos. VoiceOver no verificado manualmente.
- Instalación de la versión BLE directa en el iPhone físico: PASS. Apertura automática
  bloqueada por pantalla bloqueada. Precisión angular y vibración física: pendientes.

Referencia de accesibilidad: [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility).

![Pantalla inicial en el simulador](listener.png)
