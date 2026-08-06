# JUJOSTREAM: sesión privada de juego, foco, cierre, arte y reveals

Fecha: 2026-08-06  
Repositorios: `Jujo.StreamServer` y `Jujo.StreamClient`  
Especificación aprobada: `docs/superpowers/specs/2026-08-06-private-game-launch-session-design.md`

## Resultado

El lanzamiento de una aplicación distinta de `Desktop` dejó de usar la mera
conexión RTSP como autorización para mostrar video. JUJOSTREAM exige ahora una
prueba completa y fail-closed:

```text
proceso nuevo y perteneciente a la sesión
  -> ventana real visible
  -> ventana restaurada y en foreground estable
  -> readiness autenticado del host
  -> solicitud de IDR
  -> frame renderizado posterior al readiness
  -> reveal seleccionado
  -> habilitación de input y overlays
```

Si falta cualquiera de esas pruebas, el video continúa oculto. `Desktop` es la
única excepción explícita porque el usuario escogió ver el escritorio.

El mismo cambio agrega cierre seguro de juegos lanzados indirectamente por
Steam, composición correcta de posters verticales, cache persistente de arte y
cinco reveals globales seleccionables.

## Cadena de fallos confirmada

No se corrigió a partir de una única sospecha. Se siguió el flujo completo
cliente -> HTTPS -> proceso -> ventana -> RTSP -> decoder -> compositor:

1. El host despachaba `steam://rungameid/...` y devolvía `/launch` antes de que
   existiera una ventana de juego estable.
2. El foco Win32 robusto estaba limitado a la integración de Playnite; los
   comandos genéricos y shortcuts de Steam no recorrían ese camino.
3. El cliente retiraba la pantalla de conexión al terminar el arranque del
   transporte, por lo que un frame del escritorio ya decodificado podía salir.
4. Direct Submit usa un `SurfaceView`; ocultar sólo el widget Flutter no es una
   barrera suficiente para ese compositor.
5. Steam puede reparentar el juego fuera del process group del servidor.
   TEKKEN 8 usa el shortcut `14390411998296801280` y el root configurado
   `G:\Games\TEKKEN 8\Polaris\Binaries\Win64`; no existe un manifest estándar
   que permita resolverlo bajo `steamapps/common`.
6. El fallback de poster usaba `BoxFit.cover` sobre un viewport 16:9 y convertía
   una portada vertical en un zoom incomprensible.
7. Las pantallas de launch usaban carga de red directa en vez del cache de arte
   ya existente.

## Cambios en Jujo.StreamServer

### Orquestador de sesión Windows

Archivos nuevos:

- `src/platform/windows/game_session_orchestrator.h`
- `src/platform/windows/game_session_orchestrator.cpp`
- `src/platform/windows/game_session_policy.cpp`
- `tests/unit/test_game_session_orchestrator.cpp`

Integración:

- `src/process.cpp`
- `src/nvhttp.cpp`
- `cmake/compile_definitions/windows.cmake`
- `tests/CMakeLists.txt`

El orquestador mantiene los estados `launching`, `waitingWindow`, `focusing`,
`stabilizing`, `ready`, `failed`, `cancelling` y `closed` en un worker propio.
`/launch` no bloquea un thread HTTPS durante los 90 segundos de timeout.

Antes de ejecutar prep commands, detached commands o el comando principal se
captura un baseline de procesos. La identidad autoritativa es
`(pid, creationTime)`, no sólo PID. Así un PID reciclado no hereda pertenencia.

Un proceso sólo se adopta cuando:

- fue creado después del baseline; y
- es el proceso directo, descendiente de uno ya adoptado o su executable está
  bajo un root específico validado.

Los roots vacíos, raíces de unidad, Windows, System32, ProgramData, el perfil de
usuario completo y la raíz del cliente Steam se rechazan. `steam.exe`,
`steamservice.exe`, `steamwebhelper.exe`, Explorer y otros shells nunca se
adoptan. El working directory específico de TEKKEN sí es válido.

