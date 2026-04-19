import 'package:shared_preferences/shared_preferences.dart';

class Achievement {
  final String id;
  final String title;
  final String titleEn;
  final String description;
  final String descriptionEn;
  final String emoji;
  final int points;

  final String difficulty;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const Achievement({
    required this.id,
    required this.title,
    this.titleEn = '',
    required this.description,
    this.descriptionEn = '',
    required this.emoji,
    required this.points,
    required this.difficulty,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  String localizedTitle(String locale) =>
      locale == 'en' && titleEn.isNotEmpty ? titleEn : title;

  String localizedDescription(String locale) =>
      locale == 'en' && descriptionEn.isNotEmpty ? descriptionEn : description;

  Achievement copyWith({bool? isUnlocked, DateTime? unlockedAt}) {
    return Achievement(
      id: id,
      title: title,
      titleEn: titleEn,
      description: description,
      descriptionEn: descriptionEn,
      emoji: emoji,
      points: points,
      difficulty: difficulty,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }
}

class AchievementService {
  AchievementService._();
  static final AchievementService instance = AchievementService._();

  static const List<Achievement> _definitions = [

    Achievement(
      id: 'first_connection',
      title: 'Primera Conexión',
      titleEn: 'First Connection',
      description: 'Empareja tu primer servidor con JUJO',
      descriptionEn: 'Pair your first server with JUJO',
      emoji: '🎮',
      points: 10,
      difficulty: 'easy',
    ),
    Achievement(
      id: 'first_launch',
      title: 'Despegue',
      titleEn: 'Liftoff',
      description: 'Lanza un juego por primera vez',
      descriptionEn: 'Launch a game for the first time',
      emoji: '🚀',
      points: 15,
      difficulty: 'easy',
    ),
    Achievement(
      id: 'playtime_30min',
      title: 'Media Hora',
      titleEn: 'Half Hour',
      description: 'Acumula 30 minutos de juego',
      descriptionEn: 'Accumulate 30 minutes of playtime',
      emoji: '⏱️',
      points: 20,
      difficulty: 'easy',
    ),
    Achievement(
      id: 'first_favorite',
      title: 'Apuntado',
      titleEn: 'Bookmarked',
      description: 'Marca tu primer juego como favorito',
      descriptionEn: 'Mark your first game as a favorite',
      emoji: '🎯',
      points: 20,
      difficulty: 'easy',
    ),
    Achievement(
      id: 'changed_theme',
      title: 'Diseñador',
      titleEn: 'Designer',
      description: 'Personaliza el tema de la aplicación',
      descriptionEn: 'Customize the app theme',
      emoji: '🎨',
      points: 15,
      difficulty: 'easy',
    ),

    Achievement(
      id: 'playtime_5h',
      title: 'En Llamas',
      titleEn: 'On Fire',
      description: 'Acumula 5 horas de juego en total',
      descriptionEn: 'Accumulate 5 hours of total playtime',
      emoji: '🔥',
      points: 30,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'first_collection',
      title: 'Coleccionista',
      titleEn: 'Collector',
      description: 'Crea tu primera colección de juegos',
      descriptionEn: 'Create your first game collection',
      emoji: '🗂️',
      points: 25,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'night_player',
      title: 'Madrugador',
      titleEn: 'Night Owl',
      description: 'Juega una sesión después de la medianoche',
      descriptionEn: 'Play a session past midnight',
      emoji: '👾',
      points: 30,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'games_10',
      title: 'Diamante',
      titleEn: 'Diamond',
      description: 'Juega 10 juegos distintos',
      descriptionEn: 'Play 10 different games',
      emoji: '💎',
      points: 40,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'playtime_25h',
      title: 'Campeón',
      titleEn: 'Champion',
      description: 'Acumula 25 horas de juego en total',
      descriptionEn: 'Accumulate 25 hours of total playtime',
      emoji: '🏆',
      points: 50,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'wan_connect',
      title: 'Globetrotter',
      titleEn: 'Globetrotter',
      description: 'Conéctate a un servidor mediante WAN o VPN',
      descriptionEn: 'Connect to a server via WAN or VPN',
      emoji: '🌐',
      points: 35,
      difficulty: 'medium',
    ),
    Achievement(
      id: 'auto_reconnect',
      title: 'Reconexión',
      titleEn: 'Reconnected',
      description: 'Reconéctate automáticamente durante una sesión',
      descriptionEn: 'Auto-reconnect during a session',
      emoji: '🔄',
      points: 25,
      difficulty: 'medium',
    ),

    Achievement(
      id: 'screenshot',
      title: 'Captura',
      titleEn: 'Snapshot',
      description: 'Toma una captura de pantalla durante el stream',
      descriptionEn: 'Take a screenshot during a stream',
      emoji: '📸',
      points: 25,
      difficulty: 'hard',
    ),
    Achievement(
      id: 'collection_5games',
      title: 'Colección Épica',
      titleEn: 'Epic Collection',
      description: 'Añade 5 juegos a una misma colección',
      descriptionEn: 'Add 5 games to a single collection',
      emoji: '🎭',
      points: 40,
      difficulty: 'hard',
    ),
    Achievement(
      id: 'favorites_10',
      title: 'Estrella',
      titleEn: 'Star',
      description: 'Marca 10 juegos distintos como favoritos',
      descriptionEn: 'Mark 10 different games as favorites',
      emoji: '⭐',
      points: 45,
      difficulty: 'hard',
    ),
    Achievement(
      id: 'playtime_50h',
      title: 'Veterano',
      titleEn: 'Veteran',
      description: 'Acumula 50 horas de juego en total',
      descriptionEn: 'Accumulate 50 hours of total playtime',
      emoji: '🏅',
      points: 70,
      difficulty: 'hard',
    ),
    Achievement(
      id: 'pip_mode',
      title: 'Cineasta',
      titleEn: 'Filmmaker',
      description: 'Usa el modo Picture-in-Picture durante un stream',
      descriptionEn: 'Use Picture-in-Picture mode during a stream',
      emoji: '🎬',
      points: 35,
      difficulty: 'hard',
    ),
    Achievement(
      id: 'night_sessions_10',
      title: 'Noctámbulo',
      titleEn: 'Night Owl Pro',
      description: 'Completa 10 sesiones nocturnas después de la medianoche',
      descriptionEn: 'Complete 10 night sessions past midnight',
      emoji: '🌙',
      points: 55,
      difficulty: 'hard',
    ),

    Achievement(
      id: 'playtime_100h',
      title: 'Maestro',
      titleEn: 'Master',
      description: 'Acumula 100 horas de juego en total',
      descriptionEn: 'Accumulate 100 hours of total playtime',
      emoji: '🔮',
      points: 100,
      difficulty: 'legendary',
    ),
    Achievement(
      id: 'legend',
      title: 'Leyenda',
      titleEn: 'Legend',
      description: '200+ horas, 20+ juegos distintos y todos los logros anteriores',
      descriptionEn: '200+ hours, 20+ different games & all previous achievements',
      emoji: '👑',
      points: 200,
      difficulty: 'legendary',
    ),
  ];

  List<Achievement> _current = List.from(_definitions);

  List<Achievement> get achievements => List.unmodifiable(_current);

  int get totalPoints =>
      _current.where((a) => a.isUnlocked).fold(0, (sum, a) => sum + a.points);

  int get maxPoints =>
      _definitions.fold(0, (sum, a) => sum + a.points);

  int get unlockedCount => _current.where((a) => a.isUnlocked).length;

  Future<void> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    _current = _definitions.map((def) {
      final ms = prefs.getInt('achievement_unlocked_${def.id}');
      if (ms != null) {
        return def.copyWith(
          isUnlocked: true,
          unlockedAt: DateTime.fromMillisecondsSinceEpoch(ms),
        );
      }
      return def;
    }).toList();
  }

  Future<bool> unlock(String id) async {
    final idx = _current.indexWhere((a) => a.id == id);
    if (idx < 0 || _current[idx].isUnlocked) return false;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('achievement_unlocked_$id', now.millisecondsSinceEpoch);
    _current = List.from(_current)
      ..[idx] = _current[idx].copyWith(isUnlocked: true, unlockedAt: now);
    return true;
  }

  Future<List<Achievement>> checkStatsAchievements({
    required int totalPlaytimeSec,
    required int distinctGamesCount,
  }) async {
    final unlocked = <Achievement>[];

    final checks = <(String, bool)>[
      ('playtime_30min', totalPlaytimeSec >= 30 * 60),
      ('playtime_5h', totalPlaytimeSec >= 5 * 3600),
      ('playtime_25h', totalPlaytimeSec >= 25 * 3600),
      ('playtime_50h', totalPlaytimeSec >= 50 * 3600),
      ('playtime_100h', totalPlaytimeSec >= 100 * 3600),
      ('games_10', distinctGamesCount >= 10),
    ];

    for (final (id, condition) in checks) {
      if (condition && await unlock(id)) {
        unlocked.add(_current.firstWhere((a) => a.id == id));
      }
    }

    final allOthersUnlocked =
        _current.where((a) => a.id != 'legend').every((a) => a.isUnlocked);
    if (allOthersUnlocked &&
        distinctGamesCount >= 20 &&
        totalPlaytimeSec >= 200 * 3600) {
      if (await unlock('legend')) {
        unlocked.add(_current.firstWhere((a) => a.id == 'legend'));
      }
    }

    return unlocked;
  }
}
