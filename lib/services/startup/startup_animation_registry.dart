import 'package:flutter/widgets.dart';

import '../../screens/cinematic_intro/cinematic_intro_screen.dart';

typedef StartupAnimationBuilder =
    Widget Function({
      required VoidCallback onComplete,
      required bool reducedMotion,
    });

class StartupAnimationDefinition {
  const StartupAnimationDefinition({
    required this.id,
    required this.labelEn,
    required this.labelEs,
    required this.descriptionEn,
    required this.descriptionEs,
    this.builder,
  });

  final String id;
  final String labelEn;
  final String labelEs;
  final String descriptionEn;
  final String descriptionEs;
  final StartupAnimationBuilder? builder;

  bool get buildsScreen => builder != null;

  String labelFor(Locale locale) =>
      locale.languageCode == 'es' ? labelEs : labelEn;

  String descriptionFor(Locale locale) =>
      locale.languageCode == 'es' ? descriptionEs : descriptionEn;
}

class StartupAnimationRegistry {
  static const cinematicV1Id = 'cinematicV1';
  static const offId = 'off';

  static final List<StartupAnimationDefinition> entries = List.unmodifiable([
    StartupAnimationDefinition(
      id: cinematicV1Id,
      labelEn: 'Cinematic',
      labelEs: 'Cinemática',
      descriptionEn: 'Play the JUJO Stream opening sequence on cold start.',
      descriptionEs:
          'Reproduce la secuencia de apertura de JUJO Stream al iniciar.',
      builder: ({required onComplete, required reducedMotion}) {
        return CinematicIntroScreen(
          onComplete: onComplete,
          reducedMotion: reducedMotion,
        );
      },
    ),
    const StartupAnimationDefinition(
      id: offId,
      labelEn: 'Off',
      labelEs: 'Desactivada',
      descriptionEn: 'Open the launcher immediately.',
      descriptionEs: 'Abre el inicio inmediatamente.',
    ),
  ]);

  static StartupAnimationDefinition resolve(String? id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return entries.firstWhere((entry) => entry.id == cinematicV1Id);
  }

  static bool supports(String id) => entries.any((entry) => entry.id == id);
}