El selector de ventana considera solamente ventanas top-level visibles, no
cloaked, con área interactiva y pertenecientes a procesos adoptados. Prefiere
área, cobertura de monitor y foreground. Restaura minimizadas, aplica la
utilidad Win32 de foco existente y exige estabilidad del mismo HWND/PID: 1.5 s
para una ventana de al menos 30 % del monitor y 4 s para una ventana menor.
Esto permite que una ventana real reemplace launchers o splash externos.

Una sesión ya `ready` continúa supervisando el foreground y vuelve a reclamar
foco si el juego lo pierde, sin relanzarlo.

### Protocolo de readiness

Las respuestas `/launch` y `/resume` agregan campos opcionales compatibles con
clientes anteriores:

- `GameLaunchReadinessVersion`
- `GameLaunchReadinessRequired`
- `GameLaunchStateToken`
- `GameLaunchState`
- `GameLaunchStateGeneration`

El endpoint autenticado `/launchstate?action=status|retry&token=...` expone
estado, detalle, failure code, generación, intento y PID seleccionado. El token
se vincula al UUID del certificado cliente. Otro cliente emparejado no puede
consultarlo ni ejecutar retry. Retry repite discovery/focus sobre la sesión
actual y nunca vuelve a despachar el juego.

### Cierre de sesión

`CLOSE SESSION` detiene primero el worker y ejecuta un último discovery. Luego:

1. envía `WM_CLOSE` a ventanas de identidades propias;
2. espera el presupuesto de cierre graceful;
3. vuelve a comprobar `creationTime`;
4. usa `TerminateProcess` sólo en identidades que todavía coinciden;
5. converge con el cleanup previo de process group, input, display y sesión.

Steam y procesos preexistentes quedan fuera por política y por baseline. No se
usa un kill amplio por directorio.

### Regresión de teardown encontrada en la prueba live

La primera sesión real de TEKKEN reveló un fallo adicional que las pruebas
estáticas no podían mostrar. Tras una desconexión del cliente, el launcher
`steam://` ya había terminado, pero `Polaris-Win64-Shipping` seguía vivo y
pertenecía al orquestador. `proc_t::running()` consultaba solamente el launcher,
declaraba la app terminada y ejecutaba el cierre graceful de procesos dentro
del join RTSP. Ese trabajo consumió más del presupuesto global de 10 segundos y
activó `Hang detected! Session failed to terminate in 10 seconds`, provocando
el reinicio del servidor.

Se corrigió el contrato en el origen:

- una app detached sigue reportando `running` si Playnite la administra, el
  launcher vive, existe al menos una identidad owned viva o hay un stream
  activo;
- una desconexión ordinaria conserva el juego para resume y no ejecuta cleanup
  dentro del watchdog RTSP;
- `/cancel`/`CLOSE SESSION` conserva la ruta explícita de cierre owned;
- Steam continúa excluido y el estado vivo se comprueba por PID+creationTime.

No se amplió el watchdog ni se redujo el graceful timeout: ambas alternativas
habrían ocultado la inconsistencia de estado sin corregirla.

## Cambios en Jujo.StreamClient

### Contrato HTTP y gate privado

Archivos principales:

- `lib/services/http_api/nv_http_client.dart`
- `lib/providers/app_list_provider.dart`
- `lib/screens/app_view/app_view_screen.dart`
- `lib/screens/game/game_launch_privacy_gate.dart`
- `lib/screens/game/game_stream_screen.dart`
- `lib/platform_channels/streaming_channel.dart`

El cliente parsea el contrato nuevo sin romper servidores legacy. Para juegos,
un servidor legacy o un token ausente produce un error accionable y mantiene
video opaco; no existe fallback inseguro. Para `Desktop` se conserva la
compatibilidad anterior.

El gate separa cuatro hechos:

- `transportConnected`
- `hostGameReady`
- `postReadyFrameRendered`
- `revealCompleted`

Cuando llega una nueva generación `ready`, el cliente captura
`framesRendered`, llama `LiRequestIdrFrame()` y espera que el contador avance.
Sólo entonces habilita la presentación debajo de la superficie de launch.
Reconnect, stop, retry y error vuelven a ocultarla antes de reiniciar estado.
PiP, input, OSC y estadísticas visuales requieren reveal completado.

El error de readiness ofrece `Retry focus` y `Close session`. Back/B desde ese
error cierra la sesión en vez de abrir un overlay sobre una sesión inválida.

