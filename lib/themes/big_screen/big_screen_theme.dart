import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/plugins_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/news/gaming_news_service.dart';
import '../../widgets/poster_image.dart';
import '../launcher_theme.dart';

class BigScreenTheme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.bigScreen;

  @override
  String name(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeBigScreen;

  @override
  String description(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeBigScreenDesc;

  @override
  Widget buildBody({
    required BuildContext context,
    required List<NvApp> apps,
    required List<NvApp> allApps,
    required int selectedIndex,
    required ValueChanged<NvApp> onAppSelected,
    required ValueChanged<NvApp> onAppDetails,
    required ValueChanged<int> onIndexChanged,
    required String? activeSessionAppId,
    required bool isGridView,
    required Set<String> favoriteIds,
    required ValueChanged<NvApp> onToggleFavorite,
    VoidCallback? onToggleView,
    Widget? videoWidget,
    int? videoForAppId,
    VoidCallback? onSearch,
    VoidCallback? onFilter,
    VoidCallback? onSmartFilters,
    VoidCallback? onResumeRunning,
    ValueChanged<bool>? onDetailViewChanged,
    String? activeFilterLabel,
  }) {
    return _BigScreenBody(
      apps: apps,
      allApps: allApps,
      selectedIndex: selectedIndex,
      onAppSelected: onAppSelected,
      onAppDetails: onAppDetails,
      onIndexChanged: onIndexChanged,
      favoriteIds: favoriteIds,
      onToggleFavorite: onToggleFavorite,
      onToggleView: onToggleView,
      onSearch: onSearch,
      onFilter: onFilter,
      onSmartFilters: onSmartFilters,
      onResumeRunning: onResumeRunning,
      activeFilterLabel: activeFilterLabel,
    );
  }
}

enum _BigScreenArea { carousel, tabs, news }

class _BigScreenBody extends StatefulWidget {
  final List<NvApp> apps;
  final List<NvApp> allApps;
  final int selectedIndex;
  final ValueChanged<NvApp> onAppSelected;
  final ValueChanged<NvApp> onAppDetails;
  final ValueChanged<int> onIndexChanged;
  final Set<String> favoriteIds;
  final ValueChanged<NvApp> onToggleFavorite;
  final VoidCallback? onToggleView;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final VoidCallback? onSmartFilters;
  final VoidCallback? onResumeRunning;
  final String? activeFilterLabel;

  const _BigScreenBody({
    required this.apps,
    required this.allApps,
    required this.selectedIndex,
    required this.onAppSelected,
    required this.onAppDetails,
    required this.onIndexChanged,
    required this.favoriteIds,
    required this.onToggleFavorite,
    this.onToggleView,
    this.onSearch,
    this.onFilter,
    this.onSmartFilters,
    this.onResumeRunning,
    this.activeFilterLabel,
  });

  @override
  State<_BigScreenBody> createState() => _BigScreenBodyState();
}

class _BigScreenBodyState extends State<_BigScreenBody> {
  static const double _footerHeight = 46;
  static const double _selectedCardWidth = 560;
  static const double _cardHeight = 266;
  static const double _posterCardWidth = 176;
  static const double _cardGap = 18;
  static const double _newsCardWidth = 390;

  late int _idx;
  final FocusNode _focusNode = FocusNode(debugLabel: 'big-screen-theme');
  final ScrollController _gameScrollController = ScrollController();
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _newsScrollController = ScrollController();
  final SteamVideoClient _steamClient = const SteamVideoClient();
  final Map<int, String> _posterOverrides = <int, String>{};
  final Set<int> _posterLookups = <int>{};
  final Set<int> _failedPosterIds = <int>{};
  _BigScreenArea _area = _BigScreenArea.carousel;
  GamingNewsType? _activeNewsType;
  int _newsIndex = 0;
  bool _newsLoading = true;
  List<GamingNewsItem> _newsItems = const <GamingNewsItem>[];

  static const List<(String, GamingNewsType?)> _newsTabs = [
    ("WHAT'S NEW", null),
    ('UPDATES', GamingNewsType.update),
    ('EVENTS', GamingNewsType.event),
    ('PATCHES', GamingNewsType.patch),
    ('RECOMMENDED', GamingNewsType.recommended),
  ];

  NvApp? get _selected => widget.apps.isNotEmpty
      ? widget.apps[_idx.clamp(0, widget.apps.length - 1)]
      : null;

  @override
  void initState() {
    super.initState();
    _idx = widget.selectedIndex.clamp(
      0,
      (widget.apps.length - 1).clamp(0, 999999),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _scrollGamesToSelection(animate: false);
    });
    _loadNews();
    _recoverMissingPosterArtwork();
  }

  @override
  void didUpdateWidget(covariant _BigScreenBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apps.length != oldWidget.apps.length) {
      _idx = _idx.clamp(0, (widget.apps.length - 1).clamp(0, 999999));
      _recoverMissingPosterArtwork();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _gameScrollController.dispose();
    _pageScrollController.dispose();
    _newsScrollController.dispose();
    super.dispose();
  }

  void _scrollGamesToSelection({bool animate = true}) {
    if (!_gameScrollController.hasClients || widget.apps.isEmpty) return;
    final selectedOffset = _idx * (_posterCardWidth + _cardGap);
    final target = selectedOffset.clamp(
      0.0,
      _gameScrollController.position.maxScrollExtent,
    );
    if (animate) {
      _gameScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _gameScrollController.jumpTo(target);
    }
  }

  Future<void> _loadNews() async {
    setState(() => _newsLoading = true);
    final plugins = context.read<PluginsProvider>();
    String? steamApiKey;
    if (plugins.isEnabled('steam_connect')) {
      steamApiKey = await plugins.getApiKey('steam_connect');
    }
    final steamAppIds = steamApiKey != null && steamApiKey.trim().isNotEmpty
        ? await _steamAppIdsForNewsWithFallback()
        : _directSteamAppIdsForNews();
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

  List<int> _directSteamAppIdsForNews() {
    return widget.allApps
        .followedBy(widget.apps)
        .map((app) => app.steamAppId)
        .whereType<int>()
        .where((appId) => appId > 0)
        .toSet()
        .take(6)
        .toList(growable: false);
  }

  Future<List<int>> _steamAppIdsForNewsWithFallback() async {
    final ids = _directSteamAppIdsForNews().toSet();
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
    final posterUpdates = <int, String>{};
    for (final lookup in lookups) {
      if (ids.length >= 6) break;
      final app = lookup.app;
      final result = lookup.result;
      if (result == null) continue;
      ids.add(result.appId);
      final imageUrl = result.imageUrl;
      if ((app.posterUrl == null || app.posterUrl!.isEmpty) &&
          imageUrl != null &&
          imageUrl.isNotEmpty) {
        posterUpdates[app.appId] = imageUrl;
      }
    }
    if (mounted && posterUpdates.isNotEmpty) {
      setState(() => _posterOverrides.addAll(posterUpdates));
    }
    return ids.take(6).toList(growable: false);
  }

  Future<void> _recoverMissingPosterArtwork() async {
    final candidates = widget.apps
        .where(
          (app) =>
              (app.posterUrl == null || app.posterUrl!.isEmpty) &&
              !_posterOverrides.containsKey(app.appId) &&
              !_posterLookups.contains(app.appId) &&
              app.appName.trim().isNotEmpty,
        )
        .take(8)
        .toList(growable: false);
    if (candidates.isEmpty) return;

    for (final app in candidates) {
      await _recoverPosterArtwork(app);
    }
  }

  Future<void> _recoverPosterArtwork(NvApp app) async {
    if (_posterLookups.contains(app.appId) || app.appName.trim().isEmpty) {
      return;
    }
    _posterLookups.add(app.appId);
    final result = await _steamClient.searchApp(app.appName);
    _posterLookups.remove(app.appId);
    final imageUrl = result?.imageUrl;
    if (!mounted || imageUrl == null || imageUrl.isEmpty) return;
    setState(() => _posterOverrides[app.appId] = imageUrl);
  }

  void _handlePosterError(NvApp app) {
    if (_failedPosterIds.add(app.appId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverPosterArtwork(app));
      });
    }
  }

  String? _posterUrlForApp(NvApp app) {
    final override = _posterOverrides[app.appId];
    // If this URL already failed, never return it again.  Return the recovery
    // override once available, or null to show the text-fallback while loading.
    if (_failedPosterIds.contains(app.appId)) return override;
    final posterUrl = app.posterUrl;
    if (posterUrl != null && posterUrl.isNotEmpty) return posterUrl;
    return override;
  }

  void _selectIndex(int index) {
    if (index < 0 || index >= widget.apps.length || index == _idx) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() => _idx = index);
    widget.onIndexChanged(index);
    _scrollGamesToSelection();
  }

  void _moveGame(int delta) {
    if (widget.apps.isEmpty) return;
    _selectIndex((_idx + delta).clamp(0, widget.apps.length - 1));
  }

  void _moveNews(int delta) {
    final items = GamingNewsService.filterByType(_newsItems, _activeNewsType);
    if (items.isEmpty) return;
    final next = (_newsIndex + delta).clamp(0, items.length - 1);
    if (next == _newsIndex) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() => _newsIndex = next);
    if (_newsScrollController.hasClients) {
      _newsScrollController.animateTo(
        next * (_newsCardWidth + 16),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _moveTab(int delta) {
    final current = _newsTabs.indexWhere((tab) => tab.$2 == _activeNewsType);
    final next = (current + delta).clamp(0, _newsTabs.length - 1);
    if (next == current) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() {
      _activeNewsType = _newsTabs[next].$2;
      _newsIndex = 0;
    });
  }

  void _setArea(_BigScreenArea area) {
    if (_area != area) {
      setState(() => _area = area);
    }
    _schedulePageScroll(area);
  }

  void _schedulePageScroll(_BigScreenArea area) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      final maxScroll = _pageScrollController.position.maxScrollExtent;
      final target = switch (area) {
        _BigScreenArea.carousel => 0.0,
        _BigScreenArea.tabs => maxScroll < 1 ? 0.0 : maxScroll * 0.55,
        _BigScreenArea.news => maxScroll,
      };
      _pageScrollController.animateTo(
        target.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (_area == _BigScreenArea.carousel) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveGame(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveGame(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _setArea(_BigScreenArea.tabs);
        return KeyEventResult.handled;
      }
    } else if (_area == _BigScreenArea.tabs) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveTab(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveTab(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _setArea(_BigScreenArea.carousel);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _setArea(_BigScreenArea.news);
        return KeyEventResult.handled;
      }
    } else if (_area == _BigScreenArea.news) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveNews(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveNews(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _setArea(_BigScreenArea.tabs);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter) {
      final selected = _selected;
      if (selected != null) widget.onAppSelected(selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonX) {
      widget.onToggleView?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonY) {
      final selected = _selected;
      if (selected != null) widget.onAppDetails(selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonThumbLeft) {
      widget.onSearch?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonThumbRight) {
      widget.onFilter?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonRight1) {
      widget.onSmartFilters?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonRight2) {
      widget.onResumeRunning?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final selectedPoster = selected == null ? null : _posterUrlForApp(selected);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Background(app: selected, posterUrl: selectedPoster),
          Positioned.fill(
            bottom: _footerHeight,
            child: SingleChildScrollView(
              controller: _pageScrollController,
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  _buildTopCarousel(context),
                  _buildNewsArea(context),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _footerHeight,
            child: _buildFixedFooter(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour == 0 || now.hour == 12 ? 12 : now.hour % 12;
    final suffix = now.hour >= 12 ? 'p.m.' : 'a.m.';
    final time = '$hour:${now.minute.toString().padLeft(2, '0')} $suffix';

    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            Text(
              'JUJO.Stream',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            _headerIcon(Icons.search, onTap: widget.onSearch),
            const SizedBox(width: 18),
            _headerIcon(Icons.filter_alt_outlined, onTap: widget.onFilter),
            const SizedBox(width: 18),
            Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  Widget _buildTopCarousel(BuildContext context) {
    if (widget.apps.isEmpty) {
      return SizedBox(
        height: 360,
        child: Center(
          child: Text(
            AppLocalizations.of(context).noResults,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIBRARY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              controller: _gameScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 360),
              itemCount: widget.apps.length,
              separatorBuilder: (_, _) => const SizedBox(width: _cardGap),
              itemBuilder: (context, index) {
                return _buildGameCard(widget.apps[index], index == _idx, index);
              },
            ),
          ),
          if (selected != null) _buildSelectedMeta(selected),
        ],
      ),
    );
  }

  Widget _buildGameCard(NvApp app, bool selected, int index) {
    final isFavorite = widget.favoriteIds.contains(app.appId.toString());
    final posterUrl = _posterUrlForApp(app);
    return GestureDetector(
      onTap: () {
        if (index == _idx) {
          widget.onAppSelected(app);
        } else {
          _selectIndex(index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: selected ? _selectedCardWidth : _posterCardWidth,
        height: _cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.58 : 0.34),
              blurRadius: selected ? 32 : 18,
              offset: Offset(0, selected ? 18 : 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterUrl != null && posterUrl.isNotEmpty)
                PosterImage(
                  url: posterUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 960,
                  errorWidget: (_, _, _) {
                    _handlePosterError(app);
                    return _buildPosterFallback(app);
                  },
                )
              else
                _buildPosterFallback(app),
              if (app.isRunning)
                const Positioned(
                  top: 10,
                  left: 10,
                  child: _StatusDot(color: Colors.greenAccent),
                ),
              if (isFavorite)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Icon(
                    Icons.star,
                    color: Colors.amberAccent,
                    size: selected ? 20 : 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterFallback(NvApp app) {
    final name = app.appName.trim();
    final initials = name.isEmpty
        ? 'JU'
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
    return Container(
      color: const Color(0xFF162839),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildSelectedMeta(NvApp app) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _selectedCardWidth),
            child: Text(
              app.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (app.playtimeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'LAST TWO WEEKS: ${app.playtimeLabel.toUpperCase()}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNewsArea(BuildContext context) {
    final items = GamingNewsService.filterByType(_newsItems, _activeNewsType);
    return Container(
      constraints: const BoxConstraints(minHeight: 380),
      decoration: BoxDecoration(
        color: const Color(0xCC0A1824),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          _buildNewsTabs(),
          if (_newsLoading)
            _buildNewsSkeletons()
          else if (items.isEmpty)
            _buildNewsSkeletons()
          else
            _buildNewsCards(items),
        ],
      ),
    );
  }

  Widget _buildNewsTabs() {
    return SizedBox(
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in _newsTabs) ...[
            _newsTab(tab.$1, tab.$2),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _newsTab(String label, GamingNewsType? type) {
    final active = _activeNewsType == type;
    final focused = _area == _BigScreenArea.tabs && active;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeNewsType = type;
          _newsIndex = 0;
        });
        _setArea(_BigScreenArea.tabs);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: focused
              ? Border.all(color: Colors.white.withValues(alpha: 0.22))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.68),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildNewsCards(List<GamingNewsItem> items) {
    return SizedBox(
      height: 320,
      child: ListView.separated(
        controller: _newsScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              setState(() {
                _newsIndex = index;
              });
              _setArea(_BigScreenArea.news);
            },
            child: _buildNewsCard(
              items[index],
              _area == _BigScreenArea.news && index == _newsIndex,
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewsCard(GamingNewsItem item, bool focused) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: _newsCardWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1823),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: focused
              ? const Color(0xFF66C0F4).withValues(alpha: 0.58)
              : Colors.white.withValues(alpha: 0.08),
          width: focused ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: focused ? 0.40 : 0.28),
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
            SizedBox(height: 150, child: _buildNewsImage(item)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.typeLabel,
                      style: const TextStyle(
                        color: Color(0xFFD2D6B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.dateLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
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

  Widget _buildNewsImage(GamingNewsItem item) {
    // For news tied to a game: prefer the poster we already have in the library
    // so the card banner matches the game the user knows.
    final relatedAppId = item.relatedAppId;
    if (relatedAppId != null && relatedAppId > 0) {
      final linkedApp = widget.apps
          .followedBy(widget.allApps)
          .where((app) => app.steamAppId == relatedAppId)
          .firstOrNull;
      if (linkedApp != null) {
        final posterUrl = _posterUrlForApp(linkedApp);
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return PosterImage(
            url: posterUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            memCacheWidth: 720,
            errorWidget: (_, _, _) => _buildNewsImageUrl(item),
          );
        }
      }
    }
    return _buildNewsImageUrl(item);
  }

  Widget _buildNewsImageUrl(GamingNewsItem item) {
    if (item.imageAsset != null && item.imageAsset!.isNotEmpty) {
      return Image.asset(
        item.imageAsset!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _buildNewsFallbackImage(),
      );
    }
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return PosterImage(
        url: item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        memCacheWidth: 720,
        errorWidget: (_, _, _) => _buildNewsFallbackImage(),
      );
    }
    return _buildNewsFallbackImage();
  }

  Widget _buildNewsFallbackImage() {
    return Image.asset(
      'assets/images/news_placeholder.png',
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => const _SkeletonBlock(),
    );
  }

  Widget _buildNewsSkeletons() {
    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (_, index) {
          return Container(
            width: _newsCardWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1823),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _SkeletonBlock(
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
                          child: _SkeletonBlock(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 240,
                          height: 16,
                          child: _SkeletonBlock(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 120,
                          height: 12,
                          child: _SkeletonBlock(),
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

  Widget _buildFixedFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xE6000000),
        border: Border(top: BorderSide(color: Color(0x18FFFFFF))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            _footerHint('HOME', 'MENU'),
            const Spacer(),
            _footerHint('MENU', l.options.toUpperCase()),
            const SizedBox(width: 18),
            _footerHint('A', 'SELECT'),
            const SizedBox(width: 18),
            _footerHint('B', l.back.toUpperCase()),
          ],
        ),
      ),
    );
  }

  Widget _footerHint(String badge, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GamepadHintIcon(badge, size: 25, forceVisible: true),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _Background extends StatelessWidget {
  final NvApp? app;
  final String? posterUrl;

  const _Background({required this.app, required this.posterUrl});

  @override
  Widget build(BuildContext context) {
    final url = posterUrl ?? app?.posterUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Transform.scale(
              scale: 1.08,
              child: PosterImage(
                url: url,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                memCacheWidth: 1280,
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF07111C)),
              ),
            ),
          )
        else
          const ColoredBox(color: Color(0xFF07111C)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x88000000), Color(0x66000000), Color(0xF0000000)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x6607111C), Color(0xAA07111C)],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.85), blurRadius: 14),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final Duration delay;

  const _SkeletonBlock({this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    final tint = 0.05 + ((delay.inMilliseconds ~/ 90) % 3) * 0.025;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: tint),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
