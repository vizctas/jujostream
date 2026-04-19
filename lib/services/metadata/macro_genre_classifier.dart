class MacroGenreClassifier {
  MacroGenreClassifier._();

  static const String action = 'Accion';
  static const String adventure = 'Aventura';
  static const String fighting = 'Pelea';
  static const String platform = 'Plataforma';
  static const String cards = 'Cartas';
  static const String rogue = 'Rogue';
  static const String rpg = 'RPG';
  static const String strategy = 'Estrategia';
  static const String simulation = 'Simulacion';
  static const String racing = 'Carreras';
  static const String sports = 'Deportes';
  static const String puzzle = 'Puzzle';
  static const String horror = 'Horror';
  static const String stealth = 'Stealth';

  static const List<String> displayOrder = [
    action,
    adventure,
    rpg,
    rogue,
    fighting,
    platform,
    strategy,
    simulation,
    racing,
    sports,
    cards,
    puzzle,
    horror,
    stealth,
  ];

  static const Map<String, List<String>> _keywords = {
    action: [
      'action',
      'shooter',
      'shoot',
      'hack and slash',
      'hack & slash',
      'brawler',
      'beat em up',
      'beat\'em up',
      'arcade',
    ],
    adventure: [
      'adventure',
      'narrative',
      'story rich',
      'interactive fiction',
      'exploration',
      'walking simulator',
    ],
    fighting: [
      'fighting',
      'fighter',
      'martial arts',
      'versus',
      'combat arena',
    ],
    platform: [
      'platform',
      'platformer',
      'metroidvania',
      'side scroller',
      'side-scroller',
      'precision platformer',
    ],
    cards: [
      'card',
      'cards',
      'deckbuilder',
      'deck-building',
      'board game',
      'board',
      'tabletop',
    ],
    rogue: [
      'rogue',
      'roguelike',
      'rogue-lite',
      'roguelite',
      'procedural',
    ],
    rpg: [
      'rpg',
      'jrpg',
      'action rpg',
      'arpg',
      'role-playing',
      'role playing',
      'turn-based rpg',
      'dungeon crawler',
      'mmorpg',
    ],
    strategy: [
      'strategy',
      'tactics',
      'tactical',
      'tower defense',
      '4x',
      'rts',
      'real-time strategy',
      'turn-based strategy',
      'grand strategy',
    ],
    simulation: [
      'simulation',
      'simulator',
      'city builder',
      'management',
      'tycoon',
      'builder',
      'sandbox',
      'farming',
      'life sim',
      'survival',
    ],
    racing: [
      'racing',
      'race',
      'driving',
      'drift',
      'kart',
      'vehicular',
    ],
    sports: [
      'sports',
      'sport',
      'soccer',
      'football',
      'basketball',
      'baseball',
      'golf',
      'tennis',
      'skate',
      'wrestling',
    ],
    puzzle: [
      'puzzle',
      'logic',
      'match 3',
      'match-3',
      'hidden object',
      'word game',
    ],
    horror: [
      'horror',
      'survival horror',
      'psychological horror',
    ],
    stealth: [
      'stealth',
      'infiltration',
      'assassin',
    ],
  };

  static List<String> classify(Iterable<String> genres) {
    final normalized = genres
        .map((genre) => genre.toLowerCase().trim())
        .where((genre) => genre.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return const [];

    final matches = <String>{};
    for (final entry in _keywords.entries) {
      final macroGenre = entry.key;
      final keywords = entry.value;
      final found = normalized.any((genre) =>
          keywords.any((keyword) => genre.contains(keyword)));
      if (found) {
        matches.add(macroGenre);
      }
    }

    if (matches.isEmpty) return const [];
    return displayOrder.where(matches.contains).toList(growable: false);
  }
}
