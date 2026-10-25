# FortWatch para iPhone — conexión directa a la pulsera

```text
Micrófonos iPhone → reconocimiento y dirección en el iPhone → Bluetooth LE → pulsera
```

La app funciona sin Mac, servidor, Wi-Fi ni cuenta durante la escucha. El iPhone
reconoce sonidos con YAMNet incluido (521 clases, ejecución Core ML) y calcula
el ángulo del sonido dominante con audio espacial FOA. Solo manda pequeños
mensajes de evento, nivel y hora a la pulsera; el audio no sale del iPhone ni se
guarda en esta app. La Mac con Xcode se usa para compilar e instalar el prototipo.

## Usarla

1. Abrir `FortWatchListener.xcodeproj`, elegir el equipo propio en **Signing &
   Capabilities**, seleccionar el iPhone conectado y tocar **Run**. Requiere iOS 26
   y captura FOA compatible, por ejemplo iPhone 16 Pro o posterior. La app verifica
   el soporte real y los cuatro canales antes de escuchar.
2. Encender la pulsera con el firmware FortWatch. Cerrar el receptor anterior
   `mac_listener.py` para que no ocupe la conexión Bluetooth.
3. En la app tocar **Connect** y permitir Bluetooth. La conexión se hace
   desde la app; no requiere emparejar un dispositivo de audio en Ajustes.
4. Abrir **Sound library**, buscar un sonido o filtrar por familia y tocar **Test**.
   Incluye las 521 clases originales; Silence no vibra.
   La pulsera muestra **TEST / PATTERN TEST** y reproduce su ritmo sin guardar una
   detección en el dashboard. **Test vibration** sigue probando KNOCK: dos pulsos
   cortos. Detener la escucha antes de probar; no hace falta calibrar para esto.
5. Mantener el iPhone vertical en un soporte, con micrófonos libres y la app abierta.
6. Tocar **Start listening** y permitir micrófono. El reconocimiento empieza sin
   exigir calibración. Para intentar ubicar sonidos, tocar **Calibrate front** y
   mantener una fuente continua al frente unos segundos. Durante ese intento se
   pausa el reconocimiento. **Calibrate again** repite la referencia si se mueve
   el soporte; un fallo no impide seguir reconociendo categorías.
7. Probar sonidos desde izquierda, frente y derecha; confirmar evento, ángulo y
   vibración. La precisión física y los umbrales deben medirse en el aparato.

Si Bluetooth se apaga o la pulsera se desconecta, la captura se detiene. Reconectar
no reenvía alertas anteriores ni reinicia el micrófono solo. Si falta un permiso,
la app muestra el estado y acceso a Configuración. Al salir de la app también se
detiene; todavía no es escucha en segundo plano ni orientación desde el bolsillo.

## Pantalla y datos recientes

Toda la interfaz está en inglés. Usa la foto, tipografías Gabarito/Atkinson,
paneles translúcidos y acento lima de la landing FortWatch indicada por el usuario.
Las fuentes y la foto están incluidas en la app, sin descargarlas al escuchar.
El panel Orbit destaca el nombre del sonido, un círculo grande con creciente lima
y el lado escrito debajo. El teléfono del centro es la referencia; el ícono del
sonido se ubica en el círculo cuando hay una dirección válida.
Sin medición válida aparece **Direction unavailable**, sin inventar una dirección. Una alerta usa su propio ángulo; entre alertas se muestra
la dirección dominante reciente con un ícono genérico. Una alerta incierta no
toma prestado otro ángulo. Los datos vencidos se retiran; **Latest alert** es
historial, no una ubicación en vivo. La última detección queda como **RECENT SOUND**,
con tiempo relativo y estado de envío, incluso al detenerse o recalibrar. No hereda
la dirección de un sonido posterior y se borra al iniciar una nueva escucha.

## Reconocimiento local

Usa el modelo YAMNet completo convertido a Core ML, incluida su preparación de
onda, espectrograma y bandas mel. Recibe 15.600 muestras mono a 16 kHz (975 ms),
produce 521 scores y avanza cada 480 ms. Se remuestrea solamente **W**; los cuatro
canales originales se conservan para medir la dirección de esa misma ventana.
La inferencia usa una sola tarea; si queda ocupada, se elige la última ventana
completa en lugar de acumular audio retrasado. El límite de frescura sigue siendo
750 ms desde el fin de la captura, sin renovarlo después de predecir.

