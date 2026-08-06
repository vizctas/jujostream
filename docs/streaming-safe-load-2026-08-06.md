# JUJOSTREAM: safe load del streaming funcional y lecciones de método

Fecha: 2026-08-06
Alcance: cliente Android (Chromecast HD, Fire TV 4K, S24 Ultra).
Complementa, sin repetir, a:

- `docs/streaming-stability-2026-08-06.md` — el incidente Binder/LightsSession y su evidencia.
- `docs/private-game-launch-session-fix-2026-08-06.md` — la sesión privada de lanzamiento.

Este archivo tiene dos propósitos. El primero es servir de punto de restauración:
qué configuración por dispositivo está demostrada, qué línea de log lo confirma y
qué invariantes no se pueden romper. El segundo es dejar registrado el método que
funcionó, porque la regresión de esta semana no se produjo por falta de
conocimiento del código sino por una forma equivocada de diagnosticar.

## Estado del árbol al escribir esto

```text
versión        1.1.22+23
tests Dart     192 en verde
tests Android  en verde (:app:testDebugUnitTest BUILD SUCCESSFUL)
APK actual     370971A159F16B6626F4C7839B52311508DDCD738A7A963D5B23499A7F4DAC84
```

El APK actual **no** coincide con el validado en `streaming-stability` porque
después de esa validación entró el trabajo de sesión privada de lanzamiento
(16:41–17:30). El árbol es un superconjunto: conserva los contratos de streaming
verificados y añade funcionalidad no medida todavía en hardware.

Nivel de evidencia por componente, sin redondear hacia arriba:

| Componente | Evidencia |
|---|---|
| Política de decoder por familia de SoC | Sesiones medidas en Chromecast y Fire TV |
| Ciclo de vida de luces / Binder | 4:21 con dos DualSense sin kill, contra kills previos a 36–72 s |
| Drenado de estadísticas antes del teardown | Cierres limpios registrados en ambos dispositivos |
| Métricas de frames corregidas | Verificado en log: primera muestra `recv=300`, sin `recv=0` |
| Discovery sin HTTPS condenado | Medido: 25 handshakes inútiles por captura → 0 |
| Sesión privada de lanzamiento | Tests verdes; **sin sesión de hardware medida** |
| S24 Ultra | **Sin sesión medida en esta ronda**; su ruta se deriva del código |

## Línea base por dispositivo

La clasificación la decide `detectWeakDevice()` en `StreamingPlugin.kt:512` y es
determinista. Los tres dispositivos caen en ramas distintas a propósito.

| | Chromecast HD | Fire TV 4K (AFTKRT) | S24 Ultra |
|---|---|---|---|
| Clasificación | débil (tier-3: TV, RAM < 2800 MB) | débil (tier-3) | no débil (tier-2, SoC capaz) |
| Decoder | `c2.amlogic.avc.decoder` | `OMX.MTK.VIDEO.DECODER.AVC` | Qualcomm (`c2.qti.*`) |
| Codec anunciado | H.264 forzado | H.264 forzado | sin forzar |
| `KEY_OPERATING_RATE` | tasa real (60.0) | `min(tasa, 30)` = 30.0 | `Short.MAX_VALUE` |
| `KEY_PRIORITY` | 0 | 1 | 0 |
| Profundidad de cola | 1 | 1 | sin recorte (0–6) |
| Ruta de render | Flutter SurfaceProducer | Flutter SurfaceProducer | SurfaceProducer |
| DirectSubmit | apagado | apagado | apagado |

Líneas de log que confirman el estado correcto:

```text
Chromecast  Weak decoder rate policy: operatingRate=60.0, priority=0, amlogic=true
Fire TV     Weak decoder rate policy: operatingRate=30.0, priority=1, amlogic=false
cierre      StreamStats stopped; native stats calls drained
```

Si el Chromecast registra `operatingRate=30.0`, la regresión volvió.

## Invariantes que no se rompen

1. **Ninguna política de SoC se comparte sin evidencia por dispositivo.** MediaTek,
   Amlogic y Qualcomm son ramas separadas. Un límite global de 30 fps para todos
   los "weak devices" es exactamente la regresión que dejó el Chromecast injugable.
2. **Orden de teardown:** detener timer → bloquear lecturas nuevas → esperar la
   llamada JNI en vuelo → `nativeStopConnection()`/cleanup. Nunca mover
   `nativeStopConnection()` antes de `stopStatsPolling()`.
