# JUJOSTREAM: entrega consolidada de streaming, launcher y arte

Fecha de cierre: 2026-08-29  
Repositorios: `Jujo.StreamClient`, `Jujo.StreamServer`, `Jujo.StreamAdmin`

## Resultado

La entrega conserva el pipeline de streaming que ya demostró alta velocidad,
corrige el audio específico del Chromecast sin penalizar dispositivos de burst
pequeño, estabiliza el ciclo de vida nativo y separa definitivamente poster,
hero y galería en toda la cadena Admin -> Server -> Client.

El launcher trabaja stale-while-revalidate: conserva catálogo y arte caliente,
limita trabajo de decode, descarta solicitudes de foco obsoletas, no muestra
progreso para refresh automático y repara una sola vez entradas de cache
envenenadas. Una imagen vertical nunca vuelve a ocupar el rol de banner.

No se recortaron features. La variante Play/Google TV mantiene streaming y
Notification Mirror, pero no declara `REQUEST_INSTALL_PACKAGES`; la variante
DirectFire conserva el actualizador directo para Fire TV.

## Checkpoints recuperables

| Alcance | Checkpoint | Propósito |
|---|---|---|
| Streaming Client/Server | `checkpoint/pre-streaming-peak-20260817` | Estado anterior al hardening integral |
| Audio Chromecast | `checkpoint/pre-chromecast-audio-burst-fix-20260825` | Estado anterior al sizing por burst |
| Arte Admin/Server/Client | `checkpoint/pre-definitive-art-pipeline-20260826` | Estado anterior al contrato definitivo de arte |

Los checkpoints son tags; no se usó `reset --hard`, no se reescribió historia y
los binarios instalados conservan backups fechados.

## Cambios de streaming y latencia

### Cliente

- `NativeStreamCoordinator` serializa start, interrupt y stop; nunca hay dos
  conexiones Moonlight iniciando o activas a la vez.
- La negociación anuncia solamente codecs comprobados. La selección explícita
  no puede terminar negociando otro codec silenciosamente.
- MediaCodec cuenta presentación real mediante `OnFrameRenderedListener`.
- El watchdog distingue falta de salida inicial, stall de presentación y
  pérdida de Surface; intenta una recuperación local acotada y escala a
  reconexión serializada si no regresa el progreso.
- Direct Submit usa generaciones monotónicas de Surface y conserva el camino
  decoder -> Surface nativo sin conversión CPU.
- `LockFreeRingBuffer` mantiene propiedad SPSC: el productor nunca mueve el
  cursor del consumidor.
- Oboe dimensiona la FIFO con `max(40 ms, 2 * framesPerBurst)`. En Chromecast,
  un burst real de 2048 frames obtiene 4096 frames de cola; en hardware
  low-latency se conserva el objetivo de 40 ms.
- El lock Wi-Fi existe solamente durante una sesión y usa low-latency cuando la
  plataforma lo soporta.
- Cliente y servidor ya no compiten por el bitrate: `ServerAbrActive` define
  una sola autoridad ABR.

### Servidor

- La pérdida FEC real de sesiones clásicas alimenta el health ABR.
- Los payloads FEC/legacy se validan antes de leerse.
- El bitrate objetivo queda acotado por el techo real del encoder.
- Reconfigurar bitrate/VBV no fuerza un IDR durante congestión.
- Overflow de la cola de encoder deja telemetría y solicita un IDR para
  reconstruir referencias, sin cambiar arbitrariamente el tamaño de la cola.

Detalles y pruebas: `docs/STREAMING_PIPELINE_PEAK_HARDENING_2026-08-17.md`.

## Privacidad, foco, cierre y experiencia de apertura

- Juegos distintos de `Desktop` permanecen detrás de una barrera opaca hasta
  demostrar proceso propio, ventana visible, foreground estable, readiness
  autenticado, IDR y un frame presentado posterior al readiness.
- Direct Submit oculta y revela el `SurfaceView` real; ocultar únicamente Flutter
  no se considera una barrera de privacidad.
- El orquestador Windows rastrea propiedad por `(pid, creationTime)`, adopta
  descendientes y roots específicos seguros, y excluye Steam, Explorer y roots
  amplios.
- `CLOSE SESSION` intenta cierre graceful y luego termina solamente procesos
  cuya identidad owned todavía coincide. Steam y procesos preexistentes no se
  eliminan.
- El selector global ofrece Random, Cinematic Iris, Prism Bloom, Signal Veil,
  Poster Reveal y Minimal Luxe. Reduced motion fuerza una transición mínima.

Detalles y evidencia TEKKEN 8 con dos controles:
`docs/private-game-launch-session-fix-2026-08-06.md`.

## Launcher y cache

