/// What's new per client version, shown once on the first launch of that
/// version. Add an entry with every release bump (kAppVersion); a version with
/// no entry simply shows nothing.
const Map<String, ({List<String> es, List<String> en})> kChangelog = {
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
