import 'dart:convert';
import 'package:http/http.dart' as http;

class SteamOwnedGame {
  final int appId;
  final String? name;
  final int playtimeMinutes;
  final int playtimeRecentMinutes;
  final String? iconUrl;

  const SteamOwnedGame({
    required this.appId,
    this.name,
    this.playtimeMinutes = 0,
    this.playtimeRecentMinutes = 0,
    this.iconUrl,
  });

  String get playtimeLabel {
    if (playtimeMinutes <= 0) return '';
    if (playtimeMinutes < 60) return '${playtimeMinutes}m';
    final h = playtimeMinutes ~/ 60;
    final m = playtimeMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  factory SteamOwnedGame.fromJson(Map<String, dynamic> json) {
    final appId = (json['appid'] as num?)?.toInt() ?? 0;
    final icon = json['img_icon_url'] as String?;
    return SteamOwnedGame(
      appId: appId,
      name: json['name'] as String?,
      playtimeMinutes: (json['playtime_forever'] as num?)?.toInt() ?? 0,
      playtimeRecentMinutes: (json['playtime_2weeks'] as num?)?.toInt() ?? 0,
      iconUrl: icon != null && icon.isNotEmpty
          ? 'https://media.steampowered.com/steamcommunity/public/images/apps/$appId/$icon.jpg'
          : null,
    );
  }
}

class SteamGameStoreInfo {
  final String? shortDescription;
  final List<String> genres;
  final List<String> categories;
  final int? metacriticScore;
  final String? metacriticUrl;
  final String? releaseDate;
  final List<String> developers;
  final List<String> publishers;
  final int? reviewScore;
  final String? reviewDescription;
  final int? totalReviews;
  final int? positiveReviews;

  const SteamGameStoreInfo({
    this.shortDescription,
    this.genres = const [],
    this.categories = const [],
    this.metacriticScore,
    this.metacriticUrl,
    this.releaseDate,
    this.developers = const [],
    this.publishers = const [],
    this.reviewScore,
    this.reviewDescription,
    this.totalReviews,
    this.positiveReviews,
  });

  double? get positivePercent =>
      totalReviews != null && totalReviews! > 0 && positiveReviews != null
          ? positiveReviews! / totalReviews!
          : null;
}

class SteamLibraryService {
  static const _base = 'https://api.steampowered.com';
  static const _storeBase = 'https://store.steampowered.com/api';
  static const _reviewBase = 'https://store.steampowered.com/appreviews';

  const SteamLibraryService();

  Future<List<SteamOwnedGame>?> getOwnedGames({
    required String apiKey,
    required String steamId,
  }) async {
    if (apiKey.isEmpty || steamId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/IPlayerService/GetOwnedGames/v1/')
          .replace(queryParameters: {
        'key': apiKey,
        'steamid': steamId,
        'include_appinfo': '1',
        'include_played_free_games': '1',
        'format': 'json',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final resp = root['response'] as Map<String, dynamic>?;
      if (resp == null) return null;
      final games = resp['games'] as List? ?? [];
      return games
          .whereType<Map<String, dynamic>>()
          .map(SteamOwnedGame.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<SteamOwnedGame?> getOwnedGame({
    required String apiKey,
    required String steamId,
    required int appId,
  }) async {
    final games = await getOwnedGames(apiKey: apiKey, steamId: steamId);
    if (games == null) return null;
    try {
      return games.firstWhere((g) => g.appId == appId);
    } catch (_) {
      return null;
    }
  }

  Future<List<SteamOwnedGame>?> getRecentlyPlayed({
    required String apiKey,
    required String steamId,
    int count = 10,
  }) async {
    if (apiKey.isEmpty || steamId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/IPlayerService/GetRecentlyPlayedGames/v1/')
          .replace(queryParameters: {
        'key': apiKey,
        'steamid': steamId,
        'count': '$count',
        'format': 'json',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final resp = root['response'] as Map<String, dynamic>?;
      if (resp == null) return null;
      final games = resp['games'] as List? ?? [];
      return games
          .whereType<Map<String, dynamic>>()
          .map(SteamOwnedGame.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<SteamGameStoreInfo?> getStoreInfo(int appId) async {
    try {
      final uri = Uri.parse(_storeBase).replace(
        path: '/api/appdetails',
        queryParameters: {
          'appids': '$appId',
          'cc': 'US',
          'l': 'english',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final entry = root['$appId'] as Map<String, dynamic>?;
      if (entry == null || entry['success'] != true) return null;
      final data = entry['data'] as Map<String, dynamic>? ?? {};

      final genresList = data['genres'] as List?;
      final genres = genresList
              ?.whereType<Map<String, dynamic>>()
              .map((g) => g['description'] as String? ?? '')
              .where((g) => g.isNotEmpty)
              .toList() ??
          [];

      final catsList = data['categories'] as List?;
      final categories = catsList
              ?.whereType<Map<String, dynamic>>()
              .map((c) => c['description'] as String? ?? '')
              .where((c) => c.isNotEmpty)
              .toList() ??
          [];

      final meta = data['metacritic'] as Map<String, dynamic>?;
      final release = data['release_date'] as Map<String, dynamic>?;
      final devs = (data['developers'] as List?)?.whereType<String>().toList() ?? [];
      final pubs = (data['publishers'] as List?)?.whereType<String>().toList() ?? [];

      final reviews = await _fetchReviews(appId);

      return SteamGameStoreInfo(
        shortDescription: (data['short_description'] as String?)?.trim(),
        genres: genres,
        categories: categories,
        metacriticScore: (meta?['score'] as num?)?.toInt(),
        metacriticUrl: meta?['url'] as String?,
        releaseDate: release?['date'] as String?,
        developers: devs,
        publishers: pubs,
        reviewScore: reviews?.$1,
        reviewDescription: reviews?.$2,
        totalReviews: reviews?.$3,
        positiveReviews: reviews?.$4,
      );
    } catch (_) {
      return null;
    }
  }

  Future<(int, String, int, int)?> _fetchReviews(int appId) async {
    try {
      final uri = Uri.parse('$_reviewBase/$appId')
          .replace(queryParameters: {
        'json': '1',
        'language': 'all',
        'purchase_type': 'all',
        'review_type': 'all',
        'num_per_page': '0',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final summary = root['query_summary'] as Map<String, dynamic>?;
      if (summary == null) return null;
      return (
        (summary['review_score'] as num?)?.toInt() ?? 0,
        summary['review_score_desc'] as String? ?? '',
        (summary['total_reviews'] as num?)?.toInt() ?? 0,
        (summary['total_positive'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
