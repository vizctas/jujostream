/// What's new per client version, shown once on the first launch of that
/// version. Add an entry with every release bump (kAppVersion); a version with
/// no entry simply shows nothing.
const Map<String, ({List<String> es, List<String> en})> kChangelog = {
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
