# FortWatch — actualización de diseño y dispositivos

25 de octubre de 2026. Rama `codex/iphone-spatial-direction`, sobre el merge
`1ae20eb` con `main` hasta `88aebcb`. No se publicó la rama.

## Cambios

- App SwiftUI en inglés: fondo carbón, texto blanco grande, colores originales
  por sonido, arco afilado, retículo del teléfono e ícono de categoría.
- La categoría usa el ángulo de su propia ventana de audio. Una alerta incierta
  no toma el ángulo de otra ventana. Al vencer, se retira la categoría del indicador;
  puede quedar una señal genérica de dirección reciente. `Latest alert` es historial.
- Pulsera: misma paleta por categoría, título grande, arco e ícono, prioridad,
  patrón de vibración y dirección capturada respecto del iPhone. Conserva home,
  reloj/nivel, touch/BOOT, SPEECH persistente, BLE y subida Wi-Fi al dashboard.
- Un motor sigue indicando prioridad, no izquierda/derecha física. La dirección
  sigue siendo dominante; no separa varios sonidos. Comando de voz “Fortnite”
  y escucha en segundo plano siguen pendientes.

## Verificación

| Comprobación | Resultado y alcance |
|---|---|
| Tests iOS | PASS: 28 pruebas, 0 fallos; incluye categoría/ángulo de la misma ventana y caducidad |
| Simulador iPhone 17 Pro / iOS 26.5 | PASS: build y pantalla inicial; tamaño normal y accesibilidad máximo |
| iPhone físico / iOS 26.6.1 | PASS: build firmado localmente, instalación y apertura |
| Dibujo de pulsera en host | PASS: 3,641 renders de helpers reales con ASan/UBSan; diez eventos, todos los grados y estados inciertos; no demuestra pantalla física |
| Firmware sin analytics | PASS: compilación inicial |
| Firmware final con configuración recuperada | PASS: RAM 84,116 B, flash 3,622,209 B |
| Carga de pulsera | PASS: app0 escrita y hash verificado; NVS/particiones no reescritas |
| Captura espacial en iPhone físico | PASS: prueba optativa sobre SpatialCapture recibe un bloque decodificado de cuatro canales; 1 prueba, 0 fallos |
| Signo y precisión angular | NOT VERIFIED: requiere sonidos reales con el teléfono fijo |
| iPhone → BLE → pantalla/motor | PASS por confirmación del usuario: Connect + Test vibration muestra KNOCK nuevo y da dos pulsos |
| Subida real al dashboard | BLOCKED: configuración conservada, pero serial informa que no hay una red conocida disponible |

Evidencia local de builds/tests/instalación: `/tmp/fortwatch-design-update/`.
El respaldo completo de 16 MB del firmware anterior y su configuración quedan en
una carpeta privada local, fuera de Git. La tabla de particiones coincide con la
compilación nueva. Se recuperaron las tres redes Wi-Fi, URL y clave existentes en
`secrets.h`, ignorado por Git y con permisos 0600; no se imprimieron sus valores.
La firma personal de Xcode se conserva localmente y no se incluye en el commit.

## Corrección durante la prueba física

El usuario confirmó BLE/pantalla/motor, pero encontró Calibrate front desactivado.
La prueba física de captura sí arrancó correctamente (0.326 s hasta completar).
Se unieron inicio y calibración en **Listen & calibrate**, se movió el estado arriba
y se añadió un diagnóstico local del último inicio/parada sin audio. Los 28 tests
base volvieron a pasar y se reinstaló la versión actualizada.

## Probar el circuito real

1. En FortWatch, **Connect** → **Test vibration**. Confirmar KNOCK en pantalla y
   dos pulsos cortos. El botón informa el envío, no una confirmación del motor.
2. **Listen & calibrate** con un sonido continuo al frente durante un segundo.
   Mantener el iPhone vertical, fijo y con micrófonos libres. El botón inicia
   el micrófono y luego calibra; no exige activar primero otro control.
3. Probar una fuente a izquierda, frente y derecha. Confirmar categoría y lado
   en iPhone/pulsera y observar el dashboard. Repetir con ruido/mezclas después:
   una fuente dominante puede desviar la dirección atribuida a la ventana.

## Vista previa del firmware

Render de software de las funciones de dibujo reales con datos sintéticos para
revisar distribución; **no es una captura de la pulsera ni una medición acústica**.

![Diseño de alertas y dirección](design/directional-alert-preview.png)

## Seguimiento: dirección ausente en ambas pantallas

El usuario aclaró que no veía dirección ni en iPhone ni en pulsera. No se considera
validado el ángulo físico. Se encontró que el mensaje de calibración fallida duraba
solo hasta la siguiente actualización de audio y se reemplazaba por Listening.

La siguiente revisión conserva el fallo visible, muestra una guía circular neutral
sin inventar ángulo, compacta la pantalla durante captura y agrega un resumen
numérico local de RMS/coherencia/estabilidad/motivo de rechazo. No contiene audio
ni transcripciones ni eventos reconocidos. Los umbrales y la fórmula del ángulo
se conservan. La revisión final volvió a pasar los 30 tests de simulador
(`spatial-session-final-tests.xcresult`). Se verificó la pantalla inicial actual
en el simulador y se actualizó la captura de diseño.

La prueba física ampliada a 50 actualizaciones pasó después de desbloquear el
iPhone. Con la configuración manual `.record/.default`, las 44 ventanas del
último resumen dieron coherencia, estabilidad y calidad cero. Esto no demuestra
que los canales XYZ estuvieran vacíos: esa primera prueba no medía su RMS.

Se pasó a la configuración automática de audio de `AVCaptureSession`, como en
el ejemplo oficial de Apple. La misma prueba pasó y registró RMS direccional
0.0173 y calidad máxima 0.408; ninguna de las 44 ventanas superó 0.60 en ese
ambiente. El resumen final tenía coherencia 0.0752 y estabilidad 0.0985. Son
mediciones de señal, no una prueba de precisión angular ni de calibración.

La app normal actualizada compiló, se instaló y abrió en el iPhone. Se pidió
una prueba con una fuente continua al frente; calibración, signo y ángulo
físicos siguen sin validar. Se conserva el firmware y la configuración privada
del dashboard. No se cambiaron los umbrales ni los patrones de vibración.

Las lecturas posteriores de la app mostraron ventanas aceptadas de forma
intermitente (calidad máxima 0.760, 66/302 ventanas en el último resumen), pero
el estado final fue `calibrationFailed:true` / `calibration_timeout`. No se
confirmó todavía qué fuente ni posición se usaron; estos datos no validan el
montaje, el plano horizontal o el signo izquierda/derecha. La revisión del
diagnóstico agrega fecha de medición y marca de captura detenida para no
confundir una lectura guardada con una captura activa.

Evidencia local: `direction-diagnostic-retry.xcresult`,
`automatic-session-probe.xcresult`, `spatial-diagnostic.json`,
`spatial-automatic.json` y `spatial-input-fix-{build,install,launch}.log`,
todos bajo `/tmp/fortwatch-design-update/`.
