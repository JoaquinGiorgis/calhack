# FortWatch: capacidades tras actualizar desde main

Fecha: 25 de octubre de 2026, America/Los_Angeles.

Se integraron los ocho commits de `origin/main` hasta `88aebcb` sobre
`codex/iphone-spatial-direction`, cuya base previa era `998a92f`.
**El main remoto todavía no incluye `ios/`: la app nativa está en esta rama local.**
Esta auditoría revisa código, documentación y pruebas de software. Los avances
físicos citados son reportes del equipo en [BOARD.md](../BOARD.md), no pruebas
realizadas de nuevo durante esta revisión.

## Qué cambió en main

- **Golpes:** el detector YAMNet de la Mac amplía KNOCK a siete clases y usa
  umbral 0.30. Veta GLASS cuando las clases de impacto en madera puntúan igual o
  más alto. Es una heurística; no garantiza separar cualquier golpe de vidrio.
- **Scores y Bluetooth:** exige que el sonido siga superando el umbral en la
  ventana actual y reintenta el escaneo si Bluetooth deja de estar disponible.
- **Touch:** tocar descarta una alerta; mantener la home o BOOT un segundo cambia
  SPEECH On/Off. La preferencia queda guardada tras reiniciar. Las coordenadas
  táctiles se leen, pero todavía no hay navegación por distintas zonas.
- **Wi-Fi:** conexión a redes conocidas sin escaneo explícito continuo y pausas
  crecientes de 5–60 segundos. El equipo reporta que desaparecieron los reinicios
  al perder el hotspot; eso no demuestra estabilidad de larga duración.
- **Hardware reportado:** circuito del motor sin breadboard funcionando con power
  bank y alertas, carcasa/tapa/contrapesos impresos y touch probado el 25/10.
  El montaje y uso sostenido en la muñeca siguen en progreso.
- **Presentación:** landing en inglés, video, imágenes y metadatos sociales. Su
  ruta `/dashboard` redirige a un servicio externo; no incluye ese backend.

## Qué puede hacer ahora cada parte

| Parte | Implementado en el código actual | Límite o comprobación pendiente |
|---|---|---|
| Demo Mac | YAMNet, 10 alertas, prioridades, BLE/USB, reconexión | Pruebas reales por categoría incompletas; métricas anteriores no validan el nuevo veto |
| App iPhone local | Apple SoundAnalysis en el teléfono, BLE directo, prueba de vibración, hora/nivel/eventos | Captura FOA probada en el iPhone; usuario confirma prueba BLE/KNOCK/motor. Precisión angular pendiente |
| Dirección | Un ángulo dominante de la misma ventana del evento; calibración; arco con ícono en app y firmware | No asocia una dirección independiente a cada fuente; otra fuente puede desviar el ángulo incluso con calidad alta |
| Pulsera | Pantallas de alerta, motor por prioridad, touch/BOOT, SPEECH On/Off persistente | Un solo motor; no produce vibración física izquierda/derecha ni reconoce audio por sí misma |
| Analytics | Subida opcional de metadatos desde la pulsera por Wi-Fi | Requiere configuración privada, red y servicio externo; no garantiza guardar cada alerta |
| Carcasa | Diseño/STLs y piezas reportadas como impresas | Autonomía, sujeción y prueba de uso prolongado pendientes |
| Círculo estilo Fortnite | Arco parcial, retículo e ícono implementados en Swift y firmware | Una sola dirección dominante; ver [actualización de diseño](DIRECTION-DESIGN-UPDATE.md) para instalación y pruebas |
| Decir “Fortnite” | No implementado | Detectar SPEECH no transcribe ni identifica palabras |
| Varios sonidos con distintos ángulos | No implementado | Requiere detección/localización por fuente y validación con mezclas reales |
| Escucha en segundo plano / bolsillo | No implementado | La app se detiene al ir al fondo y requiere teléfono fijo para dirección |

El micrófono de un iPhone usado por Continuity en la demo Mac **no equivale** a la
app nativa autónoma. En ese modo, YAMNet sigue corriendo en la Mac.

## Integración resuelta

1. Se resolvió el conflicto de `handleLine` conservando el parser validado con
   dirección y el nuevo filtro SPEECH: parsear → filtrar → mostrar/vibrar.
2. Se preservó el veto GLASS también en `SpatialEventProcessor`, el modo espacial
   opcional de la Mac. El merge automático había incorporado las nuevas clases
   pero omitido el veto. Una prueba reprodujo el fallo; después de corregirlo pasan
   los casos madera mayor/igual a vidrio y vidrio dominante, conservando el ángulo.
