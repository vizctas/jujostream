/// What's new per client version, shown once on the first launch of that
/// version. Add an entry with every release bump (kAppVersion); a version with
/// no entry simply shows nothing.
const Map<String, ({List<String> es, List<String> en})> kChangelog = {
  '1.1.41': (
    es: [
      'Server Watchdog (Jujo Labs): valida CPU y RAM del servidor antes de iniciar y ofrece cerrar apps pesadas de segundo plano sin afectar el stream.',
      'Recuperación de sesión: detecta cuando un juego pausado fue cerrado en el servidor y permite iniciar una sesión nueva con un clic.',
    ],
    en: [
      'Server Watchdog (Jujo Labs): checks host CPU and RAM headroom before launch and offers to close heavy background apps without impacting the stream.',
      'Session recovery: detects when a paused game was closed on the host and lets you start a fresh session right away.',
    ],
  ),
  '1.1.40': (
    es: [
      'Más fuentes de noticias gaming, próximos lanzamientos y juegos gratis (Epic Games, Steam, CheapShark e IGN/GameSpot/Gematsu).',
      'Secciones con fondo transparente para mantener visible el artwork o video preview del juego seleccionado.',
      'Mejor navegación con mando dentro del lector de noticias, el menú de Modo Focus y la pantalla Acerca de.',
    ],
    en: [
      'Expanded gaming news, upcoming releases, and free game sources (Epic Games, Steam, CheapShark, IGN/GameSpot/Gematsu).',
      'Transparent shelf backdrop so selected game artwork or video preview remains visible.',
      'Improved controller navigation in the news reader dialog, Focus Mode menu, and About screen.',
    ],
  ),
  '1.1.39': (
    es: [
      'Secciones apiladas de noticias, actualizaciones, eventos, parches y ofertas en todos los temas con lector integrado.',
      'Barra de categorías limpia y centrada en Classic.',
    ],
    en: [
      'Stacked gaming news, updates, events, patch notes, and deals shelves across all themes with a built-in reader.',
      'Clean centered category strip in Classic mode.',
    ],
  ),
  '1.1.38': (
    es: [
      'Opciones globales y overrides independientes por servidor.',
    ],
    en: [
      'Global options with independent per-server overrides.',
    ],
  ),
  '1.1.35': (
    es: [
      'JUJO Cloud: los servidores que otras cuentas comparten contigo '
          'aparecen y se emparejan solos tras aceptar la invitación.',
    ],
    en: [
      'JUJO Cloud: servers other accounts share with you appear and pair '
          'automatically once you accept the invite.',
    ],
  ),
  '1.1.34': (
    es: [
      'Android TV (MiBox y similares): los juegos vuelven a detectar el '
          'mando; un dispositivo virtual del sistema ocupaba el jugador 1.',
      'Corregido un fallo que podía impedir iniciar el stream tras '
          'sincronizar con la nube.',
    ],
    en: [
      'Android TV (MiBox and similar): games detect the controller again; '
          'a system virtual device was taking player 1.',
      'Fixed a failure that could stop streams from starting after a '
          'cloud sync.',
    ],
  ),
  '1.1.33': (
    es: [
      'El porcentaje de frames perdidos del overlay ya no muestra picos '
          'falsos: se mide sobre los últimos 5 segundos.',
      'La recuperación del decodificador detecta mejor un video congelado.',
      'Android 11: corregido un posible cierre al ajustar la tasa de '
          'refresco.',
    ],
    en: [
      'The overlay drop percentage no longer shows false spikes: it is '
          'measured over the last 5 seconds.',
      'Decoder recovery detects a frozen picture more reliably.',
      'Android 11: fixed a possible crash when setting the refresh rate.',
    ],
  ),
  '1.1.32': (
    es: [
      'Ajustes: tema y color se eligen en una lista simple, más fácil con '
          'el mando o el control remoto.',
      'Big Screen y noticias funcionan sin conectar Steam ni API key.',
    ],
    en: [
      'Settings: theme and colour are picked from a simple list, easier '
          'with a controller or remote.',
      'Big Screen and news work without connecting Steam or an API key.',
    ],
  ),
  '1.1.31': (
    es: [
      'TV con Android 14 (Xiaomi MiBox y similares): la vibración del mando '
          'queda desactivada porque podía reiniciar el dispositivo en plena '
          'partida, como pasaba en Chromecast HD.',
    ],
    en: [
      'Android 14 TVs (Xiaomi MiBox and similar): controller rumble is off '
          'because it could restart the device mid-game, as on Chromecast HD.',
    ],
  ),
  '1.1.30': (
    es: [
      'Chromecast HD: se corrige el cierre inesperado del stream al jugar '
          'con mando; ahí la vibración del mando queda desactivada porque '
          'reiniciaba el Chromecast.',
      'Vibración del mando más eficiente en el resto de dispositivos.',
    ],
    en: [
      'Chromecast HD: fixed the stream closing unexpectedly while playing '
          'with a controller; controller rumble is off there because it '
          'restarted the Chromecast.',
      'More efficient controller rumble on every other device.',
    ],
  ),
  '1.1.29': (
    es: [
      'Jujo Cloud en teléfonos: al tocar Email o Contraseña ahora se marca '
          'el campo correcto y se escribe en él.',
    ],
    en: [
      'Jujo Cloud on phones: tapping Email or Password now highlights that '
          'field and types into it.',
    ],
  ),
  '1.1.28': (
    es: [
      'DualSense / DualShock 4: el botón del touchpad ahora llega al juego '
          'como touchpad del mando; antes movía el ratón del PC.',
    ],
    en: [
      'DualSense / DualShock 4: the touchpad button now reaches the game as '
          "the controller's touchpad; before, it moved the PC mouse.",
    ],
  ),
  '1.1.27': (
    es: [
      'Posters: ahora cargan todos los juegos de la librería; antes se '
          'quedaban grises a partir del juego ~30.',
      'Registro de estadísticas del stream para diagnosticar fluidez.',
    ],
    en: [
      'Posters: every game in the library now loads; before, tiles past '
          'the ~30th stayed grey.',
      'Stream statistics logging to diagnose smoothness.',
    ],
  ),
  '1.1.26': (
    es: [
      'Posters: se corrige que muchos juegos no mostraran su poster aunque '
          'Admin sí lo tuviera (requiere Server 1.0.35).',
      'El detalle de juego usa letras más pequeñas en TV 1080p.',
      'Nuevo: la app avisa cuando hay una versión nueva y la instala si '
          'aceptas.',
      'Nuevo: este resumen de cambios aparece al abrir cada versión nueva.',
    ],
    en: [
      'Posters: fixed many games showing no poster even though Admin had '
          'one (requires Server 1.0.35).',
      'The game detail card uses smaller type on 1080p TVs.',
      'New: the app tells you when a new version is out and installs it if '
          'you accept.',
      'New: this summary of changes appears on the first launch of each '
          'version.',
    ],
  ),
};
