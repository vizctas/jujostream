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

class HeroTheme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.hero;
  @override
  String name(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeHero;
  @override
  String description(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeHeroDesc;
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
    final hasRunning = apps.any((a) => a.isRunning);
    if (hasRunning) {
      sorted.sort((a, b) {
        if (a.isRunning && !b.isRunning) return -1;
        if (!a.isRunning && b.isRunning) return 1;
        return 0;
      });
    }

    return _HeroBody(
      apps: sorted,
      allApps: allApps,
      selectedIndex: 0,
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

enum _HeroView { news, home, detail }

class _HeroBody extends StatefulWidget {
  final List<NvApp> apps;
  final List<NvApp> allApps;
  final int selectedIndex;
  final ValueChanged<NvApp> onAppSelected;
  final ValueChanged<NvApp> onAppDetails;
  final ValueChanged<int> onIndexChanged;
  final String? activeSessionAppId;
  final Set<String> favoriteIds;
  final ValueChanged<NvApp> onToggleFavorite;
  final Widget? videoWidget;
  final int? videoForAppId;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final VoidCallback? onSmartFilters;
  final VoidCallback? onResumeRunning;
  final ValueChanged<bool>? onDetailViewChanged;
  final String? activeFilterLabel;

  const _HeroBody({
    required this.apps,
    required this.allApps,
    required this.selectedIndex,
    required this.onAppSelected,
    required this.onAppDetails,
    required this.onIndexChanged,
    required this.activeSessionAppId,
    required this.favoriteIds,
    required this.onToggleFavorite,
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
  State<_HeroBody> createState() => _HeroBodyState();
}

class _HeroBodyState extends State<_HeroBody>
    with SingleTickerProviderStateMixin {
  late int _idx;
  late ScrollController _iconSc;
  final FocusNode _fn = FocusNode(debugLabel: 'hero');
  final GlobalKey<NewsCarouselWidgetState> _newsKey =
      GlobalKey<NewsCarouselWidgetState>(debugLabel: 'hero-news');
  _HeroView _view = _HeroView.home;
  Timer? _bgDebounce;
  int? _bgAppId;
  int _detailBtnIdx = 0;
  static const int _detailBtnCount = 4;

  // News carousel state
  GamingNewsType? _activeNewsType;
  int _newsIndex = 0;
  bool _newsTabsFocused = true;

  static const double _iconSize = 64;
  static const double _iconSelSize = 80;
  static const double _iconGap = 12;

  @override
  void initState() {
    super.initState();
    _idx = widget.selectedIndex.clamp(
      0,
      (widget.apps.length - 1).clamp(0, 999999),
    );
    _iconSc = ScrollController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollIcons(false);
      _fn.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _HeroBody o) {
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

    final viewWidth = _iconSc.position.viewportDimension;
    final totalWidth = widget.apps.length * (_iconSize + _iconGap);
    final offset =
        (_idx * (_iconSize + _iconGap)) - (viewWidth / 2) + (_iconSize / 2);
    final clamped = offset.clamp(
      0.0,
      (totalWidth - viewWidth).clamp(0.0, double.infinity),
    );
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

  void _action() {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;

    if (_view == _HeroView.home) {
      if (k == LogicalKeyboardKey.arrowRight) {
        _move(1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        _move(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        _action();
        setState(() {
          _view = _HeroView.news;
          _newsTabsFocused = true;
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _action();
        setState(() {
          _view = _HeroView.detail;
          _detailBtnIdx = 0;
        });
        widget.onDetailViewChanged?.call(true);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter) {
        _action();
        if (_sel != null) widget.onAppSelected(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonY) {
        _action();
        if (_sel != null) widget.onAppDetails(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonX) {
        _action();
        if (_sel != null) widget.onToggleFavorite(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonThumbLeft) {
        _action();
        widget.onSearch?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonThumbRight) {
        _action();
        widget.onFilter?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight1) {
        _action();
        widget.onSmartFilters?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight2) {
        _action();
        widget.onResumeRunning?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonSelect) {
        _action();
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

    // ── News view ──
    if (_view == _HeroView.news) {
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
          _action();
          setState(() => _newsTabsFocused = false);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          _action();
          setState(() => _view = _HeroView.home);
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
          _action();
          setState(() => _newsTabsFocused = true);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown ||
            k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          _action();
          setState(() => _view = _HeroView.home);
          return KeyEventResult.handled;
        }
      }
    }

    if (_view == _HeroView.detail) {
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.gameButtonB ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.goBack) {
        _action();
        setState(() => _view = _HeroView.home);
        widget.onDetailViewChanged?.call(false);
        return KeyEventResult.handled;
      }

      if (k == LogicalKeyboardKey.arrowLeft) {
        setState(
          () =>
              _detailBtnIdx = (_detailBtnIdx - 1).clamp(0, _detailBtnCount - 1),
        );
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        setState(
          () =>
              _detailBtnIdx = (_detailBtnIdx + 1).clamp(0, _detailBtnCount - 1),
        );
        return KeyEventResult.handled;
      }

      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter) {
        _activateDetailButton();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonX) {
        _action();
        if (_sel != null) widget.onToggleFavorite(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonY) {
        _action();
        if (_sel != null) widget.onAppDetails(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonRight1) {
        _action();
        if (_sel != null) _openTrailer(_sel!);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.gameButtonSelect) {
        _action();
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

  void _activateDetailButton() {
    _action();
    final s = _sel;
    if (s == null) return;
    switch (_detailBtnIdx) {
      case 0:
        widget.onAppSelected(s);
      case 1:
        widget.onAppDetails(s);
      case 2:
        _openTrailer(s);
      case 3:
        widget.onToggleFavorite(s);
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
          if (v > 300 && _view == _HeroView.home) {
            _action();
            setState(() {
              _view = _HeroView.detail;
              _detailBtnIdx = 0;
            });
            widget.onDetailViewChanged?.call(true);
          } else if (v < -300 && _view == _HeroView.detail) {
            _action();
            setState(() => _view = _HeroView.home);
            widget.onDetailViewChanged?.call(false);
          } else if (v < -300 && _view == _HeroView.home) {
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
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(0, -0.3),
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD000000)],
                  ),
                ),
              ),
            ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_view) {
                _HeroView.news => _buildNews(tp),
                _HeroView.home => _buildHome(tp, s, l),
                _HeroView.detail => _buildDetail(tp, s, l),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNews(ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('hero_news'),
      children: [
        const Spacer(),
        NewsCarouselWidget(
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
          child: Row(
            children: [
              _badgeMini('◀▶'),
              const SizedBox(width: 4),
              Text(
                'Navigate',
                style: const TextStyle(color: Colors.white24, fontSize: 9),
              ),
              const Spacer(),
              _tappableHint('B', l.back, () {
                _action();
                setState(() => _view = _HeroView.home);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHome(ThemeProvider tp, NvApp? s, AppLocalizations l) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Column(
      key: const ValueKey('hero_home'),
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                'JUJO.Stream',
                style: TextStyle(
                  color: tp.accentLight.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.wifi,
                color: Colors.white.withValues(alpha: 0.25),
                size: 13,
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.battery_std,
                color: Colors.white.withValues(alpha: 0.25),
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        if (widget.apps.isEmpty) ...[
          const Spacer(),
          Center(
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
                        _action();
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
          const Spacer(),
        ] else ...[
          const Spacer(),

          if (s != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                s.appName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 20)],
                ),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.isRunning) _chip('● ${l.running}', Colors.greenAccent),
                if (widget.favoriteIds.contains(s.appId.toString())) ...[
                  if (s.isRunning) const SizedBox(width: 6),
                  _chip('★', Colors.amberAccent),
                ],
                if (s.pluginName != null) ...[
                  const SizedBox(width: 8),
                  _chip(s.pluginName!, tp.accentLight),
                ],
                if (s.metadataGenres.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ...s.metadataGenres
                      .take(2)
                      .map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _chip(g, Colors.white38),
                        ),
                      ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  l.details,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          if (widget.activeFilterLabel != null &&
              widget.activeFilterLabel!.isNotEmpty &&
              widget.activeFilterLabel != l.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  _action();
                  widget.onFilter?.call();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_list, color: tp.accent, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      widget.activeFilterLabel!,
                      style: TextStyle(
                        color: tp.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(
            height: _iconSelSize + 24,
            child: ListView.builder(
              controller: _iconSc,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: widget.apps.length,
              itemBuilder: (_, i) {
                final a = widget.apps[i];
                final lp = context.read<LauncherPreferences>();
                final sel = i == _idx;
                final size = sel ? _iconSelSize : _iconSize;
                return GestureDetector(
                  onTap: () {
                    if (sel) {
                      _action();
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
                        color: Colors.white.withValues(alpha: sel ? 0.0 : 0.08),
                        width: 1,
                      ),
                      boxShadow: null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(sel ? 12 : 9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (a.posterUrl != null && a.posterUrl!.isNotEmpty)
                            PosterImage(
                              url: a.posterUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          if (!sel)
                            Container(
                              color: Colors.black.withValues(alpha: 0.40),
                            ),
                          if (a.isRunning)
                            Positioned(
                              top: 3,
                              left: 3,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          if (widget.favoriteIds.contains(a.appId.toString()))
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Icon(
                                Icons.star,
                                color: Colors.amberAccent,
                                size: 9,
                                shadows: [
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
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Row(
              children: [
                _gpBtn('L3', Icons.search, l.search, () {
                  _action();
                  widget.onSearch?.call();
                }),
                const SizedBox(width: 8),
                _gpBtn('R3', Icons.filter_alt_outlined, 'Filter', () {
                  _action();
                  widget.onFilter?.call();
                }),
                const SizedBox(width: 8),
                _gpBtn('R1', Icons.filter_list, l.smartFilters, () {
                  _action();
                  widget.onSmartFilters?.call();
                }),
                const Spacer(),
                _gpBtn('A', Icons.play_arrow_rounded, l.play, () {
                  _action();
                  if (s != null) widget.onAppSelected(s);
                }),
                const SizedBox(width: 8),
                _gpBtn('X', Icons.star_outline, l.fav, () {
                  _action();
                  if (s != null) widget.onToggleFavorite(s);
                }),
                const SizedBox(width: 8),
                _gpBtn('Y', Icons.tune, l.options, () {
                  _action();
                  if (s != null) widget.onAppDetails(s);
                }),
                const SizedBox(width: 8),
                _gpBtn('SELECT', Icons.palette_outlined, l.themeOptions, () {
                  _action();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppViewPresentationSettingsScreen(
                        preferences: context.read<LauncherPreferences>(),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetail(ThemeProvider tp, NvApp? s, AppLocalizations l) {
    if (s == null) return const SizedBox.shrink();
    final isFav = widget.favoriteIds.contains(s.appId.toString());
    final hasDesc = s.description != null && s.description!.isNotEmpty;

    return Column(
      key: const ValueKey('hero_detail'),
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.only(top: 8),
          child: ListView.builder(
            controller: _iconSc,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: widget.apps.length,
            itemBuilder: (_, i) {
              final a = widget.apps[i];
              final sel = i == _idx;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: sel ? 48 : 40,
                height: sel ? 48 : 40,
                margin: EdgeInsets.only(right: 8, top: sel ? 0 : 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: sel ? 0.0 : 0.06),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(sel ? 6 : 7),
                  child: a.posterUrl != null && a.posterUrl!.isNotEmpty
                      ? PosterImage(
                          url: a.posterUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 100,
                          errorWidget: (_, _, _) =>
                              Container(color: tp.surface),
                        )
                      : Container(color: tp.surface),
                ),
              );
            },
          ),
        ),

        const Spacer(flex: 5),

        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: s.posterUrl != null && s.posterUrl!.isNotEmpty
                          ? PosterImage(
                              url: s.posterUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              errorWidget: (_, _, _) => Container(
                                color: tp.surface,
                                child: Center(
                                  child: Icon(
                                    Icons.videogame_asset_outlined,
                                    color: Colors.white24,
                                    size: 18,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: tp.surface,
                              child: Center(
                                child: Icon(
                                  Icons.videogame_asset_outlined,
                                  color: Colors.white24,
                                  size: 18,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.appName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 12),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (s.isRunning)
                              _chip('● ${l.running}', Colors.greenAccent),
                            if (isFav) _chip('★', Colors.amberAccent),
                            if (s.isHdrSupported)
                              _chip('HDR', tp.colors.accentLight),
                            if (s.pluginName != null)
                              _chip(s.pluginName!, tp.accentLight),
                            ...s.metadataGenres
                                .take(2)
                                .map((g) => _chip(g, Colors.white38)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 100,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: _detailActionBtn(
                              icon: Icons.play_arrow_rounded,
                              label: s.isRunning ? l.resume : l.play,
                              badge: 'A',
                              color: tp.accent,
                              focused: _detailBtnIdx == 0,
                              onTap: () {
                                _action();
                                widget.onAppSelected(s);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: _detailActionBtn(
                                  icon: Icons.library_books_outlined,
                                  label: l.details,
                                  badge: 'Y',
                                  focused: _detailBtnIdx == 1,
                                  onTap: () {
                                    _action();
                                    widget.onAppDetails(s);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _detailActionBtn(
                                  icon: Icons.movie_outlined,
                                  label: l.watchTrailer,
                                  badge: 'RB',
                                  focused: _detailBtnIdx == 2,
                                  onTap: () {
                                    _action();
                                    _openTrailer(s);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _detailActionBtn(
                                  icon: isFav ? Icons.star : Icons.star_outline,
                                  label: isFav ? l.removeFav : l.fav,
                                  badge: 'X',
                                  focused: _detailBtnIdx == 3,
                                  onTap: () {
                                    _action();
                                    widget.onToggleFavorite(s);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),

                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: hasDesc
                              ? SingleChildScrollView(
                                  child: Text(
                                    s.description!.length > 300
                                        ? '${s.description!.substring(0, 300)}…'
                                        : s.description!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
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
                                      size: 18,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l.noDescription,
                                      style: const TextStyle(
                                        color: Colors.white30,
                                        fontSize: 11,
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
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(40, 4, 40, 12),
          child: Row(
            children: [
              _tappableHint('A', l.play, () {
                _action();
                widget.onAppSelected(s);
              }),
              const SizedBox(width: 14),
              _tappableHint('X', l.fav, () {
                _action();
                widget.onToggleFavorite(s);
              }),
              const SizedBox(width: 14),
              _tappableHint('Y', l.options, () {
                _action();
                widget.onAppDetails(s);
              }),
              const SizedBox(width: 14),
              _tappableHint('B', l.back, () {
                _action();
                setState(() => _view = _HeroView.home);
                widget.onDetailViewChanged?.call(false);
              }),
              const Spacer(),
              _badgeMini('◀▶'),
              const SizedBox(width: 4),
              Text(
                'Navigate',
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailActionBtn({
    required IconData icon,
    required String label,
    required String badge,
    Color? color,
    bool focused = false,
    required VoidCallback onTap,
  }) {
    final tp = context.read<ThemeProvider>();
    final btnColor = color ?? Colors.white.withValues(alpha: 0.06);
    final isCta = color != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: isCta ? 14 : 10,
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: isCta
              ? (focused ? btnColor : btnColor.withValues(alpha: 0.8))
              : (focused
                    ? tp.accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused
                ? (isCta ? Colors.white.withValues(alpha: 0.5) : tp.accent)
                : (isCta
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.08)),
            width: focused ? 2 : 1,
          ),
          boxShadow: null,
        ),
        child: Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isCta || focused ? Colors.white : Colors.white60,
                  size: isCta ? 20 : 15,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: isCta || focused ? Colors.white : Colors.white60,
                      fontSize: isCta ? 15 : 10,
                      fontWeight: isCta || focused
                          ? FontWeight.w800
                          : FontWeight.w500,
                      letterSpacing: isCta ? 0.5 : 0,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(right: 2, bottom: 0, child: _badgeMini(badge)),
          ],
        ),
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

  Widget _badgeMini(String t) {
    if (t == '◀▶') {
      return const GamepadDirectionalHint(size: 15, forceVisible: true);
    }
    return GamepadHintIcon(t, size: 15, forceVisible: true);
  }

  Widget _tappableHint(String badge, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badgeMini(badge),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _gpBtn(String badge, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GamepadHintIcon(badge, size: 16, forceVisible: true),
          const SizedBox(width: 4),
          const SizedBox(width: 0),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
