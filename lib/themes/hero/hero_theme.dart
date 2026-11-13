import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../../ui/motion_scope.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../widgets/news_carousel/stacked_news_sections.dart';
import '../../widgets/game_backdrop_art.dart';
import '../../widgets/poster_image.dart';
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

enum _HeroView { home, news }

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
  final ScrollController _vSc = ScrollController();
  final FocusNode _fn = FocusNode(debugLabel: 'hero');
  final GlobalKey<StackedNewsSectionsState> _sectionsKey =
      GlobalKey<StackedNewsSectionsState>();
  _HeroView _view = _HeroView.home;
  Timer? _bgDebounce;
  // The header clock is read in build; nothing rebuilt the home view after
  // returning from HOME, so it showed the old minute until the next key.
  Timer? _clockTimer;
  int _clockMinute = -1;
  int? _bgAppId;

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
    _clockMinute = DateTime.now().minute;
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final minute = DateTime.now().minute;
      if (minute != _clockMinute && mounted) {
        setState(() => _clockMinute = minute);
      }
    });
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
    _vSc.dispose();
    _fn.dispose();
    _bgDebounce?.cancel();
    _clockTimer?.cancel();
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
            duration: MotionScope.read(context).focusDuration,
            curve: MotionScope.read(context).standardCurve,
          )
        : _iconSc.jumpTo(clamped);
  }

  void _move(int d) {
    final n = (_idx + d).clamp(0, widget.apps.length - 1);
    if (n == _idx) return;
    UiSoundService.playClick();
    // TV boxes have no vibrator; the platform-channel round trip per key was
    // pure latency on the D-pad path.
    if (!TvDetector.instance.isTV) HapticFeedback.lightImpact();
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;

    if (_view == _HeroView.news) {
      final consumed = _sectionsKey.currentState?.handleKeyEvent(k) ?? false;
      if (consumed) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }

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
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _action();
        setState(() => _view = _HeroView.news);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sectionsKey.currentState?.enterFromTop();
        });
        return KeyEventResult.handled;
      }
      // DPAD_CENTER on a TV remote arrives as `select`, not `enter`; without
      // it the centre button did nothing in this theme.
      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.select) {
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

    return KeyEventResult.ignored;
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

    // ActivateIntent is what Flutter's default shortcuts (select / enter /
    // space) and GamepadNavigationService dispatch to the focused node. The
    // raw-key path above missed the remote's centre button on FireTV.
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (_view == _HeroView.home && _sel != null) {
              _action();
              widget.onAppSelected(_sel!);
            }
            return null;
          },
        ),
      },
      child: Focus(
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
          if (v < -300 && _view == _HeroView.home) {
            _action();
            setState(() => _view = _HeroView.news);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _sectionsKey.currentState?.enterFromTop();
            });
          } else if (v > 300 &&
              _view == _HeroView.news &&
              _vSc.hasClients &&
              _vSc.offset <= 24) {
            _action();
            unawaited(
              _vSc.animateTo(
                0.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
            );
            setState(() => _view = _HeroView.home);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop + scrim live in their own raster layer. Without the
            // boundary every selection animation frame re-rasterised the
            // full-screen hero and both scrims, which alone cost ~50 ms on a
            // FireTV GPU and pinned D-pad navigation at 20 fps.
            Positioned.fill(
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.videoWidget != null &&
                        widget.videoForAppId == bgApp?.appId)
                      widget.videoWidget!
                    else if (bgApp != null)
                      GameBackdropArt(
                        app: bgApp,
                        heroCacheWidth: context
                            .read<ThemeProvider>()
                            .backgroundArtCacheWidth,
                        fallbackColor: tp.background,
                        enableKenBurns:
                            !tp.reduceEffects && !tp.performanceMode,
                      )
                    else
                      Container(color: tp.background),
                    Container(color: Colors.black.withValues(alpha: 0.45)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(0, -0.3),
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xDD000000)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            LayoutBuilder(
              builder: (context, constraints) {
                final vh = constraints.maxHeight;
                return SingleChildScrollView(
                  controller: _vSc,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(height: vh, child: _buildHome(tp, s, l)),
                      StackedNewsSections(
                        key: _sectionsKey,
                        allApps: widget.allApps,
                        apps: widget.apps,
                        hasFocus: _view == _HeroView.news,
                        parentScrollController: _vSc,
                        onPlayApp: widget.onAppSelected,
                        onAppDetails: widget.onAppDetails,
                        onExitUp: () {
                          _action();
                          setState(() => _view = _HeroView.home);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      ),
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  // A 20 px text blur is a full blur pass on every repaint of
                  // this layer; TV GPUs pay it on each navigation frame.
                  shadows: [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: TvDetector.instance.isTV ? 4 : 20,
                    ),
                  ],
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
              // Keep off-screen cards built so their posters are already
              // decoded when fast D-pad movement arrives.
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: widget.apps.length,
              itemBuilder: (_, i) {
                final a = widget.apps[i];
                final lp = context.read<LauncherPreferences>();
                final sel = i == _idx;
                final size = sel ? _iconSelSize : _iconSize;
                // One raster layer per card: a selection change repaints the
                // two cards that changed, not every clipped poster in view.
                return RepaintBoundary(
                  child: GestureDetector(
                  onTap: () {
                    if (sel) {
                      _action();
                      widget.onAppSelected(a);
                    } else {
                      _move(i - _idx);
                    }
                  },
                  child: AnimatedContainer(
                    duration: MotionScope.of(context).focusDuration,
                    curve: MotionScope.of(context).standardCurve,
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
                              cacheKey: a.artCacheKey('poster'),
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
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          if (context.watch<LauncherPreferences>().showButtonHints)
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
