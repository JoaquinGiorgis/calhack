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
