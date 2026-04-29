import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
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

class BackboneTheme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.backbone;
  @override
  String name(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeBackbone;
  @override
  String description(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeBackboneDesc;
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

    return _Body(
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

enum _View { carousel, detail, news }

class _Body extends StatefulWidget {
  final List<NvApp> apps;
  final List<NvApp> allApps;
  final int selectedIndex;
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
  const _Body({
    required this.apps,
    required this.allApps,
    required this.selectedIndex,
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
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late int _idx;
  late ScrollController _sc;
  final FocusNode _fn = FocusNode(debugLabel: 'backbone');
  final GlobalKey<NewsCarouselWidgetState> _newsKey = GlobalKey();
  _View _view = _View.carousel;
  Timer? _bgDebounce;
  int? _bgAppId;
  Timer? _idleTimer;
  bool _isIdle = false;
  int _newsRotation = 0;

  static const double _cw = 140, _ch = 80, _gap = 16;
  static const double _selW = 168, _selH = 96;

  @override
  void initState() {
    super.initState();
    _idx = widget.selectedIndex.clamp(
      0,
      (widget.apps.length - 1).clamp(0, 999999),
    );
    _sc = ScrollController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll(false);
      _fn.requestFocus();
      _resetIdleTimer();
    });
  }

  @override
  void didUpdateWidget(covariant _Body o) {
    super.didUpdateWidget(o);
    if (widget.apps.length != o.apps.length) {
      _idx = _idx.clamp(0, (widget.apps.length - 1).clamp(0, 999999));
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    _fn.dispose();
    _bgDebounce?.cancel();
    _idleTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  NvApp? get _sel => widget.apps.isNotEmpty ? widget.apps[_idx] : null;

  bool get _videoPlaying =>
      widget.videoWidget != null &&
      widget.videoForAppId == _sel?.appId &&
      _view == _View.detail;

  void _resetIdleTimer() {
    if (_isIdle) setState(() => _isIdle = false);
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _videoPlaying) setState(() => _isIdle = true);
    });
  }

  void _scroll([bool anim = true]) {
    if (!_sc.hasClients || widget.apps.isEmpty) return;
    final off = (_idx * (_cw + _gap)).clamp(0.0, _sc.position.maxScrollExtent);
    anim
        ? _sc.animateTo(
            off,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
        : _sc.jumpTo(off);
  }

  void _move(int d) {
    _resetIdleTimer();
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
    _scroll(true);
  }

  void _action() {
    _resetIdleTimer();
    HapticFeedback.mediumImpact();
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
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = e.logicalKey;
        if (_view == _View.news) {
          final consumed = _newsKey.currentState?.handleKeyEvent(k) ?? false;
          if (consumed) return KeyEventResult.handled;
          if (k == LogicalKeyboardKey.gameButtonB ||
              k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.goBack) {
            _action();
            setState(() => _view = _View.carousel);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        if (_view == _View.carousel) {
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
            _newsRotation++;
            _newsKey.currentState?.resetFocus();
            setState(() => _view = _View.news);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            _action();
            setState(() => _view = _View.detail);
            widget.onDetailViewChanged?.call(true);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonA ||
              k == LogicalKeyboardKey.enter) {
            _action();
            if (s != null) widget.onAppSelected(s);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonY) {
            _action();
            if (s != null) widget.onAppDetails(s);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonX) {
            _action();
            widget.onToggleView?.call();
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
        if (_view == _View.detail) {
          if (k == LogicalKeyboardKey.arrowUp ||
              k == LogicalKeyboardKey.gameButtonB ||
              k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.goBack) {
            _action();
            setState(() => _view = _View.carousel);
            widget.onDetailViewChanged?.call(false);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowLeft) {
            _move(-1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            _move(1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonA ||
              k == LogicalKeyboardKey.enter) {
            _action();
            if (s != null) widget.onAppSelected(s);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonX) {
            _action();
            widget.onToggleView?.call();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonY) {
            _action();
            if (s != null) widget.onAppDetails(s);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.gameButtonRight1) {
            _action();
            if (s != null) _openTrailer(s);
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
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          _resetIdleTimer();
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            _move(1);
          } else if (v > 300) {
            _move(-1);
          }
        },
        onVerticalDragEnd: (details) {
          _resetIdleTimer();
          final v = details.primaryVelocity ?? 0;
          if (v > 300) {
            if (_view == _View.news) {
              _action();
              setState(() => _view = _View.carousel);
            } else if (_view == _View.carousel) {
              _action();
              setState(() => _view = _View.detail);
              widget.onDetailViewChanged?.call(true);
            }
          } else if (v < -300) {
            if (_view == _View.detail) {
              _action();
              setState(() => _view = _View.carousel);
              widget.onDetailViewChanged?.call(false);
            } else if (_view == _View.carousel) {
              _action();
              _newsRotation++;
              _newsKey.currentState?.resetFocus();
              setState(() => _view = _View.news);
            } else if (_view == _View.news) {
              // Already at top — no-op
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.videoWidget != null &&
                widget.videoForAppId == bgApp?.appId &&
                _view == _View.detail)
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
                    memCacheWidth: 720,
                    errorWidget: (_, _, _) => Container(color: tp.background),
                  ),
                ),
              )
            else
              Positioned.fill(child: Container(color: tp.background)),

            AnimatedOpacity(
              opacity: _isIdle ? 0.15 : 1.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.50),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(0, 0.2),
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xEE000000)],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _view == _View.news
                        ? _newsView(tp)
                        : _view == _View.carousel
                            ? _carousel(tp, s, l)
                            : _detail(tp, s, l),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carousel(ThemeProvider tp, NvApp? s, AppLocalizations l) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Column(
      key: const ValueKey('c'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'JUJO.Stream',
                style: TextStyle(
                  color: tp.accentLight.withValues(alpha: 0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.wifi,
                color: Colors.white.withValues(alpha: 0.3),
                size: 12,
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.battery_std,
                color: Colors.white.withValues(alpha: 0.3),
                size: 12,
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

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
                const SizedBox(height: 16),
                if (widget.activeFilterLabel != null &&
                    widget.activeFilterLabel != l.all)
                  GestureDetector(
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
              ],
            ),
          ),
          const Spacer(),
        ] else ...[
          if (s != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
              child: Text(
                s.appName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 16)],
                ),
              ),
            ),
          if (s != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
              child: Row(
                children: [
                  if (s.isRunning) _chip('● ${l.running}', Colors.greenAccent),
                  if (widget.favoriteIds.contains(s.appId.toString())) ...[
                    if (s.isRunning) const SizedBox(width: 6),
                    const Icon(Icons.star, color: Colors.amberAccent, size: 13),
                  ],
                  if (s.pluginName != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      s.pluginName!,
                      style: TextStyle(
                        color: tp.accentLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (s.metadataGenres.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      s.metadataGenres.take(2).join(' · '),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Row(
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white24,
                  size: 13,
                ),
                const SizedBox(width: 3),
                Text(
                  l.details,
                  style: const TextStyle(color: Colors.white24, fontSize: 9),
                ),
              ],
            ),
          ),

          if (widget.activeFilterLabel != null &&
              widget.activeFilterLabel!.isNotEmpty &&
              widget.activeFilterLabel != l.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
              child: GestureDetector(
                onTap: () {
                  _action();
                  widget.onFilter?.call();
                },
                child: Row(
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
                    const SizedBox(width: 4),
                    Icon(Icons.close, color: Colors.white38, size: 11),
                  ],
                ),
              ),
            ),
          const Spacer(),

          SizedBox(
            height: _selH + 20,
            child: ListView.builder(
              controller: _sc,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 24, right: 24),
              itemCount: widget.apps.length,
              itemBuilder: (_, i) {
                final a = widget.apps[i];
                final sel = i == _idx;
                final lp = context.read<LauncherPreferences>();
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
                    width: sel ? _selW : _cw,
                    height: sel ? _selH : _ch,
                    margin: EdgeInsets.only(
                      right: _gap,
                      top: sel ? 0 : (_selH - _ch),
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(lp.cardBorderRadius),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: sel ? 0.0 : 0.10),
                        width: 1,
                      ),
                      boxShadow: null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(lp.cardBorderRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (a.posterUrl != null && a.posterUrl!.isNotEmpty)
                            PosterImage(
                              url: a.posterUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 340,
                              fadeInDuration: const Duration(milliseconds: 120),
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
                              color: Colors.black.withValues(alpha: 0.30),
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
                                size: 10,
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
                _gpBtn('L3', Icons.search, l.search, Colors.white24, () {
                  _action();
                  widget.onSearch?.call();
                }),
                const SizedBox(width: 8),
                _gpBtn(
                  'R3',
                  Icons.filter_alt_outlined,
                  'Filter',
                  Colors.white24,
                  () {
                    _action();
                    widget.onFilter?.call();
                  },
                ),
                const SizedBox(width: 8),
                _gpBtn(
                  'R1',
                  Icons.filter_list,
                  l.smartFilters,
                  Colors.white24,
                  () {
                    _action();
                    widget.onSmartFilters?.call();
                  },
                ),
                const Spacer(),
                _gpBtn('A', Icons.play_arrow_rounded, l.play, tp.accent, () {
                  _action();
                  if (s != null) widget.onAppSelected(s);
                }),
                const SizedBox(width: 8),
                _gpBtn(
                  'X',
                  Icons.grid_view_rounded,
                  'Grid',
                  Colors.cyanAccent,
                  () {
                    _action();
                    widget.onToggleView?.call();
                  },
                ),
                const SizedBox(width: 8),
                _gpBtn('Y', Icons.tune, l.options, Colors.cyanAccent, () {
                  _action();
                  if (s != null) widget.onAppDetails(s);
                }),
                const SizedBox(width: 8),
                _gpBtn(
                  'SELECT',
                  Icons.palette_outlined,
                  l.themeOptions,
                  Colors.white24,
                  () {
                    _action();
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
          ),
        ],
      ],
    );
  }

  Widget _newsView(ThemeProvider tp) {
    return Column(
      key: const ValueKey('n'),
      children: [
        Expanded(
          child: NewsCarouselWidget(
            key: _newsKey,
            allApps: widget.allApps,
            apps: widget.apps,
            visible: _view == _View.news,
            hasFocus: _view == _View.news,
            rotationSeed: _newsRotation,
            onDismiss: () {
              _action();
              setState(() => _view = _View.carousel);
            },
          ),
        ),
      ],
    );
  }

  Widget _detail(ThemeProvider tp, NvApp? s, AppLocalizations l) {
    if (s == null) return const SizedBox.shrink();
    final hasDesc = s.description != null && s.description!.isNotEmpty;
    final isFav = widget.favoriteIds.contains(s.appId.toString());

    return Column(
      key: const ValueKey('d'),
      children: [
        const Spacer(flex: 7),

        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 80,
                      height: 45,
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
              const SizedBox(height: 14),

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
                            child: GestureDetector(
                              onTap: () {
                                _action();
                                widget.onAppSelected(s);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: tp.accent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.isRunning ? l.resume : l.play,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: _secondaryBtn(
                                  Icons.library_books_outlined,
                                  l.details,
                                  'Y',
                                  tp.colors.accentLight,
                                  () {
                                    _action();
                                    widget.onAppDetails(s);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _secondaryBtn(
                                  Icons.tune_outlined,
                                  l.options,
                                  'LB',
                                  tp.colors.accentLight,
                                  () {
                                    _action();
                                    widget.onAppDetails(s);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _secondaryBtn(
                                  Icons.movie_outlined,
                                  l.watchTrailer,
                                  'RB',
                                  tp.colors.accentLight,
                                  () {
                                    _action();
                                    _openTrailer(s);
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
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.40),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: hasDesc
                              ? SingleChildScrollView(
                                  child: Text(
                                    s.description!.length > 280
                                        ? '${s.description!.substring(0, 280)}…'
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
          padding: const EdgeInsets.fromLTRB(40, 8, 40, 12),
          child: Row(
            children: [
              _tappableHint('A', l.play, () {
                _action();
                widget.onAppSelected(s);
              }),
              const SizedBox(width: 14),
              _tappableHint('X', 'Grid', () {
                _action();
                widget.onToggleView?.call();
              }),
              const SizedBox(width: 14),
              _tappableHint('Y', l.options, () {
                _action();
                widget.onAppDetails(s);
              }),
              const SizedBox(width: 14),
              _tappableHint('B', l.back, () {
                _action();
                setState(() => _view = _View.carousel);
                widget.onDetailViewChanged?.call(false);
              }),
              const Spacer(),
              _badgeMini('◀▶'),
              const SizedBox(width: 4),
              Text(
                'Navigate',
                style: const TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
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

  Widget _secondaryBtn(
    IconData icon,
    String label,
    String badge,
    Color accent,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accent.withValues(alpha: 0.85), size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),

          Positioned(right: 4, bottom: 2, child: _badgeMini(badge)),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: c.withValues(alpha: 0.30)),
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
          Text(
            label,
            style: const TextStyle(color: Colors.white24, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _gpBtn(
    String badge,
    IconData icon,
    String label,
    Color bg,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GamepadHintIcon(badge, size: 16, forceVisible: true),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
