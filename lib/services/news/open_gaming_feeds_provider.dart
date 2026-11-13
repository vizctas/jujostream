import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/gaming_news_item.dart';

class _RssFeedSpec {
  final String sourceLabel;
  final Uri uri;

  const _RssFeedSpec(this.sourceLabel, this.uri);
}

/// Zero-auth public gaming RSS feeds and Steam storefront highlights.
class OpenGamingFeedsProvider {
  OpenGamingFeedsProvider._();

  static const Duration _timeout = Duration(seconds: 5);
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _maxPerRssFeed = 5;

  static const Map<String, String> _headers = {
    'Accept': 'application/rss+xml, application/atom+xml, application/xml, application/json',
    'User-Agent': 'JUJOStream/1.0 (Gaming News Launcher; +https://jujo.stream)',
  };

  static final List<_RssFeedSpec> _rssFeeds = [
    _RssFeedSpec('PC GAMER', Uri.parse('https://www.pcgamer.com/rss/')),
    _RssFeedSpec(
      'ROCK PAPER SHOTGUN',
      Uri.parse('https://www.rockpapershotgun.com/feed'),
    ),
    _RssFeedSpec('EUROGAMER', Uri.parse('https://www.eurogamer.net/feed/news')),
  ];

  static final Uri _steamFeaturedUri = Uri.https(
    'store.steampowered.com',
    '/api/featuredcategories',
    {'cc': 'us', 'l': 'en'},
  );

  static DateTime? _cachedRssAt;
  static List<GamingNewsItem>? _cachedRss;
  static DateTime? _cachedFeaturedAt;
  static List<GamingNewsItem>? _cachedFeatured;