### Barrera nativa de Direct Submit

Archivos:

- `android/app/src/main/cpp/bridge/moonlight_bridge.c`
- `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/StreamingBridge.kt`
- `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/StreamingPlugin.kt`
- `android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/DirectSubmitViewFactory.kt`

Se exponen `requestIdrFrame` y `setVideoVisible`. El `SurfaceView` activo usa
alpha 0/1 sin destruir su Surface ni resetear MediaCodec. Así decoder y RTSP
pueden inicializar detrás de una barrera real y el reveal no necesita crear de
nuevo el pipeline.

### Arte y cache

Archivos:

- `lib/widgets/poster_image.dart`
- `lib/widgets/game_backdrop_art.dart`
- `lib/widgets/launch_experience.dart`
- `lib/screens/app_view/app_view_screen.dart`
- `lib/screens/game/game_stream_screen.dart`

`LaunchExperience` unifica pre-launch y handshake. Un hero landscape validado
permanece `BoxFit.cover`. Si sólo existe poster vertical, el resultado usa una
capa completa oscurecida/softened como backing y el poster íntegro al frente
con `BoxFit.contain`, margen seguro y profundidad moderada.

Ambas fases usan `PosterImage.artCacheManager`, cache keys estables y cache de
disco de 90 días. El arte seleccionado se precarga antes de que
`ImageLoadThrottle.pauseForStream()` reduzca el trabajo de imágenes durante el
stream. Ya no existe `Image.network` en las superficies de launch.

### Selector global de reveals

Archivos:

- `lib/models/stream_configuration.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/widgets/launch_reveal_transition.dart`
- `lib/screens/game/game_stream_screen.dart`

En `OPTIONS > Personalización > Efecto de apertura del juego` se persiste:

- Random (default)
- Cinematic Iris
- Prism Bloom
- Signal Veil
- Poster Reveal
- Minimal Luxe

Random resuelve a un único efecto concreto por launch. Movimiento reducido o
modo rendimiento fuerzan Minimal Luxe a 180 ms. Los efectos usan sólo opacity,
transform, clip, paint y gradientes acotados; el blur del fondo es estático. La
animación corre después del frame seguro. Una excepción visual completa al
frame ya autorizado y nunca abre el gate anticipadamente.

## Trabajo previo preservado

El fix de dos controles que eliminó la ralentización/crash de TEKKEN 8 no se
revirtió ni se retunó. También se preservaron los cambios simultáneos de otra
AI relacionados con certificados, watchword pairing y features de cloud. Los
archivos compartidos estaban dirty; por eso no se hizo reset, checkout ni
commit global de esos cambios.

Los peaks pequeños y esporádicos de drops quedan fuera de este cambio: no había
evidencia reproducible para modificar decoder, red o pacing otra vez.

## Pruebas ejecutadas

### Client

- `flutter analyze --no-fatal-infos` sobre los Dart tocados: PASS.
- Suite focalizada de protocolo/gate/arte/cache/reveals: 27/27 PASS.
- Suite Flutter completa: 192/192 PASS.
- `:app:testDebugUnitTest` con el JBR de Android Studio: PASS.
- `flutter build apk --release`: PASS.

El agregado Gradle `testDebugUnitTest` también ejecuta tests internos de todos
los plugins. Falló únicamente en 10 fixtures ausentes de
`image_picker_android` (`FileNotFoundException` en `ImageResizerTest`). La tarea
aislada del módulo JUJOSTREAM pasa y el APK release se construye.

### Server

- `cmake --build build-ninja --target sunshine --parallel 8`: PASS.
- `test_game_session_policy`: 7/7 PASS.
- Cobertura: roots peligrosos, boundaries, baseline, PID reuse, adopción
  directa/descendiente/root, exclusión permanente de Steam y conservación de
  una sesión detached mientras el juego owned siga vivo.

El binario monolítico de tests del checkout tiene fallos de link preexistentes
en `SessionDeferralManager`, `DisplayHelperWatchdog` y `server_start_time`. La
política destructiva se separó en un target focalizado para no confundir esos
links ajenos con su veredicto.

## Artefactos y despliegue

### APK release