- Catálogo con TTL separado para lista y metadata; una lista válida nunca se
  vacía antes de tener reemplazo.
- Persistencia cargada antes de red en un proceso frío.
- Refresh stale en segundo plano sin destruir la UI actual.
- Dos operaciones concurrentes de poster y una de backdrop.
- Ventana direccional de prefetch y coalescing latest-wins.
- Cache keys lógicas y estables por servidor, app, rol e índice; DHCP no invalida
  arte idéntico.
- Budgets de decode por tema y por tamaño renderizado.
- Refresh automático silencioso; refresh manual mantiene feedback explícito.
- En TV, posters cacheados no repiten fade al volver al launcher.

Detalles: `docs/launcher-cache-navigation-optimization-2026-08-11.md`.

## Contrato definitivo de arte

### Admin

Commit: `3c65a7c fix(library): keep poster and hero roles distinct`

- `GameMetadataCandidate` convierte RAWG/IGDB a un contrato neutral y modular.
- RAWG sigue siendo fuente principal cuando corresponde; IGDB complementa
  poster, hero y galería faltantes sin sobrescribir inputs manuales válidos.
- La recuperación de poster consulta una portada vertical dedicada de IGDB; ya
  no reutiliza un background landscape como poster.
- Un artwork portrait o cuadrado rechazado permanece fuera del rol hero.
- Galería deduplicada y acotada; screenshots nunca se promueven silenciosamente
  a banner.

### Server

Commit: `d5f82497 fix(artwork): enforce poster and hero contracts`

- Nuevo módulo `artwork.{h,cpp}` inspecciona firma, tamaño y dimensiones de PNG,
  JPEG, WebP y GIF sin introducir un decoder pesado.
- Rechaza HTML/404 guardado con extensión de imagen, archivos truncados,
  payloads mayores a 32 MiB y dimensiones fuera de límites.
- Poster exige orientación vertical válida; hero exige landscape válido y
  acepta panorámicos hasta el límite del contrato.
- `/appasset` valida el rol antes de servir y no devuelve un poster vertical
  para una solicitud hero.
- Descargas remotas usan staging temporal y sólo se publican después de pasar
  validación. Un fallo nunca reemplaza arte válido existente.
- MIME y fallback respetan el arte realmente servido.

### Client

Commit: `043caba fix(launcher): deliver role-safe cached artwork`

- `GameArtPolicy` prioriza siempre hero landscape; si no existe, retorna
  explícitamente `none`, nunca el poster.
- `GameArtValidator` verifica dimensiones y proporción antes de autorizar un
  banner.
- `ArtworkCacheRecovery` elimina una entrada fallida y reintenta una sola vez
  por identidad versionada, evitando loops de descarga.
- Cache keys `nvart_v3` sobreviven cambios de IP del host sin mezclar servidor,
  app, rol o índice.
- `PosterImage` conserva cache de disco, aplica budgets de memoria y repara
  errores sin convertir cada rebuild en una descarga.
- `PremiumGameBackdrop` genera localmente un fondo determinista, barato y
  fluido cuando no hay hero válido. El poster vertical no se estira ni se usa
  como banner.
- Backbone, Hero y PS5 usan el mismo componente de backdrop; se eliminó la
  divergencia por tema.

Diseño y criterios completos en
`Jujo.StreamAdmin/docs/superpowers/specs/2026-08-26-definitive-launcher-art-pipeline-design.md`.

## Distribución Android conservadora

- Play/Google TV: actualizaciones mediante Play; sin
  `REQUEST_INSTALL_PACKAGES`.
- DirectFire: actualizador directo y permiso de instalación únicamente en el
  flavor destinado a Fire TV.
- Identidad y secretos migrados a almacenamiento seguro.
- Tráfico sensible de companion/notifications protegido.
- CI rechaza artefactos release sin firma válida o con permisos incompatibles
  con su canal.

Detalles: `docs/android-distribution-security-hardening-2026-08-11.md` y
`docs/release/android-distribution-runbook.md`.

## Diseño de producto

El Admin incorporó contexto Impeccable sin alterar comportamiento:

- `PRODUCT.md`: audiencia dual, propósito, personalidad, anti-referencias y
  accesibilidad.
- `DESIGN.md`: sistema canónico Standard/Jujo Purple bajo la dirección
  **La Cabina de Mando**.
- `.impeccable/design.json`: tokens extendidos, motion, breakpoints y previews
  autocontenidos de componentes.
- Retro y Pixel8 continúan como skins voluntarias; no fragmentan contratos.

Commit Admin: `5f9b892 docs(design): define Jujo visual system`.

## Commits principales

### Client

