import 'dart:convert';
import 'package:http/http.dart' as http;

class SteamVideoClient {
  static const _searchBase =
      'https://store.steampowered.com/api/storesearch/';
  static const _appDetailsBase =
      'https://store.steampowered.com/api/appdetails';

  Future<int?> searchAppId(String gameName) async {
    try {
      final uri = Uri.parse(_searchBase).replace(queryParameters: {
        'term': gameName,
        'cc': 'US',
        'l': 'english',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;

      final norm = _normalize(gameName);
      for (final item in items) {
        final name = _normalize((item as Map<String, dynamic>)['name'] as String? ?? '');
        if (name == norm) {
          return (item['id'] as num?)?.toInt();
        }
      }

      return ((items.first as Map<String, dynamic>)['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<List<SteamMovie>> getMovies(int appId) async {
    final details = await getStoreData(appId);
    return details.movies;
  }

  Future<SteamStoreDetails> getStoreData(int appId) async {
    try {
      final uri = Uri.parse(_appDetailsBase).replace(queryParameters: {
        'appids': '$appId',
        'cc': 'US',
        'l': 'english',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const SteamStoreDetails(movies: []);

      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final appData = root['$appId'] as Map<String, dynamic>?;
      if (appData == null || appData['success'] != true) {
        return const SteamStoreDetails(movies: []);
      }

      final data = appData['data'] as Map<String, dynamic>? ?? {};

      final moviesJson = data['movies'] as List? ?? [];
      final movies = moviesJson
          .whereType<Map<String, dynamic>>()
          .map(SteamMovie.fromJson)
          .toList();

      final description = (data['short_description'] as String?)?.trim();

      final genresList = data['genres'] as List?;
      final genres = genresList == null
          ? <String>[]
          : genresList
              .whereType<Map<String, dynamic>>()
              .map((g) => g['description'] as String? ?? '')
              .where((g) => g.isNotEmpty)
              .toList();

      return SteamStoreDetails(
        movies: movies,
        description: description,
        genres: genres,
      );
    } catch (_) {
      return const SteamStoreDetails(movies: []);
    }
  }

  Future<List<SteamMovie>> lookupMovies(String gameName) async {
    final appId = await searchAppId(gameName);
    if (appId == null) return [];
    return getMovies(appId);
  }

  Future<List<SteamMovie>> lookupMoviesByAppId(int appId) => getMovies(appId);

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
}

class SteamStoreDetails {
  final List<SteamMovie> movies;
  final String? description;
  final List<String> genres;

  const SteamStoreDetails({
    required this.movies,
    this.description,
    this.genres = const [],
  });
}

class SteamMovie {
  final int id;
  final String name;
  final String? thumbnail;

  final String? mp4Sd;
  final String? mp4Hd;
  final String? webmSd;

  final String? hlsH264;
  final String? dashH264;

  const SteamMovie({
    required this.id,
    required this.name,
    this.thumbnail,
    this.mp4Sd,
    this.mp4Hd,
    this.webmSd,
    this.hlsH264,
    this.dashH264,
  });

  factory SteamMovie.fromJson(Map<String, dynamic> json) {
    final mp4  = json['mp4']  as Map<String, dynamic>? ?? {};
    final webm = json['webm'] as Map<String, dynamic>? ?? {};
    return SteamMovie(
      id:        json['id']        as int?    ?? 0,
      name:      json['name']      as String? ?? '',
      thumbnail: json['thumbnail'] as String?,

      mp4Sd:  _toHttps(mp4['480']  as String?),
      mp4Hd:  _toHttps(mp4['max']  as String?),
      webmSd: _toHttps(webm['480'] as String?),

      hlsH264:  _toHttps(json['hls_h264']  as String?),
      dashH264: _toHttps(json['dash_h264'] as String?),
    );
  }

  String? get bestUrl => mp4Sd ?? mp4Hd ?? hlsH264 ?? dashH264 ?? webmSd;

  static String? _toHttps(String? url) {
    if (url == null) return null;
    if (url.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }

  @override
  String toString() => 'SteamMovie(id: $id, name: $name, url: $bestUrl)';
}
