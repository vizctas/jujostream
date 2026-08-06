# JUJOSTREAM: estabilización de streaming y dos DualSense

Fecha: 2026-08-06  
Alcance: Chromecast HD, Fire TV, TEKKEN 8, dos DualSense, decoder Android y feedback de controles.  
Paquete: `com.vizcorp.moonlight_jujo_stream` (`1.1.22+23`).

## Resultado

El crash reproducible con dos controles no era un crash de TEKKEN, del encoder ni de `MediaCodec`. Android terminaba el UID de JUJOSTREAM porque el cliente abría una `LightsSession` nueva por cada paquete RGB del control y nunca la cerraba. Cada sesión conserva un token Binder. Con dos DualSense, el proceso alcanzaba el límite de proxies Binder de Android y el sistema lo mataba.

El fix instalado:

- conserva una sola sesión de luces por dispositivo físico;
- coalesce actualizaciones RGB y limita su aplicación a 30 Hz;
- cierra las sesiones al desconectar un control, redetectar, terminar o limpiar el stream;
- evita enviar rumble a Dart cuando ya fue procesado nativamente;
- elimina detecciones y llegadas triples de los mismos controles al iniciar;
- corrige las métricas para que SPS/PPS/VPS no se contabilicen como frames recibidos;
- contabiliza como drop un frame de imagen realmente rechazado por el decoder.

Una prueba real de TEKKEN 8 con dos DualSense duró 4 minutos y 21 segundos, frente a las terminaciones anteriores a los 36–72 segundos. Llegó a 13.200 frames recibidos, 13.196 renderizados y 2 drops reales (0,015 %), sin `renderStalled`, sin falta de buffer de entrada, sin Binder kill y sin un nuevo `ApplicationExitInfo`.

## Evidencia anterior al fix

### Kill confirmado por Android

`ApplicationExitInfo` del Chromecast registró cinco terminaciones equivalentes:

```text
reason=13 (OTHER KILLS BY SYSTEM)
subreason=11 (KILL UID)
description=Too many Binders sent to SYSTEM
```

Tiempos observados:

- 2026-08-05 23:37:30
- 2026-08-05 23:38:46
- 2026-08-05 23:41:23
- 2026-08-05 23:47:08
- 2026-08-06 00:12:33

El log del sistema confirmó además:

```text
ActivityManager: Uid 10022 sent too many Binders to uid 1000
```

No fue una inferencia basada únicamente en el código: el motivo de muerte, el UID receptor (`SYSTEM`) y el recurso Android usado por JUJOSTREAM coinciden.

### Correlación con dos controles

La cronología previa mostró:

| Escenario | Resultado |
|---|---|
| TEKKEN 8 + 1 DualSense | ~173 s y fin normal |
| TEKKEN 8 + 2 DualSense | kill a ~36 s |
| TEKKEN 8 + 2 DualSense | kills posteriores a ~39, ~60 y ~72 s |
| Desktop + 1 DualSense, luego segundo control | kill ~40 s después del segundo control |

El último caso descarta que TEKKEN sea la causa exclusiva. TEKKEN genera suficiente feedback para exponer rápidamente el defecto, pero el fallo pertenecía al ciclo de vida de feedback Android.

### Decoder antes del kill

Inmediatamente antes de varias muertes, `framesReceived` y `framesRendered` seguían avanzando. Ejemplo observado: aproximadamente 4.500 recibidos, 4.480 presentados, 2 drops explícitos y 18 ms de decode. No hubo `renderStalled` antes del kill Binder.

Eso descartó cambiar a ciegas codec, Surface, bitrate o frame pacing como supuesta solución del crash.

## Flujo completo trazado

```text
DualSense 0/1
  -> Android InputDevice / GamepadHandler
  -> JNI StreamingBridge / Moonlight common C
  -> stream de control hacia Jujo.StreamServer
  -> Sunshine input::gamepad
  -> ViGEm: dos DualShock 4 virtuales
  -> callback DS4 de rumble y RGB
  -> stream de control de regreso al cliente
  -> StreamingPlugin.onRumble / onSetControllerLED
  -> GamepadHandler: vibrator y LightsManager
```

En el servidor, ambos controles llegaron correctamente y se crearon como dos DS4 virtuales:

```text
Gamepad 0 detected as DualSense (PS5); emulating as DualShock 4
Gamepad 1 detected as DualSense (PS5); emulating as DualShock 4
```

