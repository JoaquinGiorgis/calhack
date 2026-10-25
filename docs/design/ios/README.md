# FortWatch Listener — interfaz iPhone

La referencia vigente es la landing FortWatch mostrada por el usuario el 25/10:
foto de fondo oscurecida, paneles translúcidos, marca `fortwatch` en minúsculas,
tipografía blanca y acciones lima. Se reutilizan la foto de `docs/landing/` y
sus colores; Gabarito y Atkinson Hyperlegible Next se incluyen con sus licencias OFL.
Toda la interfaz está en inglés y usa SwiftUI nativo, iOS 26.

Lectura de diseño: herramienta accesible de escucha, funcional y compacta, con el
estilo fotográfico de la marca. Variación 4/10, movimiento 1/10, densidad 6/10.

- Acento `#8FD63D`, texto de botón `#12141F`, borde glass blanco al 38%.
- Cabecera pequeña, conexión visible, un panel de sonido y acción inferior.
- Una franja lima con flecha rellena y lado grande destaca la dirección.
- El arco e ícono aparecen únicamente con una medición utilizable; una alerta
  usa el ángulo de su propia ventana. La anchura del arco no expresa precisión.
- Inicio, permisos, calibración, rechazo e incertidumbre tienen estados explícitos.
- Sound library aparece directamente en inicio y permite aprender y probar los diez ritmos.
- Un catálogo único aporta nombre, significado, símbolo y colores a alerta, biblioteca e historial.
- Recent sound conserva la última detección sin una flecha vencida.
- Start listening reconoce sin exigir calibración; Calibrate front se usa para ubicación.
- Test vibration, guía de ritmos, ayuda, Settings y Disconnect están en el menú **…**.
- Colores por categoría en el badge; historial separado de la dirección reciente.
- Dynamic Type, objetivos de 44 pt o más, nombres VoiceOver, reflujo vertical en
  accesibilidad y panel opaco con Reduce Transparency. Sin animación decorativa.

## Verificación

- Builds de simulador y de iPhone: PASS. App instalada en el teléfono; firmware
  actualizado y hash verificado. La app se abrió tras el desbloqueo del usuario;
  luego se reinstaló una corrección de texto. Esa última reapertura encontró el teléfono bloqueado.
- 47 pruebas de audio, calibración, eventos, catálogo, historial y protocolo: PASS.
- Contrato compilado iPhone/pulsera: los diez ritmos coinciden y son distintos.
- Pantalla inicial y fixtures de KNOCK/calibración fallida inspeccionados en simulador.
- El fixture de abajo está etiquetado **SIMULATED STATE** y no usa micrófono/BLE.
- VoiceOver manual, precisión angular y aprobación visual del usuario: pendientes.

Estado funcional y pruebas físicas: [identidad de sonidos](../SOUND-IDENTITY.md).

![Pantalla inicial de la app en el simulador](listener.png)

![Vista de diseño con KNOCK simulado, no una medición](knock-preview.png)

![Guía de ritmos, vista de diseño sin pruebas físicas](vibration-guide-preview.png)

![Los diez tipos en vistas simuladas de la interfaz](sound-identities.png)
