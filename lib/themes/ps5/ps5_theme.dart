import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../widgets/news_carousel/news_carousel_widget.dart';
import '../../widgets/poster_image.dart';
import '../../widgets/trailer_modal.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../../screens/app_view/app_view_presentation_settings_screen.dart';
import '../launcher_theme.dart';

class Ps5Theme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.ps5;
  @override
  String name(BuildContext context) =>
      AppLocalizations.of(context).launcherThemePs5;
  @override
  String description(BuildContext context) =>
      AppLocalizations.of(context).launcherThemePs5Desc;
  @override
  bool get hasStatusBar => false;

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
    final sorted = List<NvApp>.from(apps);
    if (apps.any((a) => a.isRunning)) {
      sorted.sort((a, b) {
        if (a.isRunning && !b.isRunning) return -1;
        if (!a.isRunning && b.isRunning) return 1;
        return 0;
      });
    }

    return _Ps5Body(
      apps: sorted,
      allApps: allApps,
      onAppSelected: onAppSelected,
      onAppDetails: onAppDetails,
      onIndexChanged: (i) {
        if (i >= 0 && i < sorted.length) {
          onIndexChanged(apps.indexOf(sorted[i]));
        }
      },
      activeSessionAppId: activeSessionAppId,
      favoriteIds: favoriteIds,
      onToggleFavorite: onToggleFavorite,
      onToggleView: onToggleView,
      videoWidget: videoWidget,
      videoForAppId: videoForAppId,
      onSearch: onSearch,
      onFilter: onFilter,
      onSmartFilters: onSmartFilters,
      onResumeRunning: onResumeRunning,
      onDetailViewChanged: onDetailViewChanged,
      activeFilterLabel: activeFilterLabel,
    );
  }
}

enum _Ps5Area { news, icons, buttons }

class _Ps5Body extends StatefulWidget {
  final List<NvApp> apps;
  final List<NvApp> allApps;
  final ValueChanged<NvApp> onAppSelected;
  final ValueChanged<NvApp> onAppDetails;
  final ValueChanged<int> onIndexChanged;
  final String? activeSessionAppId;
  final Set<String> favoriteIds;
  final ValueChanged<NvApp> onToggleFavorite;
  final VoidCallback? onToggleView;
  final Widget? videoWidget;
  final int? videoForAppId;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final VoidCallback? onSmartFilters;
  final VoidCallback? onResumeRunning;
  final ValueChanged<bool>? onDetailViewChanged;
  final String? activeFilterLabel;

  const _Ps5Body({
    required this.apps,
    required this.allApps,
    required this.onAppSelected,
    required this.onAppDetails,
    required this.onIndexChanged,
    required this.activeSessionAppId,
    required this.favoriteIds,
    required this.onToggleFavorite,
    this.onToggleView,
    this.videoWidget,
    this.videoForAppId,
    this.onSearch,
    this.onFilter,
    this.onSmartFilters,
    this.onResumeRunning,
    this.onDetailViewChanged,
    this.activeFilterLabel,
  });

  @override
  State<_Ps5Body> createState() => _Ps5BodyState();
}

class _Ps5BodyState extends State<_Ps5Body> {
  int _idx = 0;
  late ScrollController _iconSc;
  final FocusNode _fn = FocusNode(debugLabel: 'ps5');
  final GlobalKey<NewsCarouselWidgetState> _newsKey =
      GlobalKey<NewsCarouselWidgetState>(debugLabel: 'ps5-news');
  _Ps5Area _area = _Ps5Area.icons;
  Timer? _bgDebounce;
  int? _bgAppId;
  int _btnIdx = 0;
  static const int _btnCount = 2;

  // News carousel state
  GamingNewsType? _activeNewsType;
  int _newsIndex = 0;
  bool _newsTabsFocused = true;

  static const double _iconSize = 80;
  static const double _iconSelSize = 100;
  static const double _iconGap = 10;

  @override
  void initState() {
    super.initState();
    _idx = 0;
    _iconSc = ScrollController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollIcons(false);
      _fn.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _Ps5Body o) {
    super.didUpdateWidget(o);
    if (widget.apps.length != o.apps.length) {
      _idx = _idx.clamp(0, (widget.apps.length - 1).clamp(0, 999999));
    }
  }