3. Se eliminó el ID S11 duplicado del tablero: la extensión iPhone ahora es S12.
4. Se actualizaron las tablas desactualizadas de estado y umbrales. La configuración
   personal de firma de Xcode se conserva como cambio local, fuera del commit.

## Hallazgos que siguen abiertos

- **La heurística Mac no se trasladó al iPhone.** Swift mantiene `knock` y
  `glass_breaking` a 0.65 con políticas propias. Copiar nombres de YAMNet al
  clasificador Apple no sería una integración válida.
- **SPEECH apagado no se comunica al iPhone.** La pulsera descarta el evento antes
  de mostrarlo, vibrar o subirlo. “Enviada” en la app solo indica aceptación del
  envío por CoreBluetooth, no aceptación del filtro ni vibración física.
- **Analytics puede perder eventos durante una caída de Wi-Fi.** La cola de
  entrada tiene 16 lugares y el backoff puede dormir 60 segundos sin drenarla;
  el evento 17 se descarta aunque quede espacio en el buffer de 50 pendientes.
  Esto afecta el historial remoto, no la alerta local ni el motor. No se corrigió
  como parte de esta auditoría.
- **La landing promete capacidades ausentes.** “Runs on the wristband”, “No phone”
  y “Audio never leaves your wrist” contradicen el procesamiento real en Mac o
  iPhone. Los enlaces Reserve apuntan a una sección que no existe. Debe ajustarse
  antes de presentar esas frases como funciones entregadas; no se publicó ningún
  cambio de sitio en esta revisión.
- **Los documentos heredados no son prueba física.** El tablero actualizado
  registra avances que versiones anteriores de PROJECT_STATUS aún no reflejaban.
  CLAUDE.md e INVENTORY siguen describiendo la arquitectura de la demo Mac.

## Verificación de esta revisión

| Comprobación | Resultado | Alcance |
|---|---|---|
| iOS, Xcode 26.6, simulador iPhone 17 Pro/iOS 26.5 | PASS: 26 pruebas | Compilación, PCM, dirección sintética, eventos y mensajes BLE; firma desactivada |
| Python, suite espacial y de transporte | PASS: 16 pruebas | Incluye regresión del veto KNOCK/GLASS |
| Etiquetas del YAMNet incluido | PASS | 521 etiquetas; resuelven los 10 mapeos de alerta y el veto |
| Parser C++ con ASan/UBSan | PASS | Mensajes antiguos/nuevos, límites, datos inválidos y borrado de dirección previa |
| Firmware ESP32-S3 sin analytics | PASS | Compilación PlatformIO, RAM 64,580 B, flash 2,956,709 B |
| Firmware ESP32-S3 con analytics | PASS | Copia temporal con configuración de ejemplo; RAM 84,100 B, flash 3,619,569 B |
| Captura/ángulos/BLE/motor con esta versión combinada | NOT RUN | Requiere dispositivos y sonidos reales |
| Reinicios/rango/batería/entrega a dashboard bajo fallos | NOT RUN | La compilación no demuestra estos comportamientos |

Comandos principales:

```sh
git pull --no-rebase origin main
xcodebuild -project ios/FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' \
  CODE_SIGNING_ALLOWED=NO test
.venv/bin/python -m unittest discover -s live_demo/tests -p 'test_*.py' -v
c++ -std=c++17 -fsanitize=address,undefined -fno-omit-frame-pointer \
  live_demo/tests/test_alert_protocol.cpp -o /tmp/fortwatch-alert-protocol-tests
/tmp/fortwatch-alert-protocol-tests
pio run --project-dir live_demo/fortwatch_display
git diff --check
```

La segunda compilación de firmware usó una copia temporal con
`secrets.example.h` como `secrets.h`; no se crearon credenciales reales ni se
conectó a una red. Evidencia de esta revisión en
`/tmp/fortwatch-main-sync.TDMCyp/`: `ios-tests.xcresult`, `ios-tests.log`,
`python-tests.log`, `firmware-build.log` y `firmware-analytics-build.log`.
No se instaló esta combinación en el iPhone ni se flasheó la pulsera.

## Próximas comprobaciones físicas, antes del modo multisonido

1. Identificar qué firmware está realmente cargado en la pulsera y comprobar
   conexión directa desde FortWatch más la prueba KNOCK de dos pulsos.
2. Probar una fuente a la vez desde izquierda, frente y derecha, con el iPhone
   fijo y calibrado; anotar errores, demora y alertas perdidas.
3. Probar dos fuentes simultáneas para medir la limitación actual y decidir la
   integración de un modelo que detecte y localice cada fuente por separado.
