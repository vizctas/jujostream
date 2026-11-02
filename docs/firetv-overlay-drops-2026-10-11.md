# Fire TV: overlay y tirones

## Plan y estado

- [x] Identificar dispositivo y preservar registros/APK instalada.
- [x] Reproducir el fallo del overlay usando el handler Android real y el layout de Fire OS.
- [x] Corrección acotada del mapeo; 76 pruebas JVM pasan.
- [x] Capturar una sesión antes del parche para distinguir recepción, decodificación y presentación.
- [x] Compilar/verificar/instalar directFire 1.1.28+29; `adb install -r` Success.
- [x] Validar arranque y capturar sesión posterior. Confirmación física del atajo pendiente.
- [ ] Reproducir picos durante gameplay: no reproducidos en la pantalla inicial.

Dispositivo confirmado por ADB: Amazon AFTKRT / karat, serial G072JM0835250AW6,
192.168.3.137:5555. Versión previa 1.1.27+28. Dos DualSense independientes.

## Overlay

Fire OS contiene `/system/usr/keylayout/Vendor_054c_Product_0ce6.kl` con el
layout Sony fallback: scan 308 = BUTTON_L1. El cliente asumía que Android < 12
necesitaba el mapeo genérico Linux y convertía incondicionalmente scan 308 en X.
Por tanto faltaba LB en el bitmask 0x330, aun con configuración correcta.

La corrección conserva keycodes ya traducidos por Android y aplica el intercambio
X/Y antiguo únicamente cuando coinciden scan y keycode del layout genérico.
No cambia timers, emulación Guide, configuración del usuario ni el decoder.

Prueba de integración con Robolectric API 30: InputDevice, KeyEvent, handler real,
Looper y MethodChannel. Solo se sustituye la frontera JNI. Falla antes del parche
con cero eventos `onComboDetected`; pasa después para 24 órdenes por cada uno de
dos mandos. Incluye layout antiguo, layout Sony ya traducido, combinación parcial,
botones repartidos entre mandos, hold y cancelación al soltar.

La hipótesis inicial de emulación Guide no explica estos dispositivos: la sesión
real detecta `hasMode=true`. No se modifica esa emulación. Robolectric solo es
dependencia de test; guía de configuración: https://robolectric.org/getting-started/.

## Streaming

La captura inicial de logcat no conservaba la partida reportada. El único crash
conservado corresponde a Send Files to TV, no a JUJO.Stream.

Se abrió Absolum desde el cliente por ADB para obtener una referencia: H264,
1920x1080@60, OMX.MTK.VIDEO.DECODER.AVC, modo latencia, ruta texture. En la
pantalla inicial animada se mantiene aproximadamente 60 FPS, sin drops del
decoder ni acumulación de cola. El arranque/carga tiene menor cadencia de entrada;
no se confunde ese tramo con pérdida del decoder ni con gameplay sostenido.

La primera lectura de Wi-Fi era 2452 MHz (2.4 GHz), 154 Mbps de enlace. La lectura
durante la sesión es 5785 MHz (5 GHz), 1201 Mbps, RSSI -38. El agente no modificó
la configuración Wi-Fi. Esta diferencia impide atribuir la estabilidad al parche
de input o concluir que se resolvieron los tirones originales.

No se aplica un parche de rendimiento sin reproducción. Evidencias locales en
`.private/firetv-20261011/`: logcat, snapshots de sesión/Wi-Fi/input, prueba roja,
prueba verde, suite JVM y APK anterior. Los registros pueden contener identificadores
locales; no se publican ni se envían fuera del equipo.

La compilación Release en el mismo PC servidor reduce la cadencia recibida a
aproximadamente 40–45 FPS sin drops del decoder: ese tramo se excluye de la
comparación de rendimiento. No se atribuye al Fire TV ni se usa como prueba de
causa para los tirones originales.

## Validación y despliegue

- JVM: 76 pruebas, cero fallos. Contrato de distribución Flutter: 1 prueba pasa.
- APK Fire SHA256: `7104AD742651D8436A387B6F3939F181049F73AECFCEE930CE120BAF2D9B5786`.
- Firma de producción verificada; permiso de instalación presente en directFire.
- Versión instalada confirmada: 1.1.28 / code 29; app inicia y carga biblioteca.
- Hash de `base.apk` instalada coincide con el artefacto verificado.
- Respaldo: `.private/firetv-20261011/fire-installed-before.apk`.
- Solo se actualiza el Fire TV identificado; no se despliega a Chromecast o servidor.

Límite de la prueba de dispositivo: `sendevent` no tiene permiso sobre el mando.
El harness Java aislado por ADB sí inyecta teclas, pero Android sustituye el
deviceId por -1; abre el overlay a través de Flutter incluso en la APK anterior.
No valida la ruta del mando físico ni se presenta como prueba de la corrección.
El primer arranque del harness con `-Djava.class.path` abortó en ART; con CLASSPATH
funciona. Es un proceso shell separado, no un crash de JUJO.Stream. El harness y
sus registros quedan aislados en `.private` para no confundir este evento con el
reporte del usuario. La regresión significativa es la prueba del handler Android
con dispositivo y scan codes reales.

Referencia cuantificada en `stats-summary.json` (pantalla inicial animada, 5 GHz):

| Tramo | Duración | Frames recibidos | FPS medios recibidos | Drops decoder | RTT máximo | Cola máxima |
|---|---:|---:|---:|---:|---:|---:|
| Antes, 20:58:04–21:00:59 | 175 s | 10483 | 59.90 | 0 | 5 ms | 0 |
| Después, 21:07:51–21:08:56 | 65 s | 3895 | 59.92 | 0 | 4 ms | 0 |

Estos contadores comprueban recepción/entrega al renderizador, no una medición
externa de fotones ni una partida completa. No demuestran mejora de rendimiento;
sí acotan que el cambio de input no muestra regresión en este escenario.
Siguiente paso: captura durante gameplay con los tirones originales y confirmación
del atajo desde el mando físico. No se requiere modificar más código para ese paso.
