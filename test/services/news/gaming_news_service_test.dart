import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/models/gaming_news_item.dart';
import 'package:jujostream/services/news/gaming_news_service.dart';
import 'package:jujostream/services/news/open_gaming_feeds_provider.dart';

void main() {
  group('GamingNewsService', () {
    test('local items start empty so UI can show skeleton without data', () {
      final items = GamingNewsService.localItems();

      expect(items, isEmpty);
    });

    test('filters items by type and keeps all items for null type', () {
      const items = [
        GamingNewsItem(
          id: '1',
          type: GamingNewsType.event,
          title: 'Event',
          subtitle: 'Event subtitle',
          dateLabel: 'TODAY',
        ),
        GamingNewsItem(
          id: '2',
          type: GamingNewsType.recommended,
          title: 'Recommended',
          subtitle: 'Recommended subtitle',
          dateLabel: 'TODAY',
        ),
      ];

      expect(GamingNewsService.filterByType(items, null), items);
      final updates = GamingNewsService.filterByType(
        items,
        GamingNewsType.event,
      );

      expect(updates, isNotEmpty);
      expect(
        updates.every((item) => item.type == GamingNewsType.event),
        isTrue,
      );
    });

    test(
      'combineDashboardItems interleaves updates events patches and deals',
      () {
        const updates = [
          GamingNewsItem(
            id: 'update',
            type: GamingNewsType.update,
            title: 'Update',
            subtitle: '',
            dateLabel: '',
          ),
        ];
        const events = [
          GamingNewsItem(
            id: 'event',
            type: GamingNewsType.event,
            title: 'Event',
            subtitle: '',
            dateLabel: '',
          ),
        ];
        const patches = [
          GamingNewsItem(
            id: 'patch',
            type: GamingNewsType.patch,
            title: 'Patch',
            subtitle: '',
            dateLabel: '',
          ),
        ];
        const deals = [
          GamingNewsItem(
            id: 'deal',
            type: GamingNewsType.recommended,
            title: 'Deal',
            subtitle: '',
            dateLabel: '',
          ),
        ];

        final items = GamingNewsService.combineDashboardItems([
          deals,
          events,
          updates,
          patches,
        ]);

        expect(items.map((item) => item.type), [
          GamingNewsType.update,
          GamingNewsType.patch,
          GamingNewsType.event,
          GamingNewsType.recommended,
        ]);
      },
    );

    test('fetchGiveaways maps GamerPower response to event cards', () async {
      final client = _FakeClient(
        http.Response(
          jsonEncode([
            {
              'id': 3608,
              'title': 'Typers Combat Giveaway',
              'description': 'Grab this PC giveaway.',
              'image': 'https://example.com/image.jpg',
              'thumbnail': 'https://example.com/thumb.jpg',
              'published_date': '2026-04-27 16:56:38',
              'type': 'Game',
              'platforms': 'PC, Epic Games Store',
              'open_giveaway_url': 'https://example.com/open',
            },
          ]),
          200,
        ),
      );

      final items = await GamingNewsService.fetchGiveaways(client: client);

      expect(items, hasLength(1));
      expect(items.single.id, 'gamerpower-3608');
      expect(items.single.type, GamingNewsType.event);
      expect(items.single.title, 'Typers Combat Giveaway');
      expect(items.single.subtitle, 'PC, Epic Games Store');
      expect(items.single.imageUrl, 'https://example.com/image.jpg');
      expect(items.single.actionLabel, 'GamerPower');
    });

    test(
      'fetchDeals maps CheapShark response to recommended discount cards',
      () async {
        final client = _FakeClient(
          http.Response(
            jsonEncode([
              {
                'dealID': 'abc123',
                'title': 'Portal 2',
                'salePrice': '1.99',
                'normalPrice': '9.99',
                'savings': '80.0500',
                'thumb': 'https://example.com/portal.jpg',
                'steamAppID': '620',
              },
            ]),
            200,
          ),
        );

        final items = await GamingNewsService.fetchDeals(client: client);

        expect(items, hasLength(1));
        expect(items.single.id, 'cheapshark-abc123');
        expect(items.single.type, GamingNewsType.recommended);
        expect(items.single.title, 'Portal 2');
        expect(items.single.subtitle, r'$1.99  -  was $9.99');
        expect(items.single.dateLabel, 'CHEAPSHARK - 80% OFF');
        expect(items.single.imageUrl, 'https://example.com/portal.jpg');
        expect(items.single.relatedAppId, 620);
        expect(items.single.actionLabel, 'CheapShark');
        expect(
          items.single.sourceUrl,
          'https://www.cheapshark.com/redirect?dealID=abc123',
        );
      },
    );

    test('fetchDeals sends a descriptive User-Agent for CheapShark', () async {
      final client = _CapturingClient(
        http.Response(
          jsonEncode([
            {
              'dealID': 'abc123',
              'title': 'Portal 2',
              'salePrice': '1.99',
              'normalPrice': '9.99',
              'savings': '80.0500',
            },
          ]),
          200,
        ),
      );

      await GamingNewsService.fetchDeals(client: client);

      expect(client.lastRequest?.headers['User-Agent'], contains('JUJOStream'));
    });

    test(
      'fetchDeals returns empty list for malformed CheapShark response',
      () async {
        final client = _FakeClient(http.Response('{"unexpected":true}', 200));

        final items = await GamingNewsService.fetchDeals(client: client);

        expect(items, isEmpty);
      },
    );

    test('public Steam news is requested without an API key', () async {
      final client = _CountingClient();

      final items = await GamingNewsService.fetchSteamNewsForApps(
        steamAppIds: const [620],
        client: client,
      );

      expect(items, isEmpty);
      expect(client.requestCount, 1);
    });

    test(
      'fetchSteamNewsForApps maps Steam Web API news to update cards',
      () async {
        final client = _CapturingClient(
          http.Response(
            jsonEncode({
              'appnews': {
                'appid': 620,
                'newsitems': [
                  {
                    'gid': 'steam-news-1',
                    'title': 'Portal 2 Update',
                    'url': 'https://store.steampowered.com/news/app/620',
                    'contents': 'Patch notes and performance fixes.',
                    'date': 1777320000,
                    'feedlabel': 'Steam News',
                  },
                ],
              },
            }),
            200,
          ),
        );

        final items = await GamingNewsService.fetchSteamNewsForApps(
          steamAppIds: const [620],
          client: client,
        );

        expect(items, hasLength(1));
        expect(items.single.id, 'steam-steam-news-1');
        expect(
          client.lastRequest!.url.queryParameters.containsKey('key'),
          isFalse,
        );
        expect(items.single.type, GamingNewsType.update);
        expect(items.single.title, 'Portal 2 Update');
        expect(items.single.subtitle, 'Patch notes and performance fixes.');
        expect(items.single.dateLabel, 'STEAM NEWS');
        expect(items.single.relatedAppId, 620);
        expect(
          items.single.sourceUrl,
          'https://store.steampowered.com/news/app/620',
        );
      },
    );

    test('public news ignores invalid IDs and deduplicates requests', () async {
      final client = _CountingClient();
      await GamingNewsService.fetchSteamNewsForApps(
        steamAppIds: [-1, 0],
        client: client,
      );
      expect(client.requestCount, 0);
      await GamingNewsService.fetchSteamNewsForApps(
        steamAppIds: [620, 620, 0, -1],
        client: client,
      );
      expect(client.requestCount, 1);
    });

    test(
      'fetchGiveaways returns empty list when GamerPower has no data',
      () async {
        final client = _FakeClient(http.Response('No active giveaways', 201));

        final items = await GamingNewsService.fetchGiveaways(client: client);

        expect(items, isEmpty);
      },
    );

    test('fetchGiveaways returns empty list for malformed response', () async {
      final client = _FakeClient(http.Response('{bad json', 200));

      final items = await GamingNewsService.fetchGiveaways(client: client);

      expect(items, isEmpty);
    });

    test('OpenGamingFeedsProvider.parseRssXml parses RSS articles cleanly', () {
      const xml = '''
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <item>
              <title><![CDATA[Indie &amp; RPG Showcase 2026]]></title>
              <link>https://example.com/news/indie-2026</link>
              <description><![CDATA[<p>Big reveal &quot;soon&quot;.</p>]]></description>
              <pubDate>Tue, 10 Nov 2026 14:00:00 GMT</pubDate>
              <media:thumbnail url="https://example.com/cover.jpg" />
            </item>
          </channel>
        </rss>
      ''';

      final items = OpenGamingFeedsProvider.parseRssXml(
        xml,
        sourceLabel: 'PC GAMER',
      );

      expect(items, hasLength(1));
      expect(items.single.type, GamingNewsType.news);
      expect(items.single.title, 'Indie & RPG Showcase 2026');
      expect(items.single.subtitle, 'Big reveal "soon".');
      expect(items.single.imageUrl, 'https://example.com/cover.jpg');
      expect(items.single.sourceUrl, 'https://example.com/news/indie-2026');
      expect(items.single.dateLabel, 'PC GAMER · 10 NOV 2026');
    });

    test(
      'OpenGamingFeedsProvider.parseSteamFeaturedJson extracts updates and specials',
      () {
        final items = OpenGamingFeedsProvider.parseSteamFeaturedJson({
          'new_releases': {
            'items': [
              {
                'id': 620,
                'name': 'Portal 2',
                'discount_percent': 0,
                'final_price': 999,
                'currency': 'USD',
                'large_capsule_image': 'https://example.com/p2.jpg',
              },
            ],
          },
          'specials': {
            'items': [
              {
                'id': 400,
                'name': 'Portal',
                'discount_percent': 80,
                'final_price': 199,
                'original_price': 999,
                'currency': 'USD',
                'header_image': 'https://example.com/p1.jpg',
              },
            ],
          },
        });

        expect(items, hasLength(2));
        expect(items.first.type, GamingNewsType.update);
        expect(items.first.relatedAppId, 620);
        expect(items.first.dateLabel, 'STEAM · NEW RELEASE');
        expect(items.last.type, GamingNewsType.recommended);
        expect(items.last.relatedAppId, 400);
        expect(items.last.dateLabel, 'STEAM · -80%');
        expect(items.last.subtitle, r'$1.99  -  was $9.99');
      },
    );

    test(
      'OpenGamingFeedsProvider.parseSteamFeaturedJson includes coming soon and 100% free items',
      () {
        final items = OpenGamingFeedsProvider.parseSteamFeaturedJson({
          'specials': {
            'items': [
              {
                'id': 730,
                'name': 'Free Weekend Drop',
                'discount_percent': 100,
                'final_price': 0,
                'original_price': 1499,
                'currency': 'USD',
              },
            ],
          },
          'coming_soon': {
            'items': [
              {
                'id': 553850,
                'name': 'Upcoming Expansion',
                'large_capsule_image': 'https://example.com/upcoming.jpg',
              },
            ],
          },
        });

        expect(items, hasLength(2));
        expect(items.first.type, GamingNewsType.update);
        expect(items.first.dateLabel, 'STEAM · COMING SOON');
        expect(items.first.relatedAppId, 553850);
        expect(items.last.type, GamingNewsType.recommended);
        expect(items.last.dateLabel, 'STEAM · FREE');
        expect(items.last.subtitle, r'FREE  -  was $14.99');
      },
    );

    test(
      'OpenGamingFeedsProvider.parseEpicFreeGamesJson extracts current and upcoming free games',
      () {
        final now = DateTime.now().toUtc();
        final activeStart = now
            .subtract(const Duration(days: 1))
            .toIso8601String();
        final activeEnd = now.add(const Duration(days: 5)).toIso8601String();
        final nextStart = now.add(const Duration(days: 5)).toIso8601String();
        final nextEnd = now.add(const Duration(days: 12)).toIso8601String();

        final items = OpenGamingFeedsProvider.parseEpicFreeGamesJson({
          'data': {
            'Catalog': {
              'searchStore': {
                'elements': [
                  {
                    'id': 'epic-1',
                    'title': 'Control Ultimate Edition',
                    'description': 'Claim it free this week on Epic Games.',
                    'productSlug': 'control',
                    'price': {
                      'totalPrice': {'discountPrice': 0},
                    },
                    'keyImages': [
                      {
                        'type': 'OfferImageWide',
                        'url': 'https://example.com/control.jpg',
                      },
                    ],
                    'promotions': {
                      'promotionalOffers': [
                        {
                          'promotionalOffers': [
                            {
                              'startDate': activeStart,
                              'endDate': activeEnd,
                              'discountSetting': {'discountPercentage': 0},
                            },
                          ],
                        },
                      ],
                    },
                  },
                  {
                    'id': 'epic-2',
                    'title': 'Alan Wake Remastered',
                    'description': 'Next week free mystery giveaway.',
                    'urlSlug': 'alan-wake-remastered',
                    'keyImages': [
                      {
                        'type': 'Thumbnail',
                        'url': 'https://example.com/alan.jpg',
                      },
                    ],
                    'promotions': {
                      'upcomingPromotionalOffers': [
                        {
                          'promotionalOffers': [
                            {
                              'startDate': nextStart,
                              'endDate': nextEnd,
                              'discountSetting': {'discountPercentage': 0},
                            },
                          ],
                        },
                      ],
                    },
                  },
                ],
              },
            },
          },
        });

        expect(items, hasLength(2));
        expect(items.first.type, GamingNewsType.event);
        expect(items.first.dateLabel, 'EPIC GAMES · FREE NOW');
        expect(
          items.first.sourceUrl,
          'https://store.epicgames.com/en-US/p/control',
        );
        expect(items.last.type, GamingNewsType.event);
        expect(items.last.dateLabel, 'EPIC GAMES · UPCOMING FREE');
        expect(
          items.last.sourceUrl,
          'https://store.epicgames.com/en-US/p/alan-wake-remastered',
        );
      },
    );

    test(
      'fetchDeals formats 100% CheapShark discounts as FREE · 100% OFF',
      () async {
        final client = _FakeClient(
          http.Response(
            jsonEncode([
              {
                'dealID': 'free123',
                'title': 'Mystery Freebie',
                'salePrice': '0.00',
                'normalPrice': '19.99',
                'savings': '100.0',
              },
            ]),
            200,
          ),
        );

        final items = await GamingNewsService.fetchDeals(client: client);

        expect(items, hasLength(1));
        expect(items.single.dateLabel, 'CHEAPSHARK - FREE · 100% OFF');
        expect(items.single.subtitle, r'FREE  -  was $19.99');
      },
    );
  });
}

class _FakeClient extends http.BaseClient {
  final http.Response response;

  _FakeClient(this.response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _CapturingClient extends _FakeClient {
  http.BaseRequest? lastRequest;

  _CapturingClient(super.response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    lastRequest = request;
    return super.send(request);
  }
}

class _CountingClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      200,
      request: request,
    );
  }
}
