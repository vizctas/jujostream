import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/news/gaming_news_service.dart';
import 'news_carousel_card.dart';

/// Area within the news carousel that currently has focus.
enum NewsCarouselArea { tabs, cards }

/// A shared, theme-aware news/deals/events carousel.
///
/// - **Lazy:** fetches data only when [visible] becomes `true`.
/// - **Rotation:** each time [rotationSeed] changes the starting card shifts.
/// - **Gamepad-first:** LEFT/RIGHT navigate cards, UP from tabs calls [onDismiss].
/// - **Colors:** all derived from [ThemeProvider].
class NewsCarouselWidget extends StatefulWidget {
  /// Full app list used to resolve Steam IDs and poster images.
  final List<NvApp> allApps;

  /// Filtered/visible app list (may overlap with [allApps]).
  final List<NvApp> apps;

  /// When `true` the widget is on-screen and should load data.
  final bool visible;

  /// Called when the user presses UP from the tabs row (dismiss gesture).
  final VoidCallback? onDismiss;

  /// Incremented each time the user opens the carousel so items rotate.
  final int rotationSeed;

  /// Whether this widget currently owns keyboard/gamepad focus.
  final bool hasFocus;

  const NewsCarouselWidget({
    super.key,
    required this.allApps,
    required this.apps,
    required this.visible,
    this.onDismiss,
    this.rotationSeed = 0,
    this.hasFocus = false,
  });

  @override
  State<NewsCarouselWidget> createState() => NewsCarouselWidgetState();
}

class NewsCarouselWidgetState extends State<NewsCarouselWidget> {
  static const double _cardWidth = 340;
  static const double _cardGap = 16;

  static const List<(String, GamingNewsType?)> _tabs = [
    ("WHAT'S NEW", null),
    ('UPDATES', GamingNewsType.update),
    ('EVENTS', GamingNewsType.event),
    ('PATCHES', GamingNewsType.patch),
    ('RECOMMENDED', GamingNewsType.recommended),
  ];

  final ScrollController _scrollController = ScrollController();
  final SteamVideoClient _steamClient = const SteamVideoClient();

