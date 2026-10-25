# FortWatch en el celular (sin Mac)

Misma lógica que `mac_listener.py` (YAMNet, mismos umbrales, prioridades y mensajes `L,` / `E,` / `T,`), pero corriendo en el navegador del celular. El audio no sale del celular. La pulsera no cambia: recibe los mismos mensajes por la misma característica BLE.

## Requisitos
- **Android:** Chrome. **iPhone:** Safari no tiene Web Bluetooth; usar el navegador **Bluefy**.
- La página tiene que servirse por **HTTPS** (Web Bluetooth lo exige), por ejemplo GitHub Pages o Vercel. Para probar en la compu: `python3 -m http.server` dentro de esta carpeta y abrir `http://localhost:8000`.
- Todo está incluido (`tf.min.js`, `model/`), no necesita internet una vez cargada.

## Uso
1. Abrir la página. Esperar "YAMNet listo" en el registro.
2. "Conectar pulsera" y elegir `FortWatch`.
3. "Empezar a escuchar" y permitir el micrófono. Mantener la pantalla encendida.
4. "Enviar alerta de prueba" comprueba solo el enlace Bluetooth.

## Qué está verificado y qué no
- Verificado: el modelo carga en Chromium y clasifica un tono (Beep 0,92) y ruido (White noise 0,54).
- **No verificado:** Web Bluetooth con la pulsera real, el micrófono en un celular real, la comparación de puntajes contra la versión de Python con sonidos reales, la latencia y el consumo. Los umbrales se calibraron con TensorFlow en Python; hay que revisarlos con esta versión.