El catálogo conserva los nombres originales y los agrupa visualmente en People,
Animals, Nature, Vehicles, Home, Music, Devices & machines y Other sounds. Cada
clase mantiene su ID Y000…Y520 y nombre concreto. Una subclase que supera el filtro
reemplaza a sus ancestros genéricos: Meow en lugar de Meow, Cat y Animal por separado.
Esto no separa fuentes simultáneas. Silence no genera alerta automática.

Las clases con equivalencia a los diez avisos anteriores conservan esos ritmos y
umbrales de partida; las demás usan el ritmo de su familia, score mínimo 0.60 y
al menos dos de tres ventanas para vibrar. La pantalla se actualiza con cada
resultado actual aunque la vibración espere confirmación o esté en pausa. Las
pausas se aplican después de elegir, para no promover una conjetura secundaria. Los nuevos
umbrales son provisionales: vocabulario completo no significa precisión perfecta.

Ver [implementación, pruebas y límites de las 521 clases](../docs/SOUND-CATALOG-521.md).
La auditoría anterior de Apple permanece como evidencia histórica; ya no describe
el clasificador de producción.

## Dirección y límites

- El arco con ícono indica el sonido dominante respecto del frente calibrado del iPhone.
  No separa fuentes simultáneas ni identifica qué persona habla.
- Silencio, baja coherencia, sonido vertical/difuso o datos vencidos dan dirección
  incierta. No se muestran como `0°`.
- El ángulo enviado con una alerta se calcula sobre la misma ventana temporal del
  clasificador. Una fuente distinta puede dominar esa ventana; probar con una sola.
- Calibrar fija un cero; no valida los ejes físicos ni el signo izquierda/derecha.
- La referencia usa una ventana móvil de un segundo y verifica ambas mitades.
  Una caída breve no borra toda la muestra; silencio prolongado, poca actividad
  o cambios de dirección no producen una referencia. El umbral sigue en 0.60.
- La señal genérica en vivo usa 300 ms; cada alerta clasificada sigue usando
  su propia ventana exacta de 975 ms. No se intercambian sus ángulos.
- Solo se elige una categoría por ventana, con prioridad y umbrales. No es
  separación de varias fuentes ni reconocimiento garantizado de cualquier sonido.
- La vibración identifica el tipo de sonido con un ritmo aprendido. Un único motor
  no vibra físicamente de un lado u otro; la dirección aparece en pantalla.
- El firmware nuevo permite apagar SPEECH manteniendo la home o BOOT un segundo.
  La pulsera descarta esas alertas; el iPhone no recibe el estado del interruptor,
  por lo que "enviada" no implica que una alerta SPEECH se haya mostrado.
- La app no mantiene cola BLE: si el enlace está ocupado o el resultado caducó,
  descarta el envío. “Enviada” indica aceptación por CoreBluetooth; este firmware
  no confirma que el motor haya vibrado físicamente.
- El firmware conserva la tarjeta original y añade una flecha rellena y lado grande.
  Firmware anterior puede ignorar `P` o usar los ritmos anteriores: instalar ambas
  partes de esta revisión. No se flashea desde esta app.

## Código

| Archivo | Responsabilidad |
|---|---|
| `SpatialCapture.swift` | FOA, YAMNet local, continuidad, tiempo y memoria acotada |
| `YAMNetClassifier.swift` | Modelo Core ML, remuestreo y ventanas 975/480 ms |
| `YAMNetEventSelector.swift` | Selección entre 521 clases, ancestros, filtros y pausas |
| `SoundCatalog.swift` | Catálogo generado: 521 nombres, familias y estilos |
| `SpatialPCM.swift` | Lectura PCM preservando W,Y,Z,X |
| `SpatialDirection.swift` | Ángulo, calidad y calibración |
| `SoundEvents.swift` | Eventos, ventanas alineadas y selector Apple histórico para regresiones |
| `SoundIdentity.swift` | Catálogo visual único: nombre, significado, símbolo y colores |
| `SoundHaptics.swift` | Ritmos por familia, diez avisos heredados y contrato con firmware |
| `WristbandBluetooth.swift` | Servicio BLE existente, conexión, frescura y mensajes |
| `ListenerModel.swift` | Permisos, estados, parada, prueba de vibración y envío |
| `FortWatchListenerApp.swift` | Estilo fotográfico/glass de la marca y estados de escucha |

