# JUJOSTREAM streaming pipeline hardening

Fecha: 2026-08-17

## Resultado

Se reforzo el flujo completo servidor -> transporte -> Moonlight -> MediaCodec -> Surface y servidor -> Opus -> Oboe/AudioTrack. Los cambios corrigen fallos deterministas de ciclo de vida, negociacion, presentacion, audio, congestion y overflow sin cambiar a ciegas buffers, pacing, captura ni defaults que ya funcionan.

La validacion de compilacion y pruebas esta completa. La validacion fisica prolongada en FireTV, Chromecast y MiBox queda pendiente porque ADB no estuvo disponible durante esta entrega.

## Checkpoint y regreso seguro

Ambos repositorios tienen el tag anotado:

```text
checkpoint/pre-streaming-peak-20260817
```

- Cliente antes del hardening: `13f40094a65a12cf7d141b0fc5f665e8e0c853ca`
- Servidor antes del hardening: `38dbdac25902d40346d305df2ab10494190404e8`

Para inspeccionar o construir el estado anterior sin borrar trabajo:

```powershell
git switch -c recovery/pre-streaming-peak checkpoint/pre-streaming-peak-20260817
```

No se uso `reset --hard`, no se reescribio historia y cada bloque funcional quedo en un commit atomico reversible.

## Contratos aplicados

1. Solo puede existir una conexion Moonlight iniciando o activa.
2. Una sesion nueva espera el retorno real de `LiStartConnection()` y el teardown anterior.
3. La seleccion explicita anuncia un solo codec probado; `Auto` anuncia solamente decoders demostrados.
4. Dispositivos debiles mantienen H.264 incluso ante una seleccion incompatible.
5. Un frame cuenta como presentado solo cuando MediaCodec confirma su presentacion en Surface.
6. Destruccion de Surface o falta de progreso produce recuperacion local acotada y luego reconexion; nunca un stream vivo pero muerto.
7. El productor SPSC de audio nunca mueve el cursor del consumidor.
8. Solo una autoridad controla bitrate: ABR servidor o ABR cliente, nunca ambas.
9. Un overflow del encoder deja telemetria y solicita IDR para recuperar referencias.
10. Toda optimizacion nueva vive en componentes pequenos con contratos probables.

## Cambios del cliente

### Ciclo de vida nativo

- `NativeStreamLifecycle` modela `IDLE`, `STARTING`, `ACTIVE`, `INTERRUPTING` y `STOPPING`.
- `NativeStreamCoordinator` serializa start/interrupt/stop en un unico executor.
- Un timeout durante el handshake interrumpe el start bloqueante, espera su retorno y solo entonces limpia o inicia otra sesion.
- Si un start reporta exito despues de haber sido cancelado, se ejecuta stop nativo antes de volver a idle.
- PiP y cierre normal usan el mismo coordinador; se elimino el avance forzado de Dart tras cinco segundos.

### Negociacion de codec

- `CodecAdvertisementPolicy` separa capacidad probada, preferencia del usuario y mascara de protocolo.
- Seleccion explicita: anuncia exclusivamente el codec elegido si existe decoder valido.
- `Auto`: anuncia todos los codecs realmente probados.
- Politica de dispositivos debiles: H.264 como ruta segura.
- Fallback determinista: H.264; el codec finalmente negociado se registra en `onVideoSetup`.

### Decode, Surface y watchdog

- MediaCodec usa `OnFrameRenderedListener` para contar presentacion real, no solo liberacion del output buffer.
- `RenderProgressWatchdog` distingue arranque sin salida de un stall posterior.
- Primera deteccion: una recuperacion local del codec. Si no vuelve el progreso: evento `renderStalled` y reconexion serializada.
- El watchdog se rearma despues de progreso; evita tanto recuperaciones infinitas como un watchdog de un solo uso.
- DirectSubmit usa generaciones monotonicamente crecientes de Surface y notifica destruccion durante una sesion.
- El thread de Choreographer conserva su Looper, elimina callbacks y usa `quitSafely()` al cerrar.

### Audio de baja latencia