```text
8c820a9 fix(streaming): serialize native session lifecycle
b1aac3e fix(streaming): enforce one codec negotiation contract
ccbd41a fix(streaming): recover presentation pipeline stalls
6227d65 fix(streaming): bound audio latency safely
47cc204 fix(streaming): enforce single ABR authority
7f9d594 perf(streaming): protect Android transport latency
1389682 fix(audio): size Oboe queue to output burst
043caba fix(launcher): deliver role-safe cached artwork
```

### Server

```text
f8e73280 fix(streaming): wire classic ABR to FEC loss
3f0dbbef fix(streaming): recover encoder queue overflow
d5f82497 fix(artwork): enforce poster and hero contracts
```

### Admin

```text
2fb015e docs: define definitive artwork pipeline
3c65a7c fix(library): keep poster and hero roles distinct
5f9b892 docs(design): define Jujo visual system
```

## Verificación de este corte

### Admin

- `flutter test`: **323/323 PASS**.
- `flutter build windows --release`: **PASS**.
- Artefacto: `build/windows/x64/runner/Release/jujo_stream_app.exe`.

### Server

- Build release Ninja: **PASS**.
- Binario: `build-ninja/sunshine.exe`.
- Tamaño: `70,950,342` bytes.
- SHA-256 build/instalado:
  `70E9F499FCB72907616B543397E6C03E9A9B5A24DD025C621EFF810E2CAE64D3`.
- Instalado en `C:\Program Files\Jujo.Stream Server\sunshine.exe`.
- Backup: `sunshine.exe.bak-20260829-205950`.
- Servicio `Jujo.Server`: **RUNNING**.
- Listeners: TCP `47984`, `47989`, `47990`, `48010`.

### Client

- Suite Flutter completa del cambio de arte: **221/221 PASS**.
- Build Play release: **PASS**.
- APK: `build/app/outputs/flutter-apk/app-play-release.apk`.
- Versión: `1.1.23+24`.
- Tamaño: `102,504,942` bytes.
- SHA-256:
  `3C80F926260A03C9DAED72A3030A2446BDF9EBA152B3778480FB1FD0EBBE5757`.

### Dispositivos

| Dispositivo | Canal | Estado de este corte |
|---|---|---|
| Fire TV AFTKRT `192.168.3.137:5555` | DirectFire | Instalado `1.1.23+24`; MainActivity inicia; smoke log sin fatal, ANR, OOM ni error crítico de arte/codec |
| Chromecast HD | Play/Google TV | APK listo; instalación pendiente porque el dispositivo no aparece en `adb devices -l` ni `adb mdns services` |

No se afirma validación física del Chromecast mientras ADB no exponga un
endpoint. El APK exacto, su hash y la orden de instalación ya están listos.

## Instalación pendiente del Chromecast

Cuando Wireless debugging vuelva a publicar el dispositivo:

```powershell
adb devices -l
adb -s <serial-chromecast> install -r build/app/outputs/flutter-apk/app-play-release.apk
adb -s <serial-chromecast> shell monkey -p com.vizcorp.moonlight_jujo_stream -c android.intent.category.LAUNCHER 1
```

Después se debe comprobar `versionName=1.1.23`, `versionCode=24`, abrir el
launcher, navegar rápidamente por posters, iniciar una sesión corta y revisar
logcat por `FATAL EXCEPTION`, `OutOfMemoryError`, errores de artwork, stalls de
MediaCodec y underruns de audio.

## Rollback

### Código

Crear una rama desde el checkpoint requerido; no mover ni borrar la rama
actual:

```powershell
git switch -c recovery/pre-art checkpoint/pre-definitive-art-pipeline-20260826
```

### Server instalado

Con PowerShell elevado:

1. detener `Jujo.Server`;
2. copiar `sunshine.exe.bak-20260829-205950` sobre `sunshine.exe`;
3. iniciar `Jujo.Server`;
4. verificar estado `Running` y listeners `47984/47989/47990/48010`.

Nunca se sustituye el ejecutable mientras `sunshine.exe` está activo.

## Contratos que no deben volver a romperse

1. Poster, hero y galería son roles distintos en Admin, Server y Client.
2. Un hero inválido produce fallback local premium; nunca zoom de poster.
3. Una lista o imagen válida permanece visible durante refresh.
4. Cache identity depende de contenido lógico, no de una IP DHCP.
5. Trabajo automático es silencioso, acotado y cancelable por latest-wins.
6. Una sesión nueva no comparte ciclo de vida nativo con una anterior.
7. Un frame liberado por MediaCodec no cuenta como presentado sin callback.
8. Audio Oboe nunca tiene menos capacidad que un burst completo.
9. Sólo una autoridad controla bitrate.
10. Play no declara instalación de paquetes; DirectFire no pierde su updater.
11. Juegos no Desktop permanecen ocultos hasta readiness y frame seguro.
12. Cierre sólo afecta identidades owned comprobadas por PID y creation time.
