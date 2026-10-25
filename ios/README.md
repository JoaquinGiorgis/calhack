# FortWatch Listener para iPhone

Captura audio espacial real en el iPhone y lo transmite por la red local al
receptor de la Mac. La Mac conserva YAMNet, calcula dirección sobre el mismo audio
y manda las alertas a la pulsera. La vibración existente sigue indicando la
prioridad; la pantalla de la pulsera añade una flecha y un ángulo relativo al
teléfono cuando la dirección es suficientemente coherente.

Esta app requiere iOS 26 y un dispositivo que declare soporte para First Order
Ambisonics (FOA), como iPhone 16 Pro o posterior. El simulador sirve para verificar
software e interfaz, **no** para probar los micrófonos ni la precisión angular.

## Ejecutar en el iPhone

1. Abrir `FortWatchListener.xcodeproj` en Xcode. El proyecto también se puede
   regenerar con `xcodegen generate` desde esta carpeta.
2. En Signing & Capabilities, elegir el equipo de desarrollo del usuario. No hay
   un equipo ni credenciales incorporados en el proyecto.
3. Conectar y desbloquear el iPhone, elegirlo como destino y ejecutar. El modo
   desarrollador y la autorización de confianza de Xcode deben estar habilitados.
4. En la Mac, desde la raíz del repositorio y con las dependencias instaladas:

   ```sh
   .venv/bin/python live_demo/mac_listener.py --spatial-listen 0.0.0.0:8766 --link ble
   ```

5. Usar la dirección privada de la Mac (por ejemplo `192.168.1.20:8766`) o su
   nombre `.local` y copiar el código que imprime el receptor. Ambos equipos deben
   compartir una red de confianza que permita tráfico entre ellos; algunas redes
   públicas de eventos aíslan los dispositivos.
6. Tocar **Iniciar captura** y permitir micrófono y red local. Mantener el iPhone
   vertical en un soporte fijo, sin cubrir sus micrófonos.
7. Colocar una única fuente de sonido frente al teléfono, tocar **Calibrar frente**
   y sostener ese sonido durante un segundo. Repetir si la app lo pide.
8. Probar sonidos a izquierda, frente y derecha. Confirmar la orientación real y
   medir el error antes de usar la dirección en la demo. Si se mueve el soporte,
   hay que volver a calibrar.

La app funciona en primer plano y se detiene al pasar a segundo plano, cambiar de
micrófono o recibir una interrupción. No es un modo de escucha desde el bolsillo.

## Estados y límites

- **Dirección incierta:** no se usa `0°` para disimular silencio, falta de
  calibración, baja calidad o datos vencidos.
- La flecha del iPhone corresponde al sonido dominante recibido por la Mac, no a
  un detector que separe fuentes simultáneas. Con conversación y alarma a la vez,
  debe validarse qué fuente domina antes de confiar en una dirección.
- La calibración fija el frente; no verifica por sí sola que los ejes físicos y
  el signo izquierda/derecha sean correctos. Esa comprobación requiere sonidos
  desde posiciones conocidas en el dispositivo real.
- La calidad de dirección es una medida heurística de coherencia. No es una
  probabilidad ni una garantía de precisión en grados.
- El audio no se guarda en esta app. Se transmite a la Mac por HTTP local con un
  token temporal; HTTP no cifra el audio. Usar una red de confianza. Se rechazan
  destinos públicos, URLs con credenciales y redirecciones.
- Si la red se retrasa, se descarta audio en lugar de acumularlo; la Mac invalida
  la continuidad y puede exigir recalibrar. Cada solicitud tiene un límite
  absoluto de 0,75 s desde su envío para mostrar una dirección. Recibir la
  respuesta no reinicia ese plazo; la interfaz revisa su caducidad cada 100 ms.
- La pulsera necesita el firmware extendido para mostrar ángulos; el firmware
  anterior puede seguir mostrando las alertas y vibrando.

## Contrato y archivos

- `SpatialCapture.swift`: captura `AVCaptureAudioDataOutput` en modo
  `.firstOrderAmbisonics`, exige cuatro canales ACN/SN3D, agrupa bloques de 100 ms
  y permite solo una solicitud de red pendiente.
- `BridgeProtocol.swift`: copia PCM planar o intercalado sin mezclar canales,
  convierte a Float32 little-endian y valida direcciones de red y respuestas.
- `ListenerModel.swift`: estados, calibración y caducidad de la dirección.
- `FortWatchListenerApp.swift`: controles accesibles y texto de estado; nunca
  muestra resultados sintéticos como audio en vivo.

Cada `POST /audio` lleva `Authorization: Bearer <código>` y un JSON con
`version`, `session`, `sequence`, `sample_rate`, `frames`, `pts`, `layout`,
`pcm_f32le` y `calibrate_front`. El orden de canales es **W,Y,Z,X**; `pts` es el
tiempo de presentación de la captura. La secuencia avanza también en bloques
descartados para que el receptor detecte huecos. Una sesión nueva empieza en cero.

## Verificar software

```sh
xcodegen generate
xcodebuild -project FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
```

Los tests usan buffers **sintéticos** para verificar orden de canales, PCM,
timestamp, contrato JSON, restricciones de conexión y rechazo de ángulos
inválidos. No prueban la precisión del hardware ni el enlace físico a la pulsera.

Fuentes de API: [captura espacial de Apple](https://developer.apple.com/documentation/avfoundation/capturing-spatial-audio-in-your-ios-app),
[layout espacial de la salida](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput/spatialaudiochannellayouttag).