- `LockFreeRingBuffer` conserva el contrato SPSC: el productor rechaza el paquete completo al llenarse y nunca adelanta el read cursor.
- Cola Oboe dimensionada por el burst real: objetivo de 40 ms en salidas low-latency y minimo de dos bursts completos en salidas con bloques grandes.
- Metricas nativas: ocupacion de salida, paquetes rechazados y callbacks con underrun.
- Estado global de metricas atomico para evitar carreras JNI durante destruccion del renderer.
- Reapertura Oboe protegida y segura ante error de stream.
- Fallback AudioTrack usa writes bloqueantes, unidades correctas y detecta writes parciales/negativos.

### Transporte y observabilidad Android

- `StreamingNetworkLock` adquiere lock Wi-Fi solo desde `onConnectionStarted` hasta terminacion/cleanup.
- Android 10 o superior usa `WIFI_MODE_FULL_LOW_LATENCY`; versiones anteriores usan `WIFI_MODE_FULL_HIGH_PERF`.
- Adquisicion y liberacion son idempotentes y toleran fallo de plataforma.
- Stats exponen por separado `queueDepth` del presenter y `nativeVideoQueueFrames` de Moonlight.
- Eventos de stall incluyen codec, render path, Surface generation, frames recibidos/renderizados/presentados y ambas colas relevantes.

### Autoridad ABR

- Cliente parsea y persiste `ServerAbrActive` desde `serverinfo`.
- El bitrate dinamico por reconexion queda desactivado solamente cuando el servidor declara ABR NVENC activo.
- Servidores antiguos mantienen el comportamiento previo porque el campo ausente vale `false`.

## Cambios del servidor

### ABR basado en perdida real

- Se cuentan los data shards enviados por sesion.
- Sunshine/JUJOSTREAM recibe `SS_FRAME_FEC_STATUS` (`0x5502`) emitido por Moonlight y acumula data shards faltantes y frames irrecuperables.
- Los payloads FEC y legacy se validan por tamano, limites y alineacion antes de leerlos.
- Las bandas 5/15/30 por ciento coinciden con las bandas de estado de conexion de Moonlight; no son umbrales inventados.
- El health efectivo es el peor entre sesiones WebRTC y sesiones clasicas.
- El target inicial deja de ser cero y queda limitado al menor techo real de los encoders registrados.
- Downshift y upshift respetan el bitrate original individual de cada encoder.
- Stop del controlador usa condition variable; ya no puede esperar cinco segundos innecesariamente.
- Reconfiguracion NVENC exclusiva de bitrate/VBV no fuerza IDR: evita inyectar el frame mas grande justo durante congestion. Los IDR por perdida/overflow siguen existiendo donde si restauran referencias.
- ABR continua desactivado por defecto y `ServerAbrActive` solo se anuncia con ABR configurado y encoder activo `nvenc`.

### Overflow de la cola del encoder

- La cola acotada contabiliza cada episodio de overflow y permite consumir el contador atomicamente bajo su mutex.
- El broadcast de video detecta el evento, deja warning de alta senal y solicita IDR al encoder compartido.
- `reset()` limpia cola y telemetria, evitando contaminar una sesion nueva.
- No se cambio el tamano de cola, la estrategia de captura ni el pacing global.

## Decisiones conservadoras

Se preservaron intencionalmente:

- DirectSubmit default-off donde ya lo estaba.
- Politicas conocidas de dispositivos debiles.
- Captura latest-frame, encoder sin B-frames y VBV de un frame.
- FEC configurado existente.
- Cola Moonlight y tamaños de cola de video existentes.
- Pacing intraframe actual.
- ABR servidor default-off.

Reducir colas o modificar pacing sin captura A/B puede convertir jitter recuperable en drops. Por eso esta entrega primero elimina carreras, doble autoridad y estados muertos, y agrega las metricas necesarias para una afinacion fisica posterior.

## Commits

Cliente:

```text
6ab5065 docs(streaming): define hardening contracts
8c820a9 fix(streaming): serialize native session lifecycle
b1aac3e fix(streaming): enforce one codec negotiation contract
ccbd41a fix(streaming): recover presentation pipeline stalls
6227d65 fix(streaming): bound audio latency safely
47cc204 fix(streaming): enforce single ABR authority
7f9d594 perf(streaming): protect Android transport latency
```

Servidor:

```text
f8e73280 fix(streaming): wire classic ABR to FEC loss
3f0dbbef fix(streaming): recover encoder queue overflow
```

## Verificacion ejecutada

- `flutter test --reporter compact`: 216 pruebas, todas pasan.
- `flutter analyze --no-fatal-infos` sobre los Dart modificados: cero issues.
- `testDirectFireDebugUnitTest`: 47 pruebas JVM en 10 suites, cero failures/errors/skips.
- CMake Android debug: ARM64-v8a y armeabi-v7a, correcto.
- CMake Android release: ARM64-v8a y armeabi-v7a, correcto durante ambos APK.
- Test C++ host del ring buffer con `-Wall -Wextra -Werror`: correcto.
- `test_abr_network_health`: 3/3.
- `test_bounded_queue`: 2/2.
- `sunshine.exe` release Ninja: correcto; rebuild incremental sin trabajo pendiente.
- APK Direct/Fire y Play: release, R8/resource shrink, firma valida.
- Manifiesto empaquetado: Play sin `REQUEST_INSTALL_PACKAGES`; Direct/Fire con el permiso.

Warnings no bloqueantes observados: APIs Android previamente deprecadas (`Virtualizer`, algunos campos TV/Vibrator/MediaCodec) y advertencia de version Kotlin del tooling Gradle. Ninguno causa fallo de compilacion ni fue introducido como cambio funcional de este hardening.

## Artefactos

### FireTV / distribucion directa

```text
C:\Users\Jozh\repos\Jujo.StreamClient\build\app\outputs\apk\directFire\release\app-directFire-release.apk
Size: 103041178 bytes
SHA-256: 0D7171F3B8B3B4A208DF9D830C5FC55EDCFDBD0020411F8994C425ED3C43B3CE
```

### Play / Google TV

```text
C:\Users\Jozh\repos\Jujo.StreamClient\build\app\outputs\apk\play\release\app-play-release.apk
Size: 103040706 bytes
SHA-256: 541DD0D3D8ED020D09F6D14CEE2A2AAC200865224D48404D094A872832805049
```

### Servidor

```text
C:\Users\Jozh\repos\Jujo.StreamServer\build-ninja\sunshine.exe
Size: 70934816 bytes
```

## Aceptacion fisica pendiente

Cuando ADB vuelva a estar disponible, ejecutar sin modificar codigo:

1. FireTV y Chromecast: 30-60 minutos por codec soportado.
2. Tekken 8 con dos controles, rumble y triggers activos.
3. Diez ciclos start/stop y cierre desde handshake, gameplay y PiP.
4. Recreacion de Surface/background/foreground.
5. Perdida y jitter controlados, observando `nativeVideoQueueFrames`, `queueDepth`, FEC loss, audio overflow/underrun y eventos `renderStalled`.

La ausencia de ADB impide afirmar resultados termicos, RF, vendor MediaCodec o estabilidad prolongada sobre hardware real; no impide confirmar los contratos, pruebas, compilaciones y artefactos entregados aqui.

## Correccion Chromecast audio burst (2026-08-25)

Despues de la primera instalacion se reporto video excelente pero audio gravemente afectado. La inspeccion ADB de `media.audio_flinger` en Chromecast HD/Amlogic mostro:

```text
Sample rate: 48000 Hz
HAL frame count: 2048
Normal frame count: 2048
No FastMixer
```

Un burst de 2048 frames dura 42.67 ms. La FIFO fija anterior contenia 40 ms, por lo que un callback de burst completo podia pedir mas PCM del que la cola era capaz de almacenar y Oboe rellenaba el faltante con silencio.

La correccion:

- solicita callbacks Oboe del tamano exacto de `samplesPerFrame`;
- calcula la FIFO con `max(40 ms, 2 * framesPerBurst)`;
- conserva 40 ms en hardware low-latency;
- usa 4096 frames (85.33 ms) para el burst de 2048 del Chromecast;
- mantiene rechazo atomico SPSC, metricas y recuperacion del stream;
- agrega una prueba C++ que fija los contratos Chromecast, low-latency y burst desconocido.

Checkpoint adicional:

```text
checkpoint/pre-chromecast-audio-burst-fix-20260825
```