El servidor ya deduplicaba valores idénticos de rumble/LED. El defecto restante estaba después de esa deduplicación: cada actualización RGB válida todavía abría una sesión Binder Android nueva.

## Causa raíz primaria

Código anterior, de forma equivalente:

```kotlin
val session = lightsManager.openSession()
session.requestLights(request)
// no close(), no reutilización
```

La fuente oficial del SDK Android 36.1 documenta que `LightsSession` define la vida de una solicitud, implementa `AutoCloseable` y crea un `Binder` propio por sesión. Por tanto, no cerrar ni reutilizar sesiones acumula tokens Binder en `SYSTEM`.

Cadena causal confirmada:

```text
dos DS4 virtuales
  -> feedback RGB frecuente
  -> openSession() por paquete
  -> token Binder retenido por sesión
  -> límite de Binder proxies del UID
  -> ActivityManager mata todo JUJOSTREAM
```

## Cambios implementados en esta intervención

### 1. Ciclo de vida seguro de luces

Archivo: `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/GamepadHandler.kt`

- Se agregó un mapa de sesiones por `deviceId`.
- La primera actualización abre una sesión; las posteriores reutilizan la misma.
- Sólo se selecciona un nodo `InputDevice` que exponga una luz RGB real.
- Una sesión fallida se elimina y cierra antes de permitir recuperación.
- Se cierran sesiones y callbacks pendientes en:
  - fin de stream;
  - cleanup nativo;
  - redetección;
  - desconexión/hot-plug del dispositivo.
- Se añadieron contadores de callbacks, solicitudes aplicadas y sesiones vivas para validar el comportamiento sin loguear cada paquete.

Invariante nueva:

```text
sesiones Binder vivas <= controles físicos con luz RGB
```

### 2. Coalescing RGB a 30 Hz

Archivos:

- `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/ControllerLedThrottle.kt`
- `android/app/src/test/kotlin/com/limelight/jujostream/native_bridge/ControllerLedThrottleTest.kt`

La política:

- conserva siempre el color más reciente;
- crea como máximo una tarea pendiente por dispositivo;
- ignora duplicados del color ya aplicado;
- limita llamadas Binder útiles a una cada 33 ms por control;
- mantiene estado independiente por control;
- elimina todo el estado al cerrar la sesión.

### 3. Rumble deja de atravesar Dart inútilmente

Archivo: `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/StreamingPlugin.kt`

El rumble se aplica en Android mediante `GamepadHandler`. Antes, cada paquete también se emitía por `EventChannel` como `type=rumble`. Dart no tenía un caso `rumble`; el evento caía en la ruta genérica de estadísticas, activando innecesariamente parsing de HUD, métricas de sesión, telemetría y evaluación de bitrate dinámico.

Se eliminó únicamente ese segundo envío. El rumble físico nativo se conserva.

La ruta Binder nativa de vibración también fue auditada contra la fuente del
SDK Android 36.1. `InputDevice` conserva en caché su `VibratorManager`; a su
vez, el manager y cada `InputDeviceVibrator` crean un token una sola vez y lo
reutilizan en llamadas posteriores. No reproduce el patrón de fuga de
`LightsSession`, por lo que no se deshabilitó ni se limitó el haptic feedback
requerido por el juego.

### 4. Una detección y un anuncio por control

Archivos:

- `lib/screens/game/game_stream_screen.dart`
- `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/GamepadHandler.kt`

Antes del ajuste final, el arranque hacía:

1. `setStreamingActive(true)` y detección;
2. `setInputPreferences()` y otra detección;
3. `redetectControllers()` incondicional y una tercera detección.

Esto produjo tres secuencias de llegada para dos controles y seis avisos `ControllerNumber already allocated` en el servidor.

Ahora:

- se aplican preferencias/capacidades antes de activar el bridge;
- `setStreamingActive(true)` es la detección autoritativa única;
- se eliminó la redetección incondicional posterior;
- `setInputPreferences()` sólo redetecta durante un stream si una preferencia de topología cambió realmente;
- hot-plug sigue cubierto por `InputDeviceListener`;
- los reconnects vuelven a ejecutar el arranque completo.

Además de reducir trabajo, esto garantiza que la primera llegada ya anuncie las capacidades configuradas, no valores anteriores.