  static Future<List<GamingNewsItem>> fetchOpenRssNews({
    http.Client? client,
  }) async {
    if (client == null &&
        _cachedRssAt != null &&
        _cachedRss != null &&
        DateTime.now().difference(_cachedRssAt!) < _cacheTtl) {
      return _cachedRss!;
    }

    final httpClient = client ?? http.Client();
    final closeClient = client == null;
    try {
      final batches = await Future.wait(
        _rssFeeds.map((spec) => _fetchSingleRss(spec, httpClient)),
      );
      // Interleave across publications so the NEWS row stays diverse.
      final items = <GamingNewsItem>[];
      final maxLen = batches.fold<int>(
        0,
        (best, list) => list.length > best ? list.length : best,
      );
      for (var i = 0; i < maxLen; i++) {
        for (final batch in batches) {
          if (i < batch.length) items.add(batch[i]);
        }
      }
      final result = items.toList(growable: false);
      if (client == null && result.isNotEmpty) {
        _cachedRssAt = DateTime.now();
        _cachedRss = result;
      }
      return result;
    } catch (_) {
      return const <GamingNewsItem>[];
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  static Future<List<GamingNewsItem>> _fetchSingleRss(
    _RssFeedSpec spec,
    http.Client client,
  ) async {
    try {
      final response = await client
          .get(spec.uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return const <GamingNewsItem>[];
      }
      final xml = utf8.decode(response.bodyBytes, allowMalformed: true);
      return parseRssXml(xml, sourceLabel: spec.sourceLabel);
    } catch (_) {
      return const <GamingNewsItem>[];
    }
  }

  /// Parses RSS 2.0 `<item>` or Atom `<entry>` XML into [GamingNewsType.news].
  static List<GamingNewsItem> parseRssXml(
    String xml, {
    required String sourceLabel,
  }) {
    final itemPattern = RegExp(
      r'<(item|entry)\b[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    );
    final items = <GamingNewsItem>[];
    for (final match in itemPattern.allMatches(xml)) {
      if (items.length >= _maxPerRssFeed) break;
      final block = match.group(2) ?? '';
      final title = _cleanText(_extractTag(block, 'title'));
      if (title.isEmpty) continue;

      final link = _extractLink(block);
      final rawDesc = _extractTag(block, 'description').isNotEmpty
          ? _extractTag(block, 'description')
          : (_extractTag(block, 'summary').isNotEmpty
                ? _extractTag(block, 'summary')
                : _extractTag(block, 'content:encoded'));
      final subtitle = _cleanText(rawDesc);
      final pubDateRaw = _extractTag(block, 'pubDate').isNotEmpty
          ? _extractTag(block, 'pubDate')
          : (_extractTag(block, 'published').isNotEmpty
                ? _extractTag(block, 'published')
                : _extractTag(block, 'updated'));
      final imageUrl = _extractImageUrl(block, rawDesc);
      final guid = _cleanText(_extractTag(block, 'guid'));
      final idSeed = guid.isNotEmpty ? guid : (link ?? title);

      items.add(
        GamingNewsItem(
          id: 'rss-${sourceLabel.toLowerCase().replaceAll(' ', '')}-${idSeed.hashCode}',
          type: GamingNewsType.news,
          title: title,
          subtitle: subtitle.isNotEmpty ? subtitle : sourceLabel,
          dateLabel: _formatRssDateLabel(sourceLabel, pubDateRaw),
          imageUrl: imageUrl,
          actionLabel: sourceLabel,
          sourceUrl: link,
        ),
      );
    }
    return items.toList(growable: false);
  }

  static Future<List<GamingNewsItem>> fetchSteamFeatured({
    http.Client? client,
  }) async {
    if (client == null &&
        _cachedFeaturedAt != null &&
        _cachedFeatured != null &&
        DateTime.now().difference(_cachedFeaturedAt!) < _cacheTtl) {
      return _cachedFeatured!;
    }

    final httpClient = client ?? http.Client();
    final closeClient = client == null;
    try {
      final response = await httpClient
          .get(_steamFeaturedUri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return const <GamingNewsItem>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const <GamingNewsItem>[];
      final items = parseSteamFeaturedJson(decoded);
      if (client == null && items.isNotEmpty) {
        _cachedFeaturedAt = DateTime.now();
        _cachedFeatured = items;
      }
      return items;
    } catch (_) {
      return const <GamingNewsItem>[];
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  /// Parses Steam Store `featuredcategories` JSON into update & deal items.
  static List<GamingNewsItem> parseSteamFeaturedJson(
    Map<String, dynamic> decoded,
  ) {
    final items = <GamingNewsItem>[];
    final seenUpdateIds = <int>{};
    final seenDealIds = <int>{};

    void addFeaturedBucket(String key, String badge) {
      final section = decoded[key];
      if (section is! Map<String, dynamic>) return;
      final rawItems = section['items'];
      if (rawItems is! List) return;
      for (final entry in rawItems.whereType<Map<String, dynamic>>()) {
        final appId = _asInt(entry['id']);
        final name = entry['name']?.toString().trim() ?? '';
        if (appId == null || appId <= 0 || name.isEmpty) continue;
        if (!seenUpdateIds.add(appId)) continue;
        final discount = _asInt(entry['discount_percent']) ?? 0;
        final finalPrice = _formatSteamPrice(entry['final_price'], entry['currency']);
        final subtitle = discount > 0 && finalPrice != null
            ? '$finalPrice  ·  -$discount%'
            : (finalPrice ?? 'Featured on Steam');
        items.add(
          GamingNewsItem(
            id: 'steam-featured-$key-$appId',
            type: GamingNewsType.update,
            title: name,
            subtitle: subtitle,
            dateLabel: 'STEAM · $badge',
            imageUrl: _steamEntryImage(entry, appId),
            relatedAppId: appId,
            actionLabel: 'Steam Store',
            sourceUrl: 'https://store.steampowered.com/app/$appId',
          ),
        );
        if (seenUpdateIds.length >= 10) break;
      }
    }

    addFeaturedBucket('new_releases', 'NEW RELEASE');
    addFeaturedBucket('top_sellers', 'TOP SELLER');

    final specials = decoded['specials'];
    if (specials is Map<String, dynamic> && specials['items'] is List) {
      for (final entry
          in (specials['items'] as List).whereType<Map<String, dynamic>>()) {
        final appId = _asInt(entry['id']);
        final name = entry['name']?.toString().trim() ?? '';
        final discount = _asInt(entry['discount_percent']) ?? 0;
        if (appId == null || appId <= 0 || name.isEmpty || discount <= 0) {
          continue;
        }
        if (!seenDealIds.add(appId)) continue;
        final finalPrice = _formatSteamPrice(entry['final_price'], entry['currency']);
        final originalPrice = _formatSteamPrice(
          entry['original_price'],
          entry['currency'],
        );
        final subtitle = finalPrice != null && originalPrice != null
            ? '$finalPrice  -  was $originalPrice'
            : (finalPrice ?? 'Steam Special');
        items.add(
          GamingNewsItem(
            id: 'steam-special-$appId',
            type: GamingNewsType.recommended,
            title: name,
            subtitle: subtitle,
            dateLabel: 'STEAM · -$discount%',
            imageUrl: _steamEntryImage(entry, appId),
            relatedAppId: appId,
            actionLabel: 'Steam Store',
            sourceUrl: 'https://store.steampowered.com/app/$appId',
          ),
        );
        if (seenDealIds.length >= 10) break;
      }
    }

    return items.toList(growable: false);
  }

  static String? _steamEntryImage(Map<String, dynamic> entry, int appId) {
    final large = entry['large_capsule_image']?.toString().trim();
    if (large != null && large.isNotEmpty) return large;
    final header = entry['header_image']?.toString().trim();
    if (header != null && header.isNotEmpty) return header;
    final small = entry['small_capsule_image']?.toString().trim();
    if (small != null && small.isNotEmpty) return small;
    return 'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg';
  }

  static String? _formatSteamPrice(Object? centsRaw, Object? currencyRaw) {
    final cents = _asInt(centsRaw);
    if (cents == null || cents <= 0) return null;
    final currency = currencyRaw?.toString().trim().toUpperCase();
    final prefix = currency == 'EUR' ? '€' : '\$';
    return '$prefix${(cents / 100.0).toStringAsFixed(2)}';
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static String _extractTag(String block, String tag) {
    final escaped = RegExp.escape(tag);
    final match = RegExp(
      '<$escaped(?:\\s+[^>]*)?>(.*?)</$escaped>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(block);
    return match?.group(1) ?? '';
  }

  static String? _extractLink(String block) {
    final direct = _cleanText(_extractTag(block, 'link'));
    if (direct.startsWith('http')) return direct;
    final atomMatch = RegExp(
      r'''<link[^>]+href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(block);
    final href = atomMatch?.group(1)?.trim();
    if (href != null && href.startsWith('http')) return href;
    return null;
  }

  static String? _extractImageUrl(String block, String rawDesc) {
    final mediaAttr = RegExp(
      r'''<(?:media:content|media:thumbnail|enclosure)\b[^>]*\burl=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(block);
    final mediaUrl = mediaAttr?.group(1)?.trim();
    if (mediaUrl != null && mediaUrl.startsWith('http')) return mediaUrl;

    final imgMatch = RegExp(
      r'''<img\b[^>]*\bsrc=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch('$block\n$rawDesc');
    final imgUrl = imgMatch?.group(1)?.trim();
    if (imgUrl != null && imgUrl.startsWith('http')) return imgUrl;
    return null;
  }

  static String _cleanText(String raw) {
    if (raw.isEmpty) return '';
    var text = raw;
    final cdata = RegExp(
      r'<!\[CDATA\[(.*?)\]\]>',
      dotAll: true,
    ).firstMatch(text);
    if (cdata != null) {
      text = cdata.group(1) ?? text;
    }
    return text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#8217;', "'")
        .replaceAll('&#8216;', "'")
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&#8211;', '-')
        .replaceAll('&#8212;', '—')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _formatRssDateLabel(String sourceLabel, String rawDate) {
    final clean = _cleanText(rawDate);
    if (clean.isEmpty) return sourceLabel;
    final iso = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(clean);
    if (iso != null) {
      final dateStr = iso.group(1)!;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return dateStr == today ? '$sourceLabel · TODAY' : '$sourceLabel · $dateStr';
    }
    final rfc = RegExp(
      r'\b(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})\b',
    ).firstMatch(clean);
    if (rfc != null) {
      return '$sourceLabel · ${rfc.group(1)!.toUpperCase()}';
    }
    return sourceLabel;
  }
}

