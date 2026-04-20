import '../../l10n/app_localizations.dart';

class MacroGenreClassifier {
  MacroGenreClassifier._();

  // ── Locale-neutral internal IDs (used for matching & persistence) ─────
  static const String action = 'action';
  static const String adventure = 'adventure';
  static const String fighting = 'fighting';
  static const String platform = 'platform';
  static const String cards = 'cards';
  static const String rogue = 'rogue';
  static const String rpg = 'rpg';
  static const String strategy = 'strategy';
  static const String simulation = 'simulation';
  static const String racing = 'racing';
  static const String sports = 'sports';
  static const String puzzle = 'puzzle';
  static const String horror = 'horror';
  static const String stealth = 'stealth';

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

  /// Returns the localized display label for a genre ID.
  /// Falls back to the raw ID if no localization is available.
  static String localizedLabel(String genreId, AppLocalizations l) {
    return switch (genreId) {
      action => l.genreAction,
      adventure => l.genreAdventure,
      fighting => l.genreFighting,
      platform => l.genrePlatform,
      cards => l.genreCards,
      rogue => l.genreRogue,
      rpg => l.genreRpg,
      strategy => l.genreStrategy,
      simulation => l.genreSimulation,
      racing => l.genreRacing,
      sports => l.genreSports,
      puzzle => l.genrePuzzle,
      horror => l.genreHorror,
      stealth => l.genreStealth,
      _ => genreId,
    };
  }

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
