import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import 'open_gaming_feeds_provider.dart';

class GamingNewsService {
  GamingNewsService._();

  static final Uri _dealsUri = Uri.https(
    'www.cheapshark.com',
    '/api/1.0/deals',
    {'sortBy': 'Deal Rating', 'pageSize': '25', 'onSale': '1'},
  );
  static const List<int> _fallbackPopularSteamAppIds = [
    730,
    570,
    1245620,
    1091500,
    553850,
    1086940,
    1172470,
    2694490,
  ];
  static final Uri _giveawaysUri = Uri.https(
    'www.gamerpower.com',
    '/api/giveaways',
    {'platform': 'pc', 'sort-by': 'date'},
  );
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Map<String, String> _requestHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'JUJOStream/1.0 (game launcher)',
  };
  static DateTime? _cachedDealsAt;
  static DateTime? _cachedGiveawaysAt;
  static DateTime? _cachedSteamNewsAt;
  static List<GamingNewsItem>? _cachedDeals;
  static List<GamingNewsItem>? _cachedGiveaways;
  static List<GamingNewsItem>? _cachedSteamNews;
  static String _cachedSteamNewsKey = '';

  static List<GamingNewsItem> localItems() {
    return const <GamingNewsItem>[];
  }

  static Future<List<GamingNewsItem>> fetchDashboardItems({
    List<int> steamAppIds = const <int>[],
    List<NvApp> allApps = const <NvApp>[],
    List<NvApp> visibleApps = const <NvApp>[],
    http.Client? client,
  }) async {
    final ids = <int>{
      ...steamAppIds.where((id) => id > 0),
      ...allApps
          .followedBy(visibleApps)
          .map((app) => app.steamAppId)
          .whereType<int>()
          .where((id) => id > 0),
      ..._fallbackPopularSteamAppIds,
    }.take(12).toList(growable: false);

    final results = await Future.wait([
      OpenGamingFeedsProvider.fetchOpenRssNews(client: client),
      OpenGamingFeedsProvider.fetchSteamFeatured(client: client),
      OpenGamingFeedsProvider.fetchEpicFreeGames(client: client),
      fetchDeals(client: client),
      fetchGiveaways(client: client),
      fetchSteamNewsForApps(steamAppIds: ids, client: client),
    ]);
    return combineDashboardItems(results, maxPerType: 18, maxTotal: 75);
  }

  static List<GamingNewsItem> combineDashboardItems(
    List<List<GamingNewsItem>> sources, {
    int maxPerType = 12,
    int? maxTotal,
  }) {
    final grouped = <GamingNewsType, List<GamingNewsItem>>{
      for (final type in GamingNewsType.values) type: <GamingNewsItem>[],
    };
    final seenIds = <String>{};
    for (final item in sources.expand((items) => items)) {
      final bucket = grouped[item.type];
      if (bucket == null || bucket.length >= maxPerType) continue;
      if (seenIds.add(item.id)) {
        bucket.add(item);
      }
    }

    const order = [
      GamingNewsType.update,
      GamingNewsType.patch,
      GamingNewsType.event,
      GamingNewsType.recommended,
      GamingNewsType.news,
    ];
    final combined = <GamingNewsItem>[];
    var cursor = 0;
    while (true) {
      var added = false;
      for (final type in order) {
        final items = grouped[type]!;
        if (cursor < items.length) {
          combined.add(items[cursor]);
          added = true;
          if (maxTotal != null && combined.length >= maxTotal) {
            return combined.toList(growable: false);
          }
        }
      }
      if (!added) break;
      cursor++;
    }
    return combined.toList(growable: false);
  }

  static Future<List<GamingNewsItem>> fetchDeals({http.Client? client}) async {
    if (client == null &&
        _cachedDealsAt != null &&
        _cachedDeals != null &&
        DateTime.now().difference(_cachedDealsAt!) < _cacheTtl) {
      return _cachedDeals!;
    }

    final httpClient = client ?? http.Client();
    final closeClient = client == null;
    try {
      final response = await httpClient
          .get(_dealsUri, headers: _requestHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const <GamingNewsItem>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const <GamingNewsItem>[];
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromCheapSharkJson)
          .whereType<GamingNewsItem>()
          .take(20)
          .toList(growable: false);
      if (client == null) {
        _cachedDealsAt = DateTime.now();
        _cachedDeals = items;
      }
      return items;
    } catch (_) {
      return const <GamingNewsItem>[];
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  static Future<List<GamingNewsItem>> fetchGiveaways({
    http.Client? client,
  }) async {
    if (client == null &&
        _cachedGiveawaysAt != null &&
        _cachedGiveaways != null &&
        DateTime.now().difference(_cachedGiveawaysAt!) < _cacheTtl) {
      return _cachedGiveaways!;
    }

    final httpClient = client ?? http.Client();
    final closeClient = client == null;
    try {
      final response = await httpClient
          .get(_giveawaysUri, headers: _requestHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const <GamingNewsItem>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const <GamingNewsItem>[];
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromGamerPowerJson)
          .whereType<GamingNewsItem>()
          .take(20)
          .toList(growable: false);
      if (client == null) {
        _cachedGiveawaysAt = DateTime.now();
        _cachedGiveaways = items;
      }
      return items;
    } catch (_) {
      return const <GamingNewsItem>[];
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  static Future<List<GamingNewsItem>> fetchSteamNewsForApps({
    required List<int> steamAppIds,
    http.Client? client,
  }) async {
    final uniqueAppIds = steamAppIds
        .where((appId) => appId > 0)
        .toSet()
        .take(12)
        .toList(growable: false);
    // GetNewsForApp is public; only GetNewsForAppAuthed requires a key.
    if (uniqueAppIds.isEmpty) {
      return const <GamingNewsItem>[];
    }

    final cacheKey = uniqueAppIds.join(',');
    if (client == null &&
        _cachedSteamNewsAt != null &&
        _cachedSteamNews != null &&
        _cachedSteamNewsKey == cacheKey &&
        DateTime.now().difference(_cachedSteamNewsAt!) < _cacheTtl) {
      return _cachedSteamNews!;
    }

    final httpClient = client ?? http.Client();
    final closeClient = client == null;
    try {
      final items = <GamingNewsItem>[];
      for (final appId in uniqueAppIds) {
        final uri = Uri.https(
          'api.steampowered.com',
          '/ISteamNews/GetNewsForApp/v2/',
          {
            'appid': '$appId',
            'count': '3',
            'maxlength': '220',
            'format': 'json',
          },
        );
        final response = await httpClient
            .get(uri, headers: _requestHeaders)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) continue;
        final appNews = decoded['appnews'];
        if (appNews is! Map<String, dynamic>) continue;
        final newsItems = appNews['newsitems'];
        if (newsItems is! List) continue;
        items.addAll(
          newsItems
              .whereType<Map<String, dynamic>>()
              .map((json) => _fromSteamNewsJson(json, appId))
              .whereType<GamingNewsItem>(),
        );
      }
      final limited = items.take(24).toList(growable: false);
      if (client == null) {
        _cachedSteamNewsAt = DateTime.now();
        _cachedSteamNewsKey = cacheKey;
        _cachedSteamNews = limited;
      }
      return limited;
    } catch (_) {
      return const <GamingNewsItem>[];
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  static List<GamingNewsItem> filterByType(
    List<GamingNewsItem> items,
    GamingNewsType? type,
  ) {
    if (type == null) return items;
    return items.where((item) => item.type == type).toList(growable: false);
  }

  static GamingNewsItem? _fromCheapSharkJson(Map<String, dynamic> json) {
    final dealId = json['dealID']?.toString().trim();
    final title = json['title']?.toString().trim();
    if (dealId == null || dealId.isEmpty || title == null || title.isEmpty) {
      return null;
    }

    final salePrice = json['salePrice']?.toString().trim();
    final normalPrice = json['normalPrice']?.toString().trim();
    final savings = double.tryParse(json['savings']?.toString() ?? '');
    final isFree = salePrice == '0.00' || (savings != null && savings >= 99.5);
    final savingsLabel = isFree
        ? 'FREE · 100% OFF'
        : savings == null
        ? null
        : '${savings.round()}% OFF';
    final thumb = json['thumb']?.toString().trim();
    final steamAppId = int.tryParse(json['steamAppID']?.toString() ?? '');

    final subtitle = isFree && normalPrice != null && normalPrice.isNotEmpty
        ? 'FREE  -  was \$$normalPrice'
        : salePrice != null &&
              salePrice.isNotEmpty &&
              normalPrice != null &&
              normalPrice.isNotEmpty
        ? '\$$salePrice  -  was \$$normalPrice'
        : 'Discount available';

    return GamingNewsItem(
      id: 'cheapshark-$dealId',
      type: GamingNewsType.recommended,
      title: title,
      subtitle: subtitle,
      dateLabel: savingsLabel == null
          ? 'CHEAPSHARK'
          : 'CHEAPSHARK - $savingsLabel',
      imageUrl: thumb != null && thumb.isNotEmpty ? thumb : null,
      relatedAppId: steamAppId,
      actionLabel: 'CheapShark',
      sourceUrl: 'https://www.cheapshark.com/redirect?dealID=$dealId',
    );
  }

  static GamingNewsItem? _fromGamerPowerJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final title = json['title']?.toString().trim();
    if (id == null || id.isEmpty || title == null || title.isEmpty) {
      return null;
    }

    final platforms = json['platforms']?.toString().trim();
    final description = json['description']?.toString().trim();
    final image = json['image']?.toString().trim();
    final thumbnail = json['thumbnail']?.toString().trim();
    final published = json['published_date']?.toString().trim();

    return GamingNewsItem(
      id: 'gamerpower-$id',
      type: GamingNewsType.event,
      title: title,
      subtitle: platforms != null && platforms.isNotEmpty
          ? platforms
          : (description ?? ''),
      dateLabel: _dateLabel(published),
      imageUrl: image != null && image.isNotEmpty
          ? image
          : (thumbnail != null && thumbnail.isNotEmpty ? thumbnail : null),
      actionLabel: 'GamerPower',
      sourceUrl: json['open_giveaway_url']?.toString().trim(),
    );
  }

  static String _dateLabel(String? published) {
    if (published == null || published.isEmpty) return 'GAMERPOWER';
    final datePart = published.split(' ').first;
    return 'GAMERPOWER - $datePart';
  }

  static GamingNewsItem? _fromSteamNewsJson(
    Map<String, dynamic> json,
    int appId,
  ) {
    final gid = json['gid']?.toString().trim();
    final title = json['title']?.toString().trim();
    if (gid == null || gid.isEmpty || title == null || title.isEmpty) {
      return null;
    }

    final rawContents = json['contents']?.toString().trim() ?? '';
    final feedLabel = json['feedlabel']?.toString().trim();
    final sourceUrl = json['url']?.toString().trim();
    return GamingNewsItem(
      id: 'steam-$gid',
      type: _steamTypeForTitle(title),
      title: title,
      subtitle: _plainText(rawContents),
      dateLabel: feedLabel == null || feedLabel.isEmpty
          ? 'STEAM'
          : feedLabel.toUpperCase(),
      imageUrl:
          'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg',
      relatedAppId: appId,
      actionLabel: 'Steam',
      sourceUrl: sourceUrl != null && sourceUrl.isNotEmpty ? sourceUrl : null,
    );
  }

  static GamingNewsType _steamTypeForTitle(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('patch') || normalized.contains('hotfix')) {
      return GamingNewsType.patch;
    }
    return GamingNewsType.update;
  }

  static String _plainText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
