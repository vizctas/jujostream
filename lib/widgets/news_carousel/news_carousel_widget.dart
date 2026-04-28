import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/news/gaming_news_service.dart';
import '../poster_image.dart';

/// Reusable News / Events / Deals carousel that any launcher theme can embed.
///
/// The widget is fully self-contained: it loads news, manages its own scroll
/// controllers, and exposes simple navigation callbacks so the host theme can
/// wire gamepad / keyboard routing without coupling to internal state.
///
/// **Zero hardcoded colours** — every tint derives from [ThemeProvider].
class NewsCarouselWidget extends StatefulWidget {
  /// Full list of apps currently visible in the launcher (filtered).
  final List<NvApp> apps;

  /// Complete app catalogue (unfiltered) — used for Steam-ID lookups.
  final List<NvApp> allApps;

  /// Whether the tabs row is the currently focused area.
  final bool tabsFocused;

  /// Whether the cards row is the currently focused area.
  final bool cardsFocused;

  /// Index of the currently focused news card (managed by the host).
  final int newsIndex;

  /// Currently active news-type filter (null = show all).
  final GamingNewsType? activeNewsType;

  /// Called when the user changes the active tab.
  final ValueChanged<GamingNewsType?> onNewsTypeChanged;

  /// Called when the focused card index changes.
  final ValueChanged<int> onNewsIndexChanged;

  /// Optional poster-URL resolver — lets the host share its poster-recovery
  /// cache so news cards can show library artwork.
  final String? Function(NvApp app)? posterUrlForApp;

  const NewsCarouselWidget({
    super.key,
    required this.apps,
    required this.allApps,
    this.tabsFocused = false,
    this.cardsFocused = false,
    this.newsIndex = 0,
    this.activeNewsType,
    required this.onNewsTypeChanged,
    required this.onNewsIndexChanged,
    this.posterUrlForApp,
  });

  @override
  State<NewsCarouselWidget> createState() => NewsCarouselWidgetState();
}

class NewsCarouselWidgetState extends State<NewsCarouselWidget> {
  static const double _newsCardWidth = 390;

  static const List<(String, GamingNewsType?)> newsTabs = [
    ("WHAT'S NEW", null),
    ('UPDATES', GamingNewsType.update),
    ('EVENTS', GamingNewsType.event),
    ('PATCHES', GamingNewsType.patch),
    ('RECOMMENDED', GamingNewsType.recommended),
  ];

  final ScrollController _newsScrollController = ScrollController();
  bool _newsLoading = true;
  List<GamingNewsItem> _newsItems = const <GamingNewsItem>[];

