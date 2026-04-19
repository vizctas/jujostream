import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class RawgClient {
  static const _base = 'https://api.rawg.io/api';

  Future<RawgGameBrief?> searchGame(String name, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/games').replace(queryParameters: {
        'key': apiKey,
        'search': name,
        'page_size': '1',
        'search_exact': 'true',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      return RawgGameBrief.fromJson(results.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<RawgGameDetail?> getGameDetail(int id, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/games/$id').replace(queryParameters: {
        'key': apiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return RawgGameDetail.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<RawgGameDetail?> lookupGame(String name, String apiKey) async {
    final brief = await searchGame(name, apiKey);
    if (brief == null) return null;
    return getGameDetail(brief.id, apiKey);
  }
}

class RawgGameBrief {
  final int id;
  final String name;
  final double? rating;
  final String? backgroundImage;
  final String? clipUrl;
  final List<String> genres;
  final String? released;

  const RawgGameBrief({
    required this.id,
    required this.name,
    this.rating,
    this.backgroundImage,
    this.clipUrl,
    required this.genres,
    this.released,
  });

  factory RawgGameBrief.fromJson(Map<String, dynamic> json) {
    final genreList = (json['genres'] as List?)
            ?.map((g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    return RawgGameBrief(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      backgroundImage: json['background_image'] as String?,
      clipUrl: (json['clip'] as Map<String, dynamic>?)?['clip'] as String?,
      genres: genreList,
      released: json['released'] as String?,
    );
  }
}

class RawgGameDetail extends RawgGameBrief {
  final String? descriptionRaw;
  final int? metacritic;

  const RawgGameDetail({
    required super.id,
    required super.name,
    super.rating,
    super.backgroundImage,
    super.clipUrl,
    required super.genres,
    super.released,
    this.descriptionRaw,
    this.metacritic,
  });

  factory RawgGameDetail.fromJson(Map<String, dynamic> json) {
    final brief = RawgGameBrief.fromJson(json);
    return RawgGameDetail(
      id: brief.id,
      name: brief.name,
      rating: brief.rating,
      backgroundImage: brief.backgroundImage,
      clipUrl: brief.clipUrl,
      genres: brief.genres,
      released: brief.released,
      descriptionRaw: json['description_raw'] as String?,
      metacritic: json['metacritic'] as int?,
    );
  }
}
