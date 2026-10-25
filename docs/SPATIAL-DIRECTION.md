# Dirección del sonido: iPhone → Mac → pulsera

La demo mono existente sigue disponible. La ruta espacial es opcional y conserva
YAMNet, sus umbrales, Bluetooth/USB y el motor actual.

```text
iPhone FOA → red local → Mac (YAMNet + ángulo) → BLE → alerta, flecha y vibración
```

El ángulo corresponde al **sonido dominante respecto del teléfono**. YAMNet no
separa fuentes: una conversación fuerte puede dominar la dirección aunque detecte
un golpe breve en otro lado. Esto también ocurre con sonidos sucesivos dentro
del mismo segundo. La demo inicial debe usar una sola fuente.

## Primera prueba

1. Instalar la [app iPhone](../ios/README.md) en un dispositivo compatible con FOA e
   iOS 26+. La app comprueba soporte y cuatro canales. Requiere conectar el teléfono
   y seleccionar el equipo de firma en Xcode; aún falta la prueba física.
2. Conectar iPhone y Mac a la misma red local de confianza. Este prototipo usa HTTP
   **sin cifrar**: el código autentica al emisor, no cifra el audio. No exponer el
   puerto a Internet. No se graba audio ni se sube a servicios externos.
3. Preparar las dependencias del README y ejecutar desde la raíz:

   ```bash
   .venv/bin/python live_demo/mac_listener.py --spatial-listen 0.0.0.0:8766 --analytics-url ''
   ```

   En la app introducir IP privada de la Mac y puerto `8766` (o nombre `.local`)
   y el código que imprime el programa. Para probar sin pulsera añadir
   `--no-serial`. Para usar cable añadir `--link usb --port /dev/cu.<puerto-real>`.
4. La pulsera requiere el firmware extendido para mostrar ángulos. El firmware
   antiguo sigue mostrando/vibrando pero ignora esos campos. Este cambio no
   instala ni flashea automáticamente los dispositivos.
5. Poner el iPhone **vertical en soporte fijo**, micrófonos descubiertos. Iniciar
   captura, permitir micrófono y red local, mantener app en primer plano.
6. Calibrar el frente produciendo un sonido continuo desde el frente elegido
   durante al menos un segundo. Necesita sonido claro y estable; silencio o ruido
   difuso no fijan un cero. Si cambia la orientación, volver a calibrar.
7. Probar una alerta reconocida desde izquierda, frente, derecha y atrás. Verificar
   nombre, flecha y vibración. Si el signo o plano son incorrectos, revisar primero
   la orientación física; un medidor que se mueve no valida el ángulo.

Interrupciones, gaps y nuevas sesiones borran calibración. No se acumula audio
para enviarlo después. No hay seguimiento de la orientación del teléfono respecto
del cuerpo o la muñeca.

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
W alimenta YAMNet como mono a 16 kHz. Productos W×X/Y/Z forman el vector de
intensidad; `atan2` da el azimut relativo al cero calibrado. Nivel, coherencia,
componente horizontal y estabilidad determinan cuándo devolver incertidumbre.
Clasificación y dirección comparten una ventana de un segundo. Los resultados
vencidos se descartan incluso después de esperar en la cola BLE: presupuesto de
0.75 s desde el final estimado de captura para red, inferencia y envío.

`POST /audio`, JSON, `Authorization: Bearer <código>`. Campos: `version:1`,
`session` (UUID), `sequence` (desde 0), `sample_rate`, `frames`, `pts` (tiempo
monotónico del audio), `layout:"ACN_SN3D"`, `pcm_f32le` (base64 Float32 LE
entrelazado W,Y,Z,X), `calibrate_front` (booleano). Bloques ~100 ms, máximo 250 ms,
un envío en curso. Respuesta: `accepted`, `calibrated`, `calibrating`, `angle_deg`,
`direction_quality`, `reason`, `wristband_connected`. Un ángulo null es desconocido.

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