  @override
  void dispose() {
    _iconSc.dispose();
    _fn.dispose();
    _bgDebounce?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  NvApp? get _sel => widget.apps.isNotEmpty ? widget.apps[_idx] : null;

  void _scrollIcons([bool anim = true]) {
    if (!_iconSc.hasClients || widget.apps.isEmpty) return;
    final vw = _iconSc.position.viewportDimension;
    final tw = widget.apps.length * (_iconSize + _iconGap);
    final offset = (_idx * (_iconSize + _iconGap)) - (vw / 2) + (_iconSize / 2);
    final clamped = offset.clamp(0.0, (tw - vw).clamp(0.0, double.infinity));
    anim
        ? _iconSc.animateTo(
            clamped,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
        : _iconSc.jumpTo(clamped);
  }

  void _move(int d) {
    final n = (_idx + d).clamp(0, widget.apps.length - 1);
    if (n == _idx) return;
    UiSoundService.playClick();
    HapticFeedback.lightImpact();
    setState(() => _idx = n);
    _bgDebounce?.cancel();
    _bgDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _bgAppId = _sel?.appId);
        widget.onIndexChanged(n);
      }
    });
    _scrollIcons(true);
  }

  void _tap() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _openTrailer(NvApp app) async {
    int? steamId = app.steamAppId;
    if (steamId == null) {
      try {
        steamId = await SteamVideoClient().searchAppId(app.appName);
      } catch (_) {}
    }
    List<SteamMovie> movies = const [];
    if (steamId != null && steamId > 0) {
      try {
        movies = await SteamVideoClient().getMovies(steamId);
      } catch (_) {}
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TrailerModal(
            gameName: app.appName,
            steamMovies: movies,
            preferredSource: movies.isNotEmpty
                ? TrailerSource.steam
                : TrailerSource.youtube,
          ),
        ),
      ),
    );
  }

  void _showMoreMenu(NvApp app) {
    _tap();
    final tp = context.read<ThemeProvider>();
    final l = AppLocalizations.of(context);
    final isFav = widget.favoriteIds.contains(app.appId.toString());
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _Ps5ContextMenu(
        items: [
          _Ps5MenuItem(Icons.library_books_outlined, l.details, 'Y', () {
            Navigator.pop(context);
            widget.onAppDetails(app);
          }),
          _Ps5MenuItem(Icons.movie_outlined, l.watchTrailer, 'RB', () {
            Navigator.pop(context);
            _openTrailer(app);
          }),
          _Ps5MenuItem(
            isFav ? Icons.star : Icons.star_outline,
            isFav ? l.removeFav : l.fav,
            'X',
            () {
              Navigator.pop(context);
              widget.onToggleFavorite(app);
            },
          ),
        ],
        accent: tp.accent,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;

    if (_area == _Ps5Area.icons) {
      if (k == LogicalKeyboardKey.arrowRight) {
        _move(1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        _move(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        _tap();
        setState(() {
          _area = _Ps5Area.news;
          _newsTabsFocused = true;
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _tap();
        setState(() {
          _area = _Ps5Area.buttons;
          _btnIdx = 0;
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter) {
        _tap();
        if (_sel != null) widget.onAppSelected(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonY) {
        _tap();
        if (_sel != null) widget.onAppDetails(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonX) {
        _tap();
        widget.onToggleView?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonThumbLeft) {
        _tap();
        widget.onSearch?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonThumbRight) {
        _tap();
        widget.onFilter?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight1) {
        _tap();
        widget.onSmartFilters?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight2) {
        _tap();
        widget.onResumeRunning?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonSelect) {
        _tap();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AppViewPresentationSettingsScreen(
              preferences: context.read<LauncherPreferences>(),
            ),
          ),
        );
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonB ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.goBack) {
        Navigator.maybePop(context);
        return KeyEventResult.handled;
      }
    }

    // ── News area ──
    if (_area == _Ps5Area.news) {
      if (_newsTabsFocused) {
        if (k == LogicalKeyboardKey.arrowRight) {
          _newsKey.currentState?.moveTab(1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowLeft) {
          _newsKey.currentState?.moveTab(-1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          _tap();
          setState(() => _newsTabsFocused = false);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          _tap();
          setState(() => _area = _Ps5Area.icons);
          return KeyEventResult.handled;
        }
      } else {
        if (k == LogicalKeyboardKey.arrowRight) {
          _newsKey.currentState?.moveCard(1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowLeft) {
          _newsKey.currentState?.moveCard(-1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          _tap();
          setState(() => _newsTabsFocused = true);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown ||
            k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          _tap();
          setState(() => _area = _Ps5Area.icons);
          return KeyEventResult.handled;
        }
      }
    }

    if (_area == _Ps5Area.buttons) {
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.gameButtonB ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.goBack) {
        _tap();
        setState(() => _area = _Ps5Area.icons);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        setState(() => _btnIdx = (_btnIdx - 1).clamp(0, _btnCount - 1));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        setState(() => _btnIdx = (_btnIdx + 1).clamp(0, _btnCount - 1));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter) {
        _activateBtn();
        return KeyEventResult.handled;
      }

      if (k == LogicalKeyboardKey.gameButtonX) {
        _tap();
        widget.onToggleView?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonY) {
        _tap();
        if (_sel != null) widget.onAppDetails(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight1) {
        _tap();
        if (_sel != null) _openTrailer(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonSelect) {
        _tap();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AppViewPresentationSettingsScreen(
              preferences: context.read<LauncherPreferences>(),
            ),
          ),
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _activateBtn() {
    _tap();
    final s = _sel;
    if (s == null) return;
    switch (_btnIdx) {
      case 0:
        widget.onAppSelected(s);
      case 1:
        _showMoreMenu(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final s = _sel;
    final l = AppLocalizations.of(context);
    final bgApp = _bgAppId != null
        ? widget.apps.cast<NvApp?>().firstWhere(
            (a) => a?.appId == _bgAppId,
            orElse: () => s,
          )
        : s;

    return Focus(
      focusNode: _fn,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) {
            _move(1);
          } else if (v > 300) {
            _move(-1);
          }
        },
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 300 && _area == _Ps5Area.icons) {
            _tap();
            setState(() {
              _area = _Ps5Area.buttons;
              _btnIdx = 0;
            });
          } else if (v < -300 && _area == _Ps5Area.buttons) {
            _tap();
            setState(() => _area = _Ps5Area.icons);
          } else if (v < -300 && _area == _Ps5Area.icons) {
            Navigator.maybePop(context);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.videoWidget != null &&
                widget.videoForAppId == bgApp?.appId)
              Positioned.fill(child: widget.videoWidget!)
            else if (bgApp?.posterUrl != null && bgApp!.posterUrl!.isNotEmpty)
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: PosterImage(
                    key: ValueKey(bgApp.appId),
                    url: bgApp.posterUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: 1280,
                    errorWidget: (_, _, _) => Container(color: tp.background),
                  ),
                ),
              )
            else
              Positioned.fill(child: Container(color: tp.background)),

            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 280,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xEE000000), Colors.transparent],
                  ),
                ),
              ),
            ),

            Column(
              children: [
                _buildStatusBar(tp, l),
                if (widget.apps.isEmpty)
                  _buildEmpty(tp, l)
                else ...[
                  _buildIconStrip(tp, s),
                  if (_area == _Ps5Area.news) ...[
                    const SizedBox(height: 8),
                    Expanded(
                      child: NewsCarouselWidget(
                        key: _newsKey,
                        apps: widget.apps,
                        allApps: widget.allApps,
                        tabsFocused: _newsTabsFocused,
                        cardsFocused: !_newsTabsFocused,
                        newsIndex: _newsIndex,
                        activeNewsType: _activeNewsType,
                        onNewsTypeChanged: (type) =>
                            setState(() => _activeNewsType = type),
                        onNewsIndexChanged: (index) =>
                            setState(() => _newsIndex = index),
                      ),
                    ),
                  ],
                  if (_area != _Ps5Area.news) const Spacer(),
                  if (s != null && _area != _Ps5Area.news)
                    _buildBottomPanel(tp, s, l),
                  _buildHints(tp, s, l),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(ThemeProvider tp, AppLocalizations l) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            'JUJO.Stream',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              _tap();
              widget.onSearch?.call();
            },
            child: Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.4),
              size: 18,
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              _tap();
              widget.onFilter?.call();
            },
            child: Icon(
              Icons.tune,
              color: Colors.white.withValues(alpha: 0.4),
              size: 18,
            ),
          ),
          const SizedBox(width: 16),
          if (widget.activeFilterLabel != null &&
              widget.activeFilterLabel!.isNotEmpty &&
              widget.activeFilterLabel != l.all)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  _tap();
                  widget.onFilter?.call();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tp.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.activeFilterLabel!,
                    style: TextStyle(
                      color: tp.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          Icon(
            Icons.wifi,
            color: Colors.white.withValues(alpha: 0.3),
            size: 14,
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.battery_std,
            color: Colors.white.withValues(alpha: 0.3),
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeProvider tp, AppLocalizations l) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off, color: Colors.white54, size: 56),
            const SizedBox(height: 14),
            Text(
              l.noResults,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.activeFilterLabel != null &&
                widget.activeFilterLabel != l.all)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: GestureDetector(
                  onTap: () {
                    _tap();
                    widget.onFilter?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tp.accent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tp.accent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, color: tp.accent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Change Filter',
                          style: TextStyle(
                            color: tp.accentLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconStrip(ThemeProvider tp, NvApp? s) {
    final inIcons = _area == _Ps5Area.icons;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _iconSelSize + 16,
          child: ListView.builder(
            controller: _iconSc,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            itemCount: widget.apps.length,
            itemBuilder: (_, i) {
              final a = widget.apps[i];
              final sel = i == _idx;
              final lp = context.read<LauncherPreferences>();
              final size = sel ? _iconSelSize : _iconSize;
              return GestureDetector(
                onTap: () {
                  if (sel) {
                    _tap();
                    widget.onAppSelected(a);
                  } else {
                    _move(i - _idx);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: size,
                  height: size,
                  margin: EdgeInsets.only(
                    right: _iconGap,
                    top: sel ? 0 : (_iconSelSize - _iconSize),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      sel ? lp.cardBorderRadius : lp.cardBorderRadius * 0.8,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: sel ? 0.0 : 0.06),
                      width: 1,
                    ),
                    boxShadow: null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(sel ? 14 : 11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (a.posterUrl != null && a.posterUrl!.isNotEmpty)
                          PosterImage(
                            url: a.posterUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 240,
                            fadeInDuration: const Duration(milliseconds: 100),
                            errorWidget: (_, _, _) => Container(
                              color: tp.surface,
                              child: Center(
                                child: Icon(
                                  Icons.videogame_asset,
                                  color: Colors.white12,
                                  size: 20,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: tp.surface,
                            child: Center(
                              child: Text(
                                a.appName.length > 2
                                    ? a.appName.substring(0, 2)
                                    : a.appName,
                                style: TextStyle(
                                  color: tp.accentLight,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        if (!sel)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        if (a.isRunning)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (widget.favoriteIds.contains(a.appId.toString()))
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              Icons.star,
                              color: Colors.amberAccent,
                              size: 10,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 3),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        if (s != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: inIcons ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 10)],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomPanel(ThemeProvider tp, NvApp s, AppLocalizations l) {
    final isFav = widget.favoriteIds.contains(s.appId.toString());
    final hasDesc = s.description != null && s.description!.isNotEmpty;
    final inBtns = _area == _Ps5Area.buttons;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.appName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
              shadows: [Shadow(color: Colors.black87, blurRadius: 16)],
            ),
          ),
          const SizedBox(height: 4),
          if (hasDesc)
            Text(
              s.description!.length > 60
                  ? '${s.description!.substring(0, 60)}…'
                  : s.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (s.isRunning) _chip('● ${l.running}', Colors.greenAccent),
                if (isFav) _chip('★', Colors.amberAccent),
                if (s.pluginName != null) _chip(s.pluginName!, tp.accentLight),
                ...s.metadataGenres
                    .take(2)
                    .map((g) => _chip(g, Colors.white38)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _tap();
                                widget.onAppSelected(s);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: inBtns && _btnIdx == 0
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: inBtns && _btnIdx == 0
                                            ? 0.32
                                            : 0.18,
                                      ),
                                      blurRadius: inBtns && _btnIdx == 0
                                          ? 18
                                          : 10,
                                      offset: Offset(
                                        0,
                                        inBtns && _btnIdx == 0 ? 8 : 4,
                                      ),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.black87,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.isRunning ? l.resume : l.play,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showMoreMenu(s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: inBtns && _btnIdx == 1
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.more_horiz,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),

                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: hasDesc
                          ? SingleChildScrollView(
                              child: Text(
                                s.description!.length > 250
                                    ? '${s.description!.substring(0, 250)}…'
                                    : s.description!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  height: 1.7,
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.white24,
                                  size: 16,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l.noDescription,
                                  style: const TextStyle(
                                    color: Colors.white30,
                                    fontSize: 10,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHints(ThemeProvider tp, NvApp? s, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 12),
      child: Row(
        children: [
          _hint(
            'L3',
            l.search,
            onTap: () {
              _tap();
              widget.onSearch?.call();
            },
          ),
          const SizedBox(width: 12),
          _hint(
            'R3',
            'Filter',
            onTap: () {
              _tap();
              widget.onFilter?.call();
            },
          ),
          const SizedBox(width: 12),
          _hint(
            'R1',
            l.smartFilters,
            onTap: () {
              _tap();
              widget.onSmartFilters?.call();
            },
          ),
          const Spacer(),
          _hint(
            'Ⓐ',
            l.play,
            onTap: () {
              _tap();
              if (s != null) widget.onAppSelected(s);
            },
          ),
          const SizedBox(width: 12),
          _hint(
            'X',
            'Grid',
            onTap: () {
              _tap();
              widget.onToggleView?.call();
            },
          ),
          const SizedBox(width: 12),
          _hint(
            'Ⓨ',
            l.options,
            onTap: () {
              _tap();
              if (s != null) widget.onAppDetails(s);
            },
          ),
          const SizedBox(width: 12),
          _hint(
            'SELECT',
            l.themeOptions,
            onTap: () {
              _tap();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppViewPresentationSettingsScreen(
                    preferences: context.read<LauncherPreferences>(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      t,
      style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700),
    ),
  );

  Widget _hint(String badge, String label, {VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GamepadHintIcon(badge, size: 16, forceVisible: true),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
      );
}

class _Ps5MenuItem {
  final IconData icon;
  final String label;
  final String badge;
  final VoidCallback onTap;
  const _Ps5MenuItem(this.icon, this.label, this.badge, this.onTap);
}

class _Ps5ContextMenu extends StatefulWidget {
  final List<_Ps5MenuItem> items;
  final Color accent;
  const _Ps5ContextMenu({required this.items, required this.accent});
  @override
  State<_Ps5ContextMenu> createState() => _Ps5ContextMenuState();
}

class _Ps5ContextMenuState extends State<_Ps5ContextMenu> {
  int _sel = 0;
  final _fn = FocusNode(debugLabel: 'ps5menu');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fn.requestFocus());
  }

  @override
  void dispose() {
    _fn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _fn,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowDown) {
          setState(() => _sel = (_sel + 1) % widget.items.length);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          setState(
            () => _sel = (_sel - 1 + widget.items.length) % widget.items.length,
          );
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.gameButtonA ||
            k == LogicalKeyboardKey.enter) {
          widget.items[_sel].onTap();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xF0181818),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < widget.items.length; i++)
                _menuRow(widget.items[i], i == _sel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(_Ps5MenuItem item, bool focused) {
    return GestureDetector(
      onTap: item.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: focused
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              item.icon,
              color: focused ? Colors.white : Colors.white60,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: focused ? Colors.white : Colors.white60,
                  fontSize: 14,
                  fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            GamepadHintIcon(item.badge, size: 16, forceVisible: true),
          ],
        ),
      ),
    );
  }
}