### 5. Métricas de decoder corregidas

Archivo: `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/VideoDecoderRenderer.kt`

- `totalFramesReceived` sólo incrementa para `BUFFER_TYPE_PICDATA`.
- SPS, PPS y VPS dejan de inflar la diferencia recibido/renderizado.
- Un frame de imagen rechazado por recuperación, decoder no disponible, CSD incompleto, falta de input buffer, buffer nulo o estado ilegal incrementa `totalFramesDropped`.
- El log periódico se ejecuta sólo para datos de imagen, evitando líneas `recv=0` al recibir CSD.

No se alteraron en este cambio el codec, la cola, el Surface, el frame pacing ni la presentación. Los datos reales no justificaban ese riesgo.

## Trabajo restaurado/preexistente que se preservó

El árbol ya contenía cambios restaurados por la otra AI, incluyendo trabajo de certificados/pairing y fixes de streaming anteriores. Esta intervención no los revirtió ni reemplazó. El worktree seguía teniendo 44 archivos modificados además de archivos nuevos; se trabajó de forma aditiva sobre los puntos implicados.

Los fixes de streaming restaurados y verificados en el estado integrado incluyen:

- política H.264 para dispositivos débiles;
- política de operating rate diferenciada: Amlogic usa la tasa real del stream y Fire TV/MediaTek conserva su ruta medida;
- `StreamStatsGuard` para drenar llamadas nativas antes de destruir el stream;
- cierre del polling de estadísticas en stop, terminación y cleanup;
- recuperación/watchdog de Amlogic conservada;
- no forzar automáticamente Direct Submit en todo Android TV; Chromecast mantiene la ruta texture que sí presenta frames;
- corrección de registro de motion sensors para evitar ciclos accel/gyro;
- no anunciar motion en TV cuando no puede entregarse de forma segura;
- pausa del polling TLS del launcher durante el stream;
- soporte de hasta ocho gamepads en el bridge y UI.

Estos puntos aparecen en el mismo APK final junto con las correcciones nuevas.

## Pruebas automatizadas

### Android/JVM

Comando ejecutado con JDK 21 de Android Studio:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
cd android
.\gradlew.bat :app:testDebugUnitTest `
  --tests "com.limelight.jujostream.native_bridge.ControllerLedThrottleTest" `
  --tests "com.limelight.jujostream.native_bridge.StreamStatsGuardTest" `
  --tests "com.limelight.jujostream.native_bridge.WeakDeviceDecoderPolicyTest"
```

Resultado: `BUILD SUCCESSFUL`.

Casos nuevos del throttle:

- primer color inmediato;
- ráfaga conserva el último color y programa una sola entrega;
- intervalo mínimo de 33 ms;
- color ya aplicado ignorado;
- independencia y limpieza por dispositivo.

### Flutter

```powershell
flutter test
```

Resultado: 171 tests, todos aprobados.

### Integridad del diff

```powershell
git diff --check
```

Resultado: sin errores de whitespace. Sólo se reportaron advertencias existentes de conversión LF/CRLF.

## Build e instalación