3. **Al entrar al stream:** bloquear efectos de UI → drenar la cola → stop →
   dispose. Durante el stream no se llama `getCurrentPosition` ni se reproduce
   audio de interfaz.
4. **Sesiones Binder vivas ≤ controles físicos con luz RGB.** Toda `LightsSession`
   se reutiliza y se cierra explícitamente.
5. **Todo callback de alta frecuencia que cruza un límite** (Binder, JNI,
   EventChannel a Dart) necesita dueño, límite de frecuencia y cierre explícito.
6. **`framesReceived` sólo cuenta imagen.** SPS/PPS/VPS no incrementan el contador.
   Un frame de imagen rechazado cuenta como drop.
7. **DirectSubmit no se fuerza globalmente en Android TV.** En Amlogic la ruta
   SurfaceControl presentó 398 de 10.500 frames. Es una decisión por dispositivo.
8. **HTTPS de discovery sólo cuando hay certificado fijado.** Sin certificado el
   handshake contra un cert autofirmado no puede tener éxito.

## Lo que aprendí del trabajo de GPT SOL

### 1. Separar la política de la llamada a la plataforma

Las tres clases nuevas —`WeakDeviceDecoderPolicy`, `StreamStatsGuard`,
`ControllerLedThrottle`— no importan nada de Android. El comentario de la tercera
lo dice explícitamente: *"deliberately Android-free so the scheduling policy is
covered by ordinary JVM tests"*.

El efecto práctico es que la decisión queda cubierta por un test de 3 líneas en
lugar de requerir un dispositivo. `WeakDeviceDecoderPolicy` son 17 líneas y su
test fija los tres casos que importan. Antes, la misma decisión vivía embebida en
la construcción del `MediaFormat`, donde sólo se podía verificar mirando un log
en hardware.

**Regla:** si una decisión depende de una condición del dispositivo, esa decisión
va en una función pura y probable. La llamada a la API queda como una línea tonta.

### 2. Una variable por experimento, y escrito en el código

En `VideoDecoderRenderer.kt` la rama no-Qualcomm perdió el `KEY_OPERATING_RATE`
que alguien había añadido, con esta justificación en el propio comentario:

> Measured: the Amlogic decoder presented 1764/1800 frames without it. Adding it
> was an untested guess bundled with another change, so it goes back out — one
> variable at a time.

Eso es exactamente lo que yo no hice: cambié DirectSubmit y el operating rate a la
vez, y después no pude atribuir el resultado a ninguno de los dos.

### 3. Verificar el instrumento antes de creerle a la medición

Este es el hallazgo que más me corrige. `totalFramesReceived` incrementaba con
**cualquier** tipo de buffer, incluidos SPS/PPS/VPS, y lo hacía *después* de los
returns tempranos. `totalFramesDropped` no contaba los rechazos de entrada.

Consecuencia: yo construí `measure.py` sobre esas cifras y comparé builds con
ellas durante horas. El numerador y el denominador estaban mal. Las tablas de
"present ratio" que usé para decidir eran ruido con formato de dato.

**Regla:** antes de optimizar contra una métrica, leer el código que la produce.
Una métrica no verificada es una opinión con decimales.

### 4. Pedirle el veredicto al sistema operativo

La causa del crash no se dedujo del código: se leyó de Android.

```text
adb shell dumpsys activity exit-info com.vizcorp.moonlight_jujo_stream
  reason=13 (OTHER KILLS BY SYSTEM)
  subreason=11 (KILL UID)
  description=Too many Binders sent to SYSTEM
```

Yo nunca ejecuté `exit-info`. Estuve leyendo logcat buscando una excepción que no
existía, porque el proceso no fallaba: lo mataban. El sistema tenía la respuesta
registrada y con motivo explícito todo el tiempo.

**Regla:** cuando un proceso muere, preguntar primero por qué lo dice el SO.
`exit-info`, `dumpsys`, `ApplicationExitInfo` antes que cualquier hipótesis.

### 5. Diseñar el experimento que discrimina

La tabla que aisló la causa:

| Escenario | Resultado |
|---|---|
| TEKKEN + 1 DualSense | ~173 s, fin normal |
| TEKKEN + 2 DualSense | kill a ~36 s |
| Desktop + 1, luego un segundo control | kill ~40 s después del segundo |

