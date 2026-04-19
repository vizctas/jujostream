import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeTrailerResult {
  final String videoId;
  final String title;
  final String? thumbnailUrl;
  final String? channelTitle;

  const YouTubeTrailerResult({
    required this.videoId,
    required this.title,
    this.thumbnailUrl,
    this.channelTitle,
  });

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  String get embedUrl => 'https://www.youtube.com/embed/$videoId?autoplay=1&rel=0';

  factory YouTubeTrailerResult.fromSearchItem(Map<String, dynamic> item) {
    final id = item['id'] as Map<String, dynamic>? ?? {};
    final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    final high = thumbs['high'] as Map<String, dynamic>?;
    final medium = thumbs['medium'] as Map<String, dynamic>?;
    final def = thumbs['default'] as Map<String, dynamic>?;
    return YouTubeTrailerResult(
      videoId: id['videoId'] as String? ?? '',
      title: snippet['title'] as String? ?? '',
      thumbnailUrl: (high?['url'] ?? medium?['url'] ?? def?['url']) as String?,
      channelTitle: snippet['channelTitle'] as String?,
    );
  }
}

class YouTubeTrailerService {
  static const _searchBase = 'https://www.googleapis.com/youtube/v3/search';

  const YouTubeTrailerService();

  Future<List<YouTubeTrailerResult>?> searchTrailer({
    required String apiKey,
    required String gameName,
    int maxResults = 5,
  }) async {
    if (apiKey.isEmpty || gameName.isEmpty) return null;
    try {
      final uri = Uri.parse(_searchBase).replace(queryParameters: {
        'part': 'snippet',
        'q': '$gameName official trailer',
        'type': 'video',
        'maxResults': '$maxResults',
        'order': 'relevance',
        'videoEmbeddable': 'true',
        'key': apiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final items = root['items'] as List? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(YouTubeTrailerResult.fromSearchItem)
          .where((r) => r.videoId.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<YouTubeTrailerResult?> bestTrailer({
    required String apiKey,
    required String gameName,
  }) async {
    final results = await searchTrailer(
      apiKey: apiKey,
      gameName: gameName,
      maxResults: 1,
    );
    return results?.isNotEmpty == true ? results!.first : null;
  }
}