Build final:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
flutter build apk --release
```

Artefacto:

```text
build/app/outputs/flutter-apk/app-release.apk
size:    102112130 bytes
SHA-256: E780612ED0F2405AA342728C7701A9F57DEEA71B0757AE247537AA6D556D958C
firma:   APK Signature Scheme v2 verificada
version: 1.1.22+23
```

Instalación in-place (`adb install -r`) confirmada con `Success` en:

| Dispositivo | Serial ADB | Android | Resultado |
|---|---|---:|---|
| Fire TV AFTKRT | `192.168.3.137:5555` | 11 | instalado y proceso lanzado |
| Chromecast HD | `adb-27201HFGN1QWGB-S7HBwA._adb-tls-connect._tcp` | 14 | instalado y proceso lanzado |

La actualización in-place conserva ajustes y emparejamientos.

## Validación real

### Chromecast HD + TEKKEN 8 + dos DualSense

Ventana: 15:18:08–15:22:29.

- Chromecast detectó slots 0 y 1.
- Servidor creó gamepad 0 y 1 como DS4 virtuales.
- Duración: 4:21.
- Última muestra: 13.200 recibidos, 13.196 renderizados, 2 drops.
- Drop explícito: 0,015 %.
- Decode habitual: 18–22 ms.
- Picos transitorios observados: 30–37 ms, sin acumulación.
- Sin `No input buffer after ...`.
- Sin `renderStalled`.
- Sin `FATAL EXCEPTION` ni señal nativa fatal.
- Sin `Too many Binders sent to SYSTEM`.
- Sin nuevo `ApplicationExitInfo`.
- El stream terminó cuando el servidor detectó que TEKKEN ya no estaba ejecutándose, no por muerte del cliente.

Una segunda ejecución de 3:25 sobre el APK final confirmó los cambios añadidos
después de la prueba larga:

- una sola línea `Detected 2 gamepad(s)`;
- exactamente dos `ARRIVAL`, slots 0 y 1;
- dos DS4 creados por el servidor;
- cero `ControllerNumber already allocated`;
- la primera estadística válida fue `recv=300`, sin muestras `recv=0` causadas por CSD;
- última muestra: 11.100 recibidos, 11.095 renderizados, 3 drops y 20 ms;
- ningún exit nuevo; el primer `ApplicationExitInfo` sigue siendo únicamente `PACKAGE UPDATED` por la instalación ADB.

### Fire TV

- APK final instalado.
- Proceso iniciado correctamente.
- Captura logcat independiente activa.
- No se añadió un cambio específico de decoder a Fire TV: el perfil existente ya era estable y una modificación sin evidencia podía degradar su 8,5/10 actual.

## Logs conservados

Antes del fix:

```text
build/device-logs/chromecast-20260805-212450.log
build/device-logs/firetv-20260805-212450.log
```

Prueba larga con el fix crítico:

```text
build/device-logs/chromecast-fixed-20260806-151719.log
build/device-logs/firetv-fixed-20260806-151719.log
```

Capturas del APK final:

```text
build/device-logs/chromecast-final-20260806-152806.log
build/device-logs/firetv-final-20260806-152806.log
```

## Criterios anti-regresión

Una versión no debe promoverse si falla cualquiera de estos criterios:

1. Con dos DualSense, `liveSessions` nunca supera 2.
2. Un stream de 10 minutos no genera `Too many Binders`, `KILL UID`, ANR ni crash nativo.
3. Hay una sola secuencia `Detected 2 gamepad(s)` al inicio y cero `ControllerNumber already allocated` en el servidor.
4. `framesReceived` sólo cuenta imagen; CSD no cambia el contador.
5. `framesDropped` contabiliza tanto descarte de salida como rechazo real de entrada.
6. `framesRendered` continúa avanzando; si recibido avanza y renderizado se estanca, se investiga como wedge de decoder/surface.
7. Fire TV y Chromecast se prueban por separado: no se comparte una política de SoC sin evidencia.
8. Todo recurso Binder o callback de alta frecuencia debe tener propietario, límite de frecuencia y cierre explícito.

## Comandos de diagnóstico repetibles

```powershell
adb devices -l

adb -s <serial> logcat -c
adb -s <serial> logcat -v threadtime |
  Select-String 'GamepadHandler|VideoDecoder|StreamingPlugin|Too many Binders|FATAL EXCEPTION|Fatal signal'

adb -s <serial> shell dumpsys activity exit-info com.vizcorp.moonlight_jujo_stream

adb -s <serial> shell dumpsys input |
  Select-String 'DualSense|ControllerNumber|LIGHT' -Context 1,2
```

Señal de wedge de presentación:

```text
framesReceived sube + framesRendered se estanca
```

Señal de la regresión corregida en este incidente:

```text
ActivityManager: Uid ... sent too many Binders to uid 1000
ApplicationExitInfo: description=Too many Binders sent to SYSTEM
```

## Hallazgos independientes no atribuidos al crash

- El servidor registra errores periódicos de CloudAgent por refresh token reutilizado/JWT expirado. Son un problema de autenticación separado; no coincidieron causalmente con el kill Binder y no se modificaron aquí.
- Los errores NVENC durante el sondeo inicial están rodeados por el propio mensaje del servidor que indica ignorarlos; el encoder H.264 NVENC se creó correctamente para la sesión.
- Los avisos de motion no activo son coherentes con la política TV restaurada; no impiden que ambos controles funcionen como DS4.

Mantener estos hallazgos separados evita declarar como causa la primera advertencia visible y volver a introducir cambios especulativos en el pipeline de vídeo.
