# Validación: iPhone directo a pulsera

Fecha: 24 de octubre de 2026 (America/Los_Angeles).
Rama: `codex/iphone-spatial-direction`.

Este pase es histórico. El [estado del 25/10](DIRECTION-DESIGN-UPDATE.md) añade
28 tests, prueba FOA en el iPhone, diseño circular e instalación en ambos dispositivos;
el usuario confirma conexión BLE, pantalla KNOCK y vibración.

La app actual reconoce y calcula dirección en el iPhone, luego envía alertas
por BLE. Se eliminó la dependencia de Mac/HTTP, los campos IP/código, los tipos de
transporte y el permiso de red local. Bluetooth y micrófono se solicitan al usarlos.
El receptor Mac anterior fue detenido para que no compita por la pulsera.

| Área | Resultado | Evidencia |
|---|---|---|
| Build real iPhone | PASS | SDK 26.5, destino iPhone 17 Pro conectado, firma local existente |
| Tests iOS | PASS | 26 tests, 0 fallos, simulador iPhone 17 Pro/iOS 26.5 |
| PCM espacial | PASS | 4 tests: W/Y/Z/X, planar/interleaved, enteros, buffer CMSampleBuffer y rechazo mono/NaN |
| Ángulo/calibración | PASS | 8 tests sintéticos: ángulos, referencia, silencio/difusión/vertical, inestabilidad, calibración y timeout |
| Clasificador/eventos/ventanas | PASS | 8 tests: etiquetas reales del modelo Apple, mapeo, prioridad, pausas, orden, ring de 4 s y alineación exacta |
| Protocolo BLE | PASS | 6 tests: UUID reales, mensajes golden, números/rangos, 63 bytes y caducidad absoluta |
| Parser firmware | PASS | C++ con AddressSanitizer/UndefinedBehaviorSanitizer: mensajes legacy, dirección, incertidumbre, valores inválidos y límite de 63 bytes |
| Modelo Apple real | PASS de ejecución | `.version1`: 303 etiquetas; stream sintético en Mac produjo ventanas de 1 s cada 0.5 s. No valida precisión en iPhone |
| Interfaz | PASS visual | Pantalla inicial del simulador con conexión directa, sin IP/código. Captura en `docs/design/ios/listener.png` |
| Instalación física | PASS | CoreDevice confirmó instalación de `dev.fortwatch.spatiallistener` en el iPhone conectado |
| Apertura automática | BLOCKED | El iPhone se bloqueó; CoreDevice rechazó launch con `Locked`. Abrir FortWatch manualmente |
| Captura FOA/ejes/precisión física | NOT RUN | Requiere prueba con sonidos desde posiciones conocidas |
| BLE/pantalla/motor físicos desde iPhone | PENDING | Solicitado al usuario conectar y tocar Probar vibración; falta confirmación |

## Comprobaciones realizadas

```sh
xcodebuild -project ios/FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/FortWatchListener.xcodeproj -scheme FortWatchListener \
  -destination 'id=<iPhone conectado>' build
git diff --check
```

Evidencia local de este pase:
`/tmp/fortwatch-ios-direct-tests-v2.xcresult`,
`/tmp/fortwatch-ios-direct-tests.log`,
`/tmp/fortwatch-ios-direct-device.log`,
`/tmp/fortwatch-direct-install.json` y `/tmp/fortwatch-direct-launch.json`.
No se cambiaron credenciales ni se flasheó firmware.

La revisión independiente comprobó estados del modelo/UI, sesión BLE, permisos,
stop/desconexión, generaciones, reloj de captura, ring y ventana de clasificación.
Se corrigieron un reset excesivo del clasificador bajo carga, la comprobación de
frecuencia durante preparación y errores de compilación de la API Swift.
El modelo Apple fue ejecutado además con audio sintético en macOS: 11 resultados,
ventanas `[0,1]`, `[0.5,1.5]`…; sin micrófono ni archivos de audio personales.

## Límites que siguen pendientes

Los umbrales Apple son provisionales. Las métricas anteriores ESC-50 de YAMNet no
se transfieren a este modelo. Faltan falsos positivos, tasa de detección, latencia
y precisión angular medidos en el iPhone real. El ángulo es del sonido dominante;
puede corresponder a otra fuente que coexista con el evento clasificado.

El presupuesto de 0.75 s parte del final de captura; se revalida antes de BLE. No hay
cola de envío. Una detección consume su pausa de 2 s (voz 15 s) aunque el transporte
esté ocupado; la UI indica si no se pudo enviar. Que CoreBluetooth acepte el envío
no confirma físicamente el motor. La escucha requiere primer plano.

## Próximas tres acciones físicas

1. Abrir FortWatch y conectar la pulsera dentro de la app; permitir Bluetooth.
2. Tocar **Probar vibración** y confirmar KNOCK más dos pulsos cortos.
3. Iniciar escucha, permitir micrófono, calibrar frente y medir con sonidos desde
   posiciones conocidas siguiendo [la guía](SPATIAL-DIRECTION.md).
