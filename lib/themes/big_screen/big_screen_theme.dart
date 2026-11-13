import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/preferences/launcher_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../../ui/motion_scope.dart';
import '../../ui/accessible_action.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/library/launcher_artwork_budget.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/tv/tv_detector.dart';
import '../../widgets/game_backdrop_art.dart';
import '../../widgets/news_carousel/stacked_news_sections.dart';
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

enum _BigScreenArea { carousel, news }

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
  static const double _cardHeight = 266;
  static const double _cardGap = 18;
  static const double _headerHeight = 72;

  double _screenWidth = 1920;
  double get _selectedCardWidth => (_screenWidth * 0.292).clamp(360.0, 600.0);
  double get _posterCardWidth => (_screenWidth * 0.092).clamp(130.0, 190.0);

  late int _idx;
  final FocusNode _focusNode = FocusNode(debugLabel: 'big-screen-theme');
  final ScrollController _gameScrollController = ScrollController();
  final ScrollController _pageScrollController = ScrollController(
    initialScrollOffset: _headerHeight,
  );
  final GlobalKey _carouselRowKey = GlobalKey();
  final GlobalKey<StackedNewsSectionsState> _newsSectionsKey =
      GlobalKey<StackedNewsSectionsState>();
  final SteamVideoClient _steamClient = const SteamVideoClient();
  final Map<int, String> _posterOverrides = <int, String>{};
  final Set<int> _posterLookups = <int>{};
  final Set<int> _failedPosterIds = <int>{};
  Timer? _selectionSyncDebounce;
  _BigScreenArea _area = _BigScreenArea.carousel;

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
      _schedulePageScroll(_BigScreenArea.carousel);
    });
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
    _selectionSyncDebounce?.cancel();
    _focusNode.dispose();
    _gameScrollController.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  void _scrollGamesToSelection({bool animate = true}) {
    if (!_gameScrollController.hasClients || widget.apps.isEmpty) return;
    final pos = _gameScrollController.position;
    final itemLeft = _idx * (_posterCardWidth + _cardGap);
    final target = (itemLeft - (pos.viewportDimension - _selectedCardWidth) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _gameScrollController.animateTo(
        target,
        duration: MotionScope.read(context).focusDuration,
        curve: MotionScope.read(context).standardCurve,
      );
    } else {
      _gameScrollController.jumpTo(target);
    }
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
    _selectionSyncDebounce?.cancel();
    _selectionSyncDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _idx == index) widget.onIndexChanged(index);
    });
    _scrollGamesToSelection();
  }

  void _moveGame(int delta) {
    if (widget.apps.isEmpty) return;
    _selectIndex((_idx + delta).clamp(0, widget.apps.length - 1));
  }

  void _setArea(_BigScreenArea area) {
    if (_area != area) {
      setState(() => _area = area);
    }
    if (area == _BigScreenArea.news) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _newsSectionsKey.currentState?.enterFromTop();
      });
    } else {
      _schedulePageScroll(area);
    }
  }

  void _schedulePageScroll(_BigScreenArea area) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (area != _BigScreenArea.carousel) return;
      final ctx = _carouselRowKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: MotionScope.read(context).focusDuration,
        curve: MotionScope.read(context).standardCurve,
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
        UiSoundService.playClick();
        if (!TvDetector.instance.isTV) HapticFeedback.lightImpact();
        _setArea(_BigScreenArea.news);
        return KeyEventResult.handled;
      }
    } else if (_area == _BigScreenArea.news) {
      final consumed =
          _newsSectionsKey.currentState?.handleKeyEvent(key) ?? false;
      if (consumed) return KeyEventResult.handled;
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
    _screenWidth = MediaQuery.of(context).size.width;
    final selected = _selected;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Background(app: selected),
          Positioned.fill(
            bottom: context.watch<LauncherPreferences>().showButtonHints ? _footerHeight : 0,
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
          if (context.watch<LauncherPreferences>().showButtonHints)
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
            _headerIcon(
              Icons.search,
              label: AppLocalizations.of(context).searchGame,
              onTap: widget.onSearch,
            ),
            const SizedBox(width: 18),
            _headerIcon(
              Icons.filter_alt_outlined,
              label: AppLocalizations.of(context).smartFilters,
              onTap: widget.onFilter,
            ),
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

  Widget _headerIcon(
    IconData icon, {
    required String label,
    VoidCallback? onTap,
  }) {
    return AccessibleAction(
      label: label,
      tooltip: label,
      onActivate: onTap ?? () {},
      enabled: onTap != null,
      child: Center(child: Icon(icon, color: Colors.white, size: 24)),
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
            key: _carouselRowKey,
            height: _cardHeight,
            child: ListView.separated(
              controller: _gameScrollController,
              scrollDirection: Axis.horizontal,
              // Keep off-screen cards built so their posters are already
              // decoded when fast D-pad movement arrives.
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
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
    void activate() {
      if (index == _idx) {
        widget.onAppSelected(app);
      } else {
        _selectIndex(index);
      }
    }

    return Semantics(
      button: true,
      label: app.appName,
      selected: selected,
      onTap: activate,
      child: GestureDetector(
        onTap: activate,
        child: AnimatedContainer(
          duration: MotionScope.of(context).focusDuration,
          curve: MotionScope.of(context).standardCurve,
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
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.48),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (posterUrl != null && posterUrl.isNotEmpty)
                  PosterImage(
                    url: posterUrl,
                    cacheKey: app.artCacheKey('poster'),
                    fit: BoxFit.cover,
                    memCacheWidth: LauncherArtworkBudget.bigScreenPosterWidth(
                      selected: selected,
                    ),
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
            constraints: BoxConstraints(maxWidth: _selectedCardWidth),
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
    return StackedNewsSections(
      key: _newsSectionsKey,
      allApps: widget.allApps,
      apps: widget.apps,
      hasFocus: _area == _BigScreenArea.news,
      parentScrollController: _pageScrollController,
      onPlayApp: widget.onAppSelected,
      onAppDetails: widget.onAppDetails,
      onExitUp: () {
        UiSoundService.playClick();
        if (!TvDetector.instance.isTV) HapticFeedback.lightImpact();
        _setArea(_BigScreenArea.carousel);
      },
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

  const _Background({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (app != null)
          GameBackdropArt(
            app: app!,
            heroCacheWidth: theme.backgroundArtCacheWidth,
            fallbackColor: const Color(0xFF07111C),
            enableKenBurns: !theme.reduceEffects && !theme.performanceMode,
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
