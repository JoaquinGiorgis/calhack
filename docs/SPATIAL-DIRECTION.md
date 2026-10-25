# Dirección del sonido: iPhone → Bluetooth → pulsera

La ruta actual funciona directamente desde el iPhone. La Mac se usa para compilar
e instalar la app; no participa durante la escucha.

```text
iPhone FOA → SoundAnalysis + ángulo en el iPhone → BLE → alerta, flecha y vibración
```

El ángulo corresponde al **sonido dominante respecto del teléfono**. El sistema
no separa fuentes: una conversación fuerte puede dominar la dirección aunque se
reconozca un golpe breve en otro lado. Esto también ocurre con sonidos sucesivos
dentro del mismo segundo. La primera prueba debe usar una sola fuente.

## Primera prueba

1. Instalar la [app iPhone](../ios/README.md), seleccionar el equipo de firma propio
   y ejecutar en un iPhone con FOA e iOS 26+. La app verifica el soporte real.
2. Encender la pulsera. Cerrar el receptor anterior de la Mac para liberar BLE.
   No hace falta que los dispositivos compartan Wi-Fi.
3. Tocar **Conectar pulsera** dentro de la app y permitir Bluetooth. Cuando figure
   conectada, tocar **Probar vibración**: KNOCK y dos pulsos cortos. Confirmar en la
   pulsera; la app no tiene confirmación física del motor.
4. Tocar **Iniciar escucha**, permitir micrófono y mantener la app abierta. Dejar
   el iPhone vertical en un soporte fijo con los micrófonos descubiertos.
5. Tocar **Calibrar frente** y producir un sonido claro y estable desde el frente
   elegido durante al menos un segundo. Silencio/ruido difuso no fijan un cero.
6. Probar alertas desde izquierda, frente, derecha y atrás. Verificar nombre,
   flecha y vibración. Si se mueve el soporte, volver a calibrar.

El firmware extendido muestra ángulos; el anterior puede mostrar alertas y vibrar
sin flecha. No se flashea automáticamente. Interrupciones, gaps y sesiones nuevas
borran calibración. Una desconexión detiene escucha y no reenvía alertas antiguas.
No hay seguimiento del teléfono respecto del cuerpo ni escucha en segundo plano.

## Vibración y protocolo

Se conserva el único motor/circuito de GPIO17 y sus patrones por prioridad:
seguridad (tres largos), atención (dos cortos), baja (uno corto). Una alerta genera
una secuencia. El motor único no produce una sensación localizada por lado.

`E,KNOCK,0.62` significa evento con dirección desconocida.
`E,KNOCK,0.62,-35,0.81` agrega ángulo y calidad espacial. Ángulo −180…180°,
positivo derecha, negativo izquierda, cero frente. Calidad 0…1 es coherencia
heurística, **no probabilidad de acierto**; flecha solo con calidad ≥0.60.
Máximo 63 bytes por mensaje. Dirección inválida no suprime un evento válido ni
reutiliza la dirección anterior. En pantalla se indica que es del sonido dominante.

## Captura y cálculo

FOA son componentes procesadas ACN/SN3D **W,Y,Z,X**, no cuatro cápsulas crudas.
W alimenta SoundAnalysis como mono. Productos W×X/Y/Z forman el vector de
intensidad; `atan2` da el azimut relativo al cero calibrado. Nivel, coherencia,
componente horizontal y estabilidad determinan cuándo devolver incertidumbre.

El ángulo enviado con cada alerta usa exactamente la ventana temporal devuelta
por el clasificador (un segundo, solapamiento 50%). La flecha de escucha puede
actualizarse con bloques más recientes y no se reutiliza como ángulo de una alerta
vieja. El límite de 0.75 s parte del final de captura y vuelve a comprobarse antes
del envío BLE. La memoria se limita a cuatro segundos FOA y un lote pendiente de
hasta 500 ms; el audio no se escribe a disco ni se transmite fuera del teléfono.

Los umbrales Apple son provisionales y están en `SoundEvents.swift`. Las métricas
anteriores ESC-50 corresponden a YAMNet en la Mac, no al nuevo clasificador.

## Validación física pendiente

Registrar diez intentos en ocho posiciones separadas por 45°, primero una fuente,
después conversación de fondo. Medir ángulo real/estimado, error circular,
incertidumbres, evento, latencia y vibración; repetir a distintas distancias.
Contar también los resultados inciertos. Pruebas sintéticas/compilaciones no
demuestran precisión acústica, entrega BLE ni funcionamiento físico del motor.

## Fuentes

- [Apple: captura espacial y buffers en tiempo real](https://developer.apple.com/videos/play/wwdc2025/251/).
- [Apple: ejemplo FOA](https://developer.apple.com/documentation/avfoundation/capturing-spatial-audio-in-your-ios-app).
- [Apple: layout de canales](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput/spatialaudiochannellayouttag).
- [Zotter y Frank: análisis direccional](https://link.springer.com/chapter/10.1007/978-3-030-17207-7_5).
- [ambiX: ACN/SN3D](https://ambisonics-symposium.org/Members/zotter/copy_of_publications/publications/2011_NachbarZotterSontacchiDeleflie_ambix.pdf).