  List<GamingNewsItem> _items = const [];
  bool _loading = true;
  bool _fetched = false;
  GamingNewsType? _activeType;
  int _cardIndex = 0;
  NewsCarouselArea _area = NewsCarouselArea.tabs;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _lazyLoad();
  }

  @override
  void didUpdateWidget(covariant NewsCarouselWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_fetched) _lazyLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading (lazy)
  // ---------------------------------------------------------------------------

  Future<void> _lazyLoad() async {
    if (_fetched) return;
    _fetched = true;
    setState(() => _loading = true);

    final plugins = context.read<PluginsProvider>();
    String? steamApiKey;
    if (plugins.isEnabled('steam_connect')) {
      steamApiKey = await plugins.getApiKey('steam_connect');
    }

    final steamAppIds = steamApiKey != null && steamApiKey.trim().isNotEmpty
        ? await _steamAppIdsWithFallback()
        : _directSteamAppIds();

    if (!mounted) return;

    final items = await GamingNewsService.fetchDashboardItems(
      steamAppIds: steamAppIds,
      steamApiKey: steamApiKey,
    );

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<int> _directSteamAppIds() {
    return widget.allApps
        .followedBy(widget.apps)
        .map((app) => app.steamAppId)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet()
        .take(6)
        .toList(growable: false);
  }

  Future<List<int>> _steamAppIdsWithFallback() async {
    final ids = _directSteamAppIds().toSet();
    if (ids.length >= 6) return ids.take(6).toList(growable: false);

    final candidates = widget.allApps
        .followedBy(widget.apps)
        .where((app) => app.steamAppId == null && app.appName.trim().isNotEmpty)
        .take(8)
        .toList(growable: false);

    final lookups = await Future.wait(
      candidates.map(
        (app) async =>
            (app: app, result: await _steamClient.searchApp(app.appName)),
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

  // ---------------------------------------------------------------------------
  // Rotation
  // ---------------------------------------------------------------------------

  List<GamingNewsItem> _rotatedItems(List<GamingNewsItem> source) {
    if (source.isEmpty || widget.rotationSeed <= 0) return source;
    final offset = widget.rotationSeed % source.length;
    return [...source.skip(offset), ...source.take(offset)];
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _moveCard(int delta) {
    final items = _filteredItems();
    if (items.isEmpty) return;
    final next = (_cardIndex + delta).clamp(0, items.length - 1);
    if (next == _cardIndex) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() => _cardIndex = next);
    _scrollToCard(next);
  }

  void _moveTab(int delta) {
    final current = _tabs.indexWhere((t) => t.$2 == _activeType);
    final next = (current + delta).clamp(0, _tabs.length - 1);
    if (next == current) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() {
      _activeType = _tabs[next].$2;
      _cardIndex = 0;
    });
  }

  void _scrollToCard(int index) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      index * (_cardWidth + _cardGap),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  List<GamingNewsItem> _filteredItems() {
    final filtered = GamingNewsService.filterByType(_items, _activeType);
    return _rotatedItems(filtered);
  }

  // ---------------------------------------------------------------------------
  // Public key handler — called by the parent theme's onKeyEvent
  // ---------------------------------------------------------------------------

  /// Returns `true` if the event was consumed.
  bool handleKeyEvent(LogicalKeyboardKey key) {
    if (_area == NewsCarouselArea.tabs) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveTab(1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveTab(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        widget.onDismiss?.call();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _area = NewsCarouselArea.cards);
        return true;
      }
    } else {
      // cards area
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveCard(1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveCard(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _area = NewsCarouselArea.tabs);
        return true;
      }
    }
    return false;
  }

  /// Reset internal focus to tabs when the widget becomes visible.
  void resetFocus() {
    setState(() {
      _area = NewsCarouselArea.tabs;
      _cardIndex = 0;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final items = _filteredItems();

    return Container(
      constraints: const BoxConstraints(minHeight: 340),
      decoration: BoxDecoration(
        color: tp.background.withValues(alpha: 0.80),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          _buildTabs(tp),
          if (_loading)
            _buildSkeletons(tp)
          else if (items.isEmpty)
            _buildSkeletons(tp)
          else
            _buildCards(tp, items),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------

  Widget _buildTabs(ThemeProvider tp) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in _tabs) ...[
            _tab(tp, tab.$1, tab.$2),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _tab(ThemeProvider tp, String label, GamingNewsType? type) {
    final active = _activeType == type;
    final focused =
        widget.hasFocus && _area == NewsCarouselArea.tabs && active;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeType = type;
          _cardIndex = 0;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? tp.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: focused
              ? Border.all(color: tp.accent.withValues(alpha: 0.40))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? tp.accentLight
                : Colors.white.withValues(alpha: 0.68),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _buildCards(ThemeProvider tp, List<GamingNewsItem> items) {
    return SizedBox(
      height: 290,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: _cardGap),
        itemBuilder: (context, index) {
          final isFocused =
              widget.hasFocus &&
              _area == NewsCarouselArea.cards &&
              index == _cardIndex;
          return GestureDetector(
            onTap: () {
              setState(() => _cardIndex = index);
            },
            child: NewsCarouselCard(
              item: items[index],
              focused: isFocused,
              cardWidth: _cardWidth,
              tp: tp,
              allApps: widget.allApps,
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeletons
  // ---------------------------------------------------------------------------

  Widget _buildSkeletons(ThemeProvider tp) {
    return SizedBox(
      height: 290,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: _cardGap),
        itemBuilder: (_, index) {
          return Container(
            width: _cardWidth,
            decoration: BoxDecoration(
              color: tp.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
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
                          width: 200,
                          height: 16,
                          child: _SkeletonBlock(color: tp.surfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 100,
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Skeleton placeholder
// -----------------------------------------------------------------------------

class _SkeletonBlock extends StatelessWidget {
  final Color color;
  final Duration delay;

  const _SkeletonBlock({
    required this.color,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tint = 0.08 + ((delay.inMilliseconds ~/ 90) % 3) * 0.03;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: tint + 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
