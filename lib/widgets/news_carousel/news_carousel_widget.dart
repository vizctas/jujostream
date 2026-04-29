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
/// - **Gamepad-first:** LEFT/RIGHT navigate cards, UP/DOWN between rows,
///   UP from tabs calls [onDismiss].
/// - **Two-row grid:** items are laid out in two rows for denser content.
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
  static const double _cardWidth = 320;
  static const double _cardHeight = 220;
  static const double _cardGap = 14;
  static const double _rowGap = 12;
  static const int _rowCount = 2;

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

  /// Current focused card column (horizontal index).
  int _cardCol = 0;

  /// Current focused card row (0 = top, 1 = bottom).
  int _cardRow = 0;

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
        .take(12)
        .toList(growable: false);
  }

  Future<List<int>> _steamAppIdsWithFallback() async {
    final ids = _directSteamAppIds().toSet();
    if (ids.length >= 12) return ids.take(12).toList(growable: false);

    final candidates = widget.allApps
        .followedBy(widget.apps)
        .where((app) => app.steamAppId == null && app.appName.trim().isNotEmpty)
        .take(14)
        .toList(growable: false);

    final lookups = await Future.wait(
      candidates.map(
        (app) async =>
            (app: app, result: await _steamClient.searchApp(app.appName)),
      ),
    );

    for (final lookup in lookups) {
      if (ids.length >= 12) break;
      final result = lookup.result;
      if (result == null) continue;
      ids.add(result.appId);
    }

    return ids.take(12).toList(growable: false);
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
  // Two-row grid helpers
  // ---------------------------------------------------------------------------

  /// Number of columns in the grid (items per row).
  int _colCount(List<GamingNewsItem> items) {
    return (items.length / _rowCount).ceil().clamp(1, items.length);
  }

  /// Map (row, col) → flat index into items list.
  int? _gridToIndex(int row, int col, int itemCount) {
    final cols = (itemCount / _rowCount).ceil();
    final index = row * cols + col;
    return index < itemCount ? index : null;
  }

  
  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _moveCard(int dCol, int dRow) {
    final items = _filteredItems();
    if (items.isEmpty) return;
    final cols = _colCount(items);

    var nextCol = _cardCol + dCol;
    var nextRow = _cardRow + dRow;

    // Vertical: UP from row 0 → go to tabs
    if (nextRow < 0) {
      setState(() => _area = NewsCarouselArea.tabs);
      return;
    }
    nextRow = nextRow.clamp(0, _rowCount - 1);
    nextCol = nextCol.clamp(0, cols - 1);

    // Ensure the target cell has an item
    final targetIdx = _gridToIndex(nextRow, nextCol, items.length);
    if (targetIdx == null) {
      // Try staying in same column but clamp row
      nextRow = 0;
      final fallback = _gridToIndex(nextRow, nextCol, items.length);
      if (fallback == null) return;
    }

    if (nextCol == _cardCol && nextRow == _cardRow) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() {
      _cardCol = nextCol;
      _cardRow = nextRow;
    });
    _scrollToCol(nextCol);
  }

  void _moveTab(int delta) {
    final current = _tabs.indexWhere((t) => t.$2 == _activeType);
    final next = (current + delta).clamp(0, _tabs.length - 1);
    if (next == current) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() {
      _activeType = _tabs[next].$2;
      _cardCol = 0;
      _cardRow = 0;
    });
  }

  void _scrollToCol(int col) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      col * (_cardWidth + _cardGap),
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
      // cards area — 2D grid navigation
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveCard(1, 0);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveCard(-1, 0);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveCard(0, -1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveCard(0, 1);
        return true;
      }
    }
    return false;
  }

  /// Reset internal focus to tabs when the widget becomes visible.
  void resetFocus() {
    setState(() {
      _area = NewsCarouselArea.tabs;
      _cardCol = 0;
      _cardRow = 0;
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
      decoration: BoxDecoration(
        color: tp.background.withValues(alpha: 0.80),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          _buildTabs(tp),
          Expanded(
            child: _loading || items.isEmpty
                ? _buildSkeletons(tp)
                : _buildCards(tp, items),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabs with animated underline
  // ---------------------------------------------------------------------------

  Widget _buildTabs(ThemeProvider tp) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            _tab(tp, _tabs[i].$1, _tabs[i].$2),
            if (i < _tabs.length - 1) const SizedBox(width: 10),
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
          _cardCol = 0;
          _cardRow = 0;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active
                    ? tp.accentLight
                    : Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            // Animated underline indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 2,
              width: active ? 24 : 0,
              decoration: BoxDecoration(
                color: active ? tp.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cards — two-row horizontal grid
  // ---------------------------------------------------------------------------

  Widget _buildCards(ThemeProvider tp, List<GamingNewsItem> items) {
    final cols = _colCount(items);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute card height from available space: fill the area evenly.
        final available = constraints.maxHeight - 22; // padding top+bottom
        final cellH = ((available - _rowGap) / _rowCount)
            .clamp(_cardHeight * 0.6, _cardHeight);

        return ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
          itemCount: cols,
          separatorBuilder: (_, _) => const SizedBox(width: _cardGap),
          itemBuilder: (context, col) {
            return SizedBox(
              width: _cardWidth,
              child: Column(
                children: [
                  for (int row = 0; row < _rowCount; row++) ...[
                    if (row > 0) const SizedBox(height: _rowGap),
                    _buildGridCell(tp, items, row, col, cellH),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGridCell(
    ThemeProvider tp,
    List<GamingNewsItem> items,
    int row,
    int col, [
    double cellHeight = _cardHeight,
  ]) {
    final index = _gridToIndex(row, col, items.length);
    if (index == null) {
      // Empty cell — transparent placeholder
      return SizedBox(height: cellHeight);
    }

    final isFocused = widget.hasFocus &&
        _area == NewsCarouselArea.cards &&
        col == _cardCol &&
        row == _cardRow;

    return GestureDetector(
      onTap: () {
        setState(() {
          _cardCol = col;
          _cardRow = row;
        });
      },
      child: SizedBox(
        height: cellHeight,
        child: NewsCarouselCard(
          item: items[index],
          focused: isFocused,
          cardWidth: _cardWidth,
          tp: tp,
          allApps: widget.allApps,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shimmer Skeletons
  // ---------------------------------------------------------------------------

  Widget _buildSkeletons(ThemeProvider tp) {
    final gridHeight = (_cardHeight * _rowCount) + _rowGap + 30;

    return SizedBox(
      height: gridHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: _cardGap),
        itemBuilder: (_, col) {
          return SizedBox(
            width: _cardWidth,
            child: Column(
              children: [
                for (int row = 0; row < _rowCount; row++) ...[
                  if (row > 0) const SizedBox(height: _rowGap),
                  _ShimmerCard(
                    width: _cardWidth,
                    height: _cardHeight,
                    tp: tp,
                    delay: Duration(milliseconds: (col * _rowCount + row) * 80),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shimmer skeleton card — animated sweep
// -----------------------------------------------------------------------------

class _ShimmerCard extends StatefulWidget {
  final double width;
  final double height;
  final ThemeProvider tp;
  final Duration delay;

  const _ShimmerCard({
    required this.width,
    required this.height,
    required this.tp,
    this.delay = Duration.zero,
  });

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Stagger start based on delay
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.tp.surfaceVariant.withValues(alpha: 0.18);
    final shimmer = widget.tp.surfaceVariant.withValues(alpha: 0.38);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-0.4 + 2.0 * _ctrl.value, 0),
              colors: [base, shimmer, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 3),
            Container(
              width: 60,
              height: 10,
              decoration: BoxDecoration(
                color: widget.tp.surfaceVariant.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 180,
              height: 14,
              decoration: BoxDecoration(
                color: widget.tp.surfaceVariant.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 90,
              height: 10,
              decoration: BoxDecoration(
                color: widget.tp.surfaceVariant.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