- Archivo: `build/app/outputs/flutter-apk/app-release.apk`
- Tamaño: 102341506 bytes (97.6 MB reportados por Flutter)
- SHA-256: `370971A159F16B6626F4C7839B52311508DDCD738A7A963D5B23499A7F4DAC84`
- Package: `com.vizcorp.moonlight_jujo_stream`
- Versión: `1.1.22+23`

### Host release

- Archivo de build: `Jujo.StreamServer/build-ninja/sunshine.exe`
- Tamaño: 70927979 bytes
- SHA-256 instalado: `AC6F0FA2EFA47291EC10BDF53436DBFA709AB77E06A3D6F509B8E4B0F1EC217C`
- Servicio: `Jujo.Server`, estado `Running`
- Listener verificado: TCP 47984, 47989, 47990 y 48010
- Backup recuperable:
  `C:\Program Files\Jujo.Stream Server\sunshine.exe.codex-backup-20260806-172115`
- Backup inmediatamente anterior al fix de teardown:
  `C:\Program Files\Jujo.Stream Server\sunshine.exe.pre-teardown-fix-20260806`

### Dispositivos al corte

| Dispositivo | Serial ADB | API/Android | Estado |
|---|---|---:|---|
| Fire TV AFTKRT | `192.168.3.137:5555` | Android 11 | APK 1.1.22+23; smoke posterior al redeploy PASS, MainActivity enfocada, JUJOPC descubierto, sin fatal/ANR |
| Chromecast HD | `adb-27201HFGN1QWGB-S7HBwA._adb-tls-connect._tcp` | Android 14 | APK 1.1.22+23; TEKKEN live validado; ADB-TLS se desconectó después y requiere reactivar Wireless Debugging para recoger el cierre final |

Fire TV mantiene una captura local posterior al fix en
`build/jujostream-firetv-post-teardown-fix-20260806.log`. No se registró
`FATAL EXCEPTION`, ANR ni fatal signal en el smoke test de arranque.

### Evidencia live Chromecast: TEKKEN 8

- 17:56:36: `/launch` despachado.
- 17:56:42: decoder `c2.amlogic.avc.decoder` configurado a 1920x1080@60,
  H.264, SurfaceProducer, y conexión iniciada.
- 17:56:42: dos DualSense asignados a slot 0 y slot 1 en cliente y Gamepad 0/1
  emulados como DualShock 4 en host.
- 17:56:42-17:56:53: readiness avanzó por `waitingWindow`, `stabilizing`,
  `focusing`, `stabilizing` y `ready`; PID seleccionado 7632.
- 17:56:53: IDR aceptado; contador avanzó de 458 a 459.
- 17:56:53-17:56:54: reveal `minimalLuxe` inició y terminó; el Surface se hizo
  visible sólo después del frame seguro.
- El foreground Win32 fue `Polaris-Win64-Shipping`/`TEKKEN 8`; no se mostró el
  escritorio en la captura del cliente.
- A 6600 frames recibidos: 6589 renderizados, 9 drops acumulados y 18 ms de
  latency del decoder. Hubo ráfagas de pérdida de red e IDR recovery, pero el
  contador de render continuó avanzando y no apareció `renderStalled`.

## Recuperación

Si el binario host desplegado necesitara rollback:

1. detener `Jujo.Server` con privilegios administrativos;
2. copiar el backup timestamped anterior sobre
   `C:\Program Files\Jujo.Stream Server\sunshine.exe`;
3. iniciar `Jujo.Server`;
4. comprobar estado `Running` y listeners 47984/47989/47990/48010.

No se debe restaurar el backup mientras el servicio o `sunshine.exe` estén
activos. El APK release validado queda conservado en su ruta de build.

## Validación live restante

TEKKEN 8, dos controles, foco, privacidad del escritorio, frame gate, reveal y
decode sostenido ya tienen evidencia real. Fire TV tiene smoke posterior al
último binario. Resta una sola prueba no inferible: reconectar ADB-TLS del
Chromecast, repetir una sesión corta con el servidor que contiene el fix de
teardown y ejecutar `CLOSE SESSION`, comprobando que TEKKEN sale, Steam
permanece y `Jujo.Server` no reinicia. Después se recogerá el logcat remoto que
quedó en `/sdcard/jujostream-chromecast-final-20260806.log`.