  /// Filtered items based on the active news type.
  List<GamingNewsItem> get filteredItems =>
      GamingNewsService.filterByType(_newsItems, widget.activeNewsType);

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  @override
  void dispose() {
    _newsScrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Public API — called by host themes for gamepad navigation
  // ---------------------------------------------------------------------------

  /// Move the focused card by [delta] positions (±1).
  void moveCard(int delta) {
    final items = filteredItems;
    if (items.isEmpty) return;
    final next = (widget.newsIndex + delta).clamp(0, items.length - 1);
    if (next == widget.newsIndex) return;
    UiSoundService.playClick();
    widget.onNewsIndexChanged(next);
    _scrollToCard(next);
  }

  /// Move the active tab by [delta] positions (±1).
  void moveTab(int delta) {
    final current =
        newsTabs.indexWhere((tab) => tab.$2 == widget.activeNewsType);
    final next = (current + delta).clamp(0, newsTabs.length - 1);
    if (next == current) return;
    UiSoundService.playClick();
    widget.onNewsTypeChanged(newsTabs[next].$2);
    widget.onNewsIndexChanged(0);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _scrollToCard(int index) {
    if (!_newsScrollController.hasClients) return;
    _newsScrollController.animateTo(
      index * (_newsCardWidth + 16),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadNews() async {
    setState(() => _newsLoading = true);
    final plugins = context.read<PluginsProvider>();
    String? steamApiKey;
    if (plugins.isEnabled('steam_connect')) {
      steamApiKey = await plugins.getApiKey('steam_connect');
    }
    final steamAppIds =
        steamApiKey != null && steamApiKey.trim().isNotEmpty
            ? await _steamAppIdsWithFallback()
            : _directSteamAppIds();
    if (!mounted) return;
    final items = await GamingNewsService.fetchDashboardItems(
      steamAppIds: steamAppIds,
      steamApiKey: steamApiKey,
    );
    if (!mounted) return;
    setState(() {
      _newsItems = items;
      _newsLoading = false;
    });
  }

  /// Extract Steam App IDs directly from poster URLs.
  List<int> _directSteamAppIds() {
    return widget.allApps
        .followedBy(widget.apps)
        .map((app) => app.steamAppId)
        .whereType<int>()
        .where((appId) => appId > 0)
        .toSet()
        .take(6)
        .toList(growable: false);
  }

  /// Try direct IDs first, then fall back to Steam Store search by name
  /// for apps whose poster URL doesn't contain a Steam App ID.
  Future<List<int>> _steamAppIdsWithFallback() async {
    final ids = _directSteamAppIds().toSet();
    if (ids.length >= 6) return ids.take(6).toList(growable: false);

    final candidates = widget.allApps
        .followedBy(widget.apps)
        .where((app) => app.steamAppId == null && app.appName.trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
    if (candidates.isEmpty) return ids.toList(growable: false);

    const client = SteamVideoClient();
    final lookups = await Future.wait(
      candidates.map(
        (app) async => (app: app, result: await client.searchApp(app.appName)),
      ),
    );
    for (final lookup in lookups) {
      if (ids.length >= 6) break;
      final result = lookup.result;
      if (result == null) continue;
      ids.add(result.appId);
    }
    return ids.take(6).toList(growable: false);
  }

  String? _resolvedPosterUrl(NvApp app) {
    if (widget.posterUrlForApp != null) return widget.posterUrlForApp!(app);
    final url = app.posterUrl;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final items = filteredItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        // When placed inside Expanded the parent gives a bounded maxHeight;
        // use Expanded for the cards so they fill the available space.
        // Otherwise fall back to the fixed 320px height.
        final bounded = constraints.maxHeight.isFinite;

        Widget cardsSection;
        if (_newsLoading || items.isEmpty) {
          cardsSection = bounded
              ? Expanded(child: _buildSkeletons(tp, bounded: true))
              : _buildSkeletons(tp);
        } else {
          cardsSection = bounded
              ? Expanded(child: _buildCards(tp, items, bounded: true))
              : _buildCards(tp, items);
        }

        return Container(
          constraints: bounded
              ? null
              : const BoxConstraints(minHeight: 380),
          decoration: BoxDecoration(
            color: tp.surface.withValues(alpha: 0.80),
            border: Border(
              top: BorderSide(
                color: tp.accentLight.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Column(
            children: [
              _buildTabs(tp),
              cardsSection,
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabs(ThemeProvider tp) {
    return SizedBox(
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in newsTabs) ...[
            _buildTab(tp, tab.$1, tab.$2),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildTab(ThemeProvider tp, String label, GamingNewsType? type) {
    final active = widget.activeNewsType == type;
    final focused = widget.tabsFocused && active;
    return GestureDetector(
      onTap: () {
        widget.onNewsTypeChanged(type);
        widget.onNewsIndexChanged(0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? tp.accent.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: focused
              ? Border.all(color: tp.accentLight.withValues(alpha: 0.32))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? tp.accentLight
                : tp.accentLight.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildCards(
    ThemeProvider tp,
    List<GamingNewsItem> items, {
    bool bounded = false,
  }) {
    final list = ListView.separated(
      controller: _newsScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => widget.onNewsIndexChanged(index),
          child: _buildCard(
            tp,
            items[index],
            widget.cardsFocused && index == widget.newsIndex,
          ),
        );
      },
    );
    // When bounded (inside Expanded), let the ListView fill available space.
    // Otherwise use the fixed 320px height for themes that don't expand.
    return bounded ? list : SizedBox(height: 320, child: list);
  }

  Widget _buildCard(ThemeProvider tp, GamingNewsItem item, bool focused) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: _newsCardWidth,
      decoration: BoxDecoration(
        color: tp.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: focused
              ? tp.accent.withValues(alpha: 0.58)
              : tp.accentLight.withValues(alpha: 0.08),
          width: focused ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: tp.background.withValues(alpha: focused ? 0.40 : 0.28),
            blurRadius: focused ? 22 : 14,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 150, child: _buildNewsImage(tp, item)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.typeLabel,
                      style: TextStyle(
                        color: tp.warm,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tp.accentLight,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.dateLabel,
                      style: TextStyle(
                        color: tp.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsImage(ThemeProvider tp, GamingNewsItem item) {
    final relatedAppId = item.relatedAppId;
    if (relatedAppId != null && relatedAppId > 0) {
      final linkedApp = widget.apps
          .followedBy(widget.allApps)
          .where((app) => app.steamAppId == relatedAppId)
          .firstOrNull;
      if (linkedApp != null) {
        final posterUrl = _resolvedPosterUrl(linkedApp);
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return PosterImage(
            url: posterUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            memCacheWidth: 720,
            errorWidget: (_, _, _) => _buildNewsImageUrl(tp, item),
          );
        }
      }
    }
    return _buildNewsImageUrl(tp, item);
  }

  Widget _buildNewsImageUrl(ThemeProvider tp, GamingNewsItem item) {
    if (item.imageAsset != null && item.imageAsset!.isNotEmpty) {
      return Image.asset(
        item.imageAsset!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _buildFallbackImage(tp),
      );
    }
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return PosterImage(
        url: item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        memCacheWidth: 720,
        errorWidget: (_, _, _) => _buildFallbackImage(tp),
      );
    }
    return _buildFallbackImage(tp);
  }

  Widget _buildFallbackImage(ThemeProvider tp) {
    return Image.asset(
      'assets/images/news_placeholder.png',
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => _SkeletonBlock(color: tp.surfaceVariant),
    );
  }

  Widget _buildSkeletons(ThemeProvider tp, {bool bounded = false}) {
    final list = ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (_, index) {
        return Container(
          width: _newsCardWidth,
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: tp.accentLight.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: _SkeletonBlock(
                  color: tp.surfaceVariant,
                  delay: Duration(milliseconds: index * 90),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 70,
                        height: 12,
                        child: _SkeletonBlock(color: tp.surfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 240,
                        height: 16,
                        child: _SkeletonBlock(color: tp.surfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 120,
                        height: 12,
                        child: _SkeletonBlock(color: tp.surfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return bounded ? list : SizedBox(height: 320, child: list);
  }
}

class _SkeletonBlock extends StatelessWidget {
  final Color color;
  final Duration delay;

  const _SkeletonBlock({
    required this.color,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tint = 0.05 + ((delay.inMilliseconds ~/ 90) % 3) * 0.025;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: tint + 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