La tercera fila es la que hace el trabajo: elimina TEKKEN como causa y deja el
número de controles como única variable. Una fila de tabla diseñada a propósito
vale más que veinte capturas del mismo escenario.

### 6. No tocar lo que la evidencia no implica

Tres decisiones de contención que valen tanto como los arreglos:

- No se cambió codec, cola, Surface, frame pacing ni presentación: *"los datos
  reales no justificaban ese riesgo"*.
- No se tocó Fire TV, que ya iba 8,5/10, para no arriesgar un perfil estable.
- Se auditó la ruta de vibración por si tenía la misma fuga; se comprobó en la
  fuente del SDK que `InputDevice` cachea su `VibratorManager` y reutiliza el
  token, y por eso **no** se limitó el haptic feedback.

Ese tercer punto es el más disciplinado: se investigó el vecino sospechoso, se
concluyó que estaba sano y se dejó en paz.

### 7. Restaurar un conjunto conocido completo, no una mezcla

La profundidad de cola quedó en 1 para dispositivos débiles aunque el comentario
argumenta que 2 absorbería mejor el jitter, con esta razón: *"match it so the
whole configuration is one known-good set rather than a mix"*. Media restauración
produce una configuración que nunca se probó en ningún lado.

### 8. Mantener los hallazgos independientes separados

Los errores de CloudAgent por JWT y el ruido de NVENC en el sondeo se anotaron
como hallazgos aparte, con la nota de que no coincidían causalmente con el kill.
Es lo contrario de declarar causa a la primera advertencia visible del log.

## Errores míos de esta semana y su antídoto

| Error | Antídoto |
|---|---|
| Apliqué los valores de Fire TV a todos los dispositivos débiles | Una política por familia de decoder, con test por caso |
| Cambié DirectSubmit y operating rate a la vez | Una variable por build; anotar la medición en el comentario |
| Confié en `measure.py` sin auditar de dónde salían los contadores | Leer el productor de la métrica antes de decidir con ella |
| Borré `weakDevice` creyendo que MiBox lo había introducido | `git log -S` antes de afirmar el origen de un subsistema |
| Busqué una excepción en logcat en vez de preguntar al SO | `dumpsys activity exit-info` como primer paso ante una muerte |
| Tomé un cero en todas las métricas como éxito | Un cero en el control significa que no hay datos, no que funciona |

El último merece detalle porque casi lo doy por bueno: al medir el fix de
discovery obtuve 0 handshakes fallidos **y** 0 llamadas HTTP. Cero en el grupo de
control no es una mejora, es una captura vacía. La app no había arrancado porque
en Android TV la actividad se declara con `LEANBACK_LAUNCHER` y `monkey` con
`LAUNCHER` no la encuentra. Toda medición necesita una señal que demuestre que el
experimento ocurrió.

## Antes de promover un build

1. `flutter test` y `:app:testDebugUnitTest` en verde.
2. Build release con el JBR de Android Studio, **una sola vez**.
3. Instalar exactamente ese artefacto en cada dispositivo y comparar el SHA-256
   remoto de `base.apk` con el local antes de sacar conclusiones.
4. Chromecast → cierre limpio → Fire TV → volver a Chromecast. La reentrada es
   criterio obligatorio.
5. Confirmar las dos líneas de `Weak decoder rate policy` y el
   `StreamStats stopped; native stats calls drained` en cada cierre.
6. Con dos DualSense: `liveSessions` nunca supera 2, una sola línea
   `Detected 2 gamepad(s)`, cero `ControllerNumber already allocated`.
7. Cero `renderStalled`, FORTIFY, señal fatal, ANR o `ApplicationExitInfo` nuevo.

Comandos de diagnóstico en `docs/streaming-stability-2026-08-06.md`. Para lanzar
en Android TV hay que usar la actividad explícita, no `monkey`:

```bash
adb -s <serial> shell am start -n com.vizcorp.moonlight_jujo_stream/com.limelight.jujostream.MainActivity
```

## Pendiente

- El árbol completo no tiene sesión de hardware medida después del trabajo de
  sesión privada de lanzamiento.
- S24 Ultra no tiene sesión medida en esta ronda; su configuración está derivada
  del código, no observada.
- Nada de este trabajo está commiteado. Los releases publicados siguen siendo
  server-1.0.29, client-1.1.22 y admin-1.0.26.