UUID servicio: `6b1a0001-5d1e-4c3b-9a7e-50554e445345`.
UUID escritura: `6b1a0002-5d1e-4c3b-9a7e-50554e445345`.
Se conserva `E,<evento>,<score>[,<ángulo>,<calidad>]`, `L,<nivel>` y
`T,<hora>,<fecha>`, con máximo 63 bytes por escritura.
`D,<evento>,<score>[,<ángulo>,<calidad>]` refresca la pantalla sin vibración,
contador ni analytics. Un descarte manual bloquea D hasta una nueva notificación E. `P,<evento>` prueba un ritmo
con un evento conocido exacto; no incrementa historial, contador ni analytics.

## Verificar software

```sh
xcodebuild -project FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
```

El proyecto se genera desde `project.yml` con XcodeGen. Si se regenera, conservar o
volver a seleccionar el equipo de firma personal. Los tests usan audio sintético:
no prueban precisión acústica, alcance BLE ni funcionamiento físico del motor.

Fuentes: [YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet),
[Core ML](https://developer.apple.com/documentation/coreml),
[captura espacial](https://developer.apple.com/documentation/avfoundation/capturing-spatial-audio-in-your-ios-app),
[CoreBluetooth](https://developer.apple.com/documentation/corebluetooth/transferring-data-between-bluetooth-low-energy-devices).

### Diagnóstico físico optativo

La prueba `testPhysicalSpatialCaptureProvidesValidAudio` se compila solo con
`FORTWATCH_CAPTURE_PROBE`, requiere un iPhone real y permiso de micrófono. Usa
`SpatialCapture`, espera 50 actualizaciones decodificadas y detiene la captura; no
guarda audio ni envía alertas. La versión anterior, con Apple SoundAnalysis, pasó en el iPhone 17 Pro.
La revisión YAMNet además exige que el diagnóstico confirme inferencias nuevas;
esa prueba de micrófono aún está pendiente. El modelo sí pasó por separado sus
pruebas de salidas y remuestreo en el iPhone.
No valida el signo ni la precisión angular. Para diagnosticar el inicio, la app
guarda solo el último estado/mensaje en `Documents/fortwatch-capture-status.json`,
sin muestras, eventos reconocidos ni identificadores.

`Documents/fortwatch-spatial-status.json` guarda como máximo una vez por segundo
el último resumen numérico de la señal y de la calibración: RMS, coherencia,
estabilidad, calidad y motivo de rechazo. No contiene audio ni transcripciones.
El archivo incluye `sampledAt` y `capturing`; al detener, conserva la última
medición y marca `capturing:false` con `stoppedAt`. Su presencia sola no indica
que la captura esté activa. La sesión configura automáticamente el audio para FOA;
mantiene la comprobación de micrófono integrado y layout de cuatro canales.

La prueba optativa `testPhysicalCalibrationReachesResultWithoutCaptureFailure`
ejercita el coste de calibrar en el teléfono y espera la parada real. Su PASS
incluye un rechazo deliberado: no demuestra una referencia frontal correcta.
Las estadísticas `calibrationAttemptSeconds`, `calibrationCandidateWindows`,
`calibrationAcceptedWindows`, `calibrationBestQuality` y
`calibrationRejectionReason` corresponden únicamente al intento y se conservan
tras timeout; no mezclan la escucha posterior con la calibración.

### Ritmos por sonido

| Sonido | Patrón |
|---|---|
| ALARM | Tres largos |
| CAR HORN | Dos largos |
| GLASS | Tres cortos |
| SHOUT | Largo · corto · largo |
| BABY | Corto · largo · corto |
| KNOCK | Dos cortos |
| DOORBELL | Largo · corto |
| PHONE | Dos cortos · pausa · dos cortos |
| DOG | Dos cortos · un largo |
| SPEECH | Un corto |

Los pulsos se ejecutan sin bloquear el bucle de la pulsera. La guía representa
sus duraciones y pausas. La prueba `python3 live_demo/tests/test_haptic_contract.py`
(desde la raíz) compila ambas tablas y exige que coincidan; esto no demuestra
que una persona pueda reconocer los diez ritmos sin entrenamiento.

### Diagnóstico de bandas optativo

`FORTWATCH_BAND_PROBE` habilita
`SpatialBandProbeTests/testPhysicalSpatialBandsProduceNumericReport`. Captura
8 segundos en RAM con el micrófono integrado, detiene la captura y compara
ventanas de 1 segundo sin filtro y en tres bandas. El primer segundo calienta
los filtros. Solo guarda métricas numéricas en `Documents/fortwatch-band-probe.json`;
no guarda audio. El ángulo crudo es diagnóstico, sin calibración ni validación
física. No cambia filtros ni umbrales de producción.
