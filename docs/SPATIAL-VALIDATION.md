# Validación de la integración espacial

Fecha: 24 de octubre de 2026 (America/Los_Angeles).
Rama: `codex/iphone-spatial-direction`.

La integración es experimental. La precisión angular, el enlace físico iPhone →
Mac → BLE y la vibración en muñeca **no están verificados con estos cambios**.

| Área | Resultado | Evidencia |
|---|---|---|
| Receptor/estimador Python | PASS | 15 tests: ángulos sintéticos, silencio/difusión, calibración, huecos, paquetes inválidos, HTTP local, vencimiento total y cola BLE |
| Parser de mensajes de la pulsera | PASS | Ejecutable C++ con AddressSanitizer, UndefinedBehaviorSanitizer y warnings como errores; legacy, opcionales, NaN/Inf/rangos, reinicio y límite de 63 bytes |
| Firmware ESP32-S3 | PASS | PlatformIO, dependencias fijadas por el proyecto; RAM 64,500 / 327,680 bytes, flash 2,953,525 / 6,553,600 bytes |
| Modelo YAMNet real | PASS | Cargó el modelo del repositorio, produjo 521 scores finitos y reconoció silencio sintético; 10 grupos de eventos válidos |
| App iPhone, compilación sin firma | PASS | Destino genérico iOS, SDK instalado 26.5; sin credenciales ni instalación en dispositivo |
| Pruebas iOS finales | PASS | 9 casos, 0 fallos: PCM, layout FOA, buffers sintéticos, contrato, destinos locales y ángulos inválidos |
| Captura FOA física / ejes / error angular | NOT RUN | Requiere iPhone real y posiciones conocidas |
| BLE, pantalla y motor físicos con esta versión | NOT RUN | No se flasheó la pulsera |

## Comandos de verificación

Desde la raíz:

```sh
.venv/bin/python -m unittest discover -s live_demo/tests -v
clang++ -std=c++11 -Wall -Wextra -Werror -fsanitize=address,undefined -g \
  live_demo/tests/test_alert_protocol.cpp -o /tmp/fortwatch-alert-protocol-tests
/tmp/fortwatch-alert-protocol-tests
uvx --from platformio pio run --project-dir live_demo/fortwatch_display
git diff --check
```

Para iOS, ver los comandos reproducibles en [ios/README.md](../ios/README.md).
También se invocó `load_yamnet()` desde el programa real con una ventana de 16,000
ceros Float32. Inferencia inicial: 0.097 s; segunda: 0.004 s. Son tiempos de esa
prueba, **no latencia sonido → pulsera**. No se usaron micrófono ni Bluetooth para
la prueba del modelo. Las dependencias se prepararon en la `.venv` local ignorada.

El build ESP32 usa el toolchain del proyecto y emite warnings de conversión en la
dependencia GFX Library for Arduino 1.5.0; terminó correctamente. No se modificó
esa dependencia.

## Revisión y límites

La revisión detectó y corrigió el envío de dirección caducada desde la cola BLE,
la suma accidental de presupuestos de red/inferencia, una carrera al reiniciar
la sesión de audio del iPhone y la caducidad tardía de la flecha en su interfaz.

Los tests del estimador usan señales generadas: no validan el procesamiento
acústico real de Apple. Una fuente dominante distinta de la clase reconocida puede
producir una flecha incorrecta para ese evento. La interfaz identifica la dirección
como la del sonido dominante; una demo inicial debe mantener una sola fuente.

## Próximas tres acciones físicas

1. El iPhone 17 Pro ya aparece conectado al finalizar la comprobación. Desbloquearlo
   y seleccionar el equipo de firma en Xcode para instalar la app.
2. Revisar y cargar el firmware de la pulsera conservando su cableado actual.
3. Calibrar con el teléfono vertical y fijo; medir ángulo, alerta y vibración con
   sonidos desde ocho posiciones siguiendo [la guía](SPATIAL-DIRECTION.md).
