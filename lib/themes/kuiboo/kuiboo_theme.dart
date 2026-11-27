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
import '../../widgets/news_carousel/stacked_news_sections.dart';
import '../../widgets/game_backdrop_art.dart';
import '../../widgets/poster_image.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../../screens/app_view/app_view_presentation_settings_screen.dart';
import '../launcher_theme.dart';

class KuibooTheme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.kuiboo;
  @override
  String name(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeKuiboo;
  @override
  String description(BuildContext context) =>
      AppLocalizations.of(context).launcherThemeKuibooDesc;
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
      selectedIndex: apps.isEmpty
          ? 0
          : sorted.indexOf(apps[selectedIndex.clamp(0, apps.length - 1)]),
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

enum _View { carousel, sections }

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
  final ScrollController _vSc = ScrollController();
  final FocusNode _fn = FocusNode(debugLabel: 'kuiboo');
  final GlobalKey<StackedNewsSectionsState> _sectionsKey =
      GlobalKey<StackedNewsSectionsState>();
  _View _view = _View.carousel;
  Timer? _bgDebounce;
  int? _bgAppId;

  static const double _cw = 140, _ch = 80, _gap = 16;
  // Selected card size is viewport-driven; updated on every carousel layout.
  double _selW = 336, _selH = 189;
  bool _animating = false;

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
    });
  }

  @override
  void didUpdateWidget(covariant _Body o) {
    super.didUpdateWidget(o);
    if (!identical(widget.apps, o.apps)) {
      final id = o.apps.isEmpty
          ? null
          : o.apps[_idx.clamp(0, o.apps.length - 1)].appId;
      final i = widget.apps.indexWhere((a) => a.appId == id);
      _idx = (i >= 0 ? i : widget.selectedIndex).clamp(
        0,
        (widget.apps.length - 1).clamp(0, 999999),
      );
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    _vSc.dispose();
    _fn.dispose();
    _bgDebounce?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  NvApp? get _sel => widget.apps.isNotEmpty ? widget.apps[_idx] : null;

  void _scroll([bool anim = true]) {
    if (_sc.positions.length != 1 || widget.apps.isEmpty) return;
    // List is padded by half the viewport on both sides, so the selected
    // card's centre lands on the viewport centre at this offset.
    final off = (_idx * (_cw + _gap) + _selW / 2).clamp(
      0.0,
      _sc.position.maxScrollExtent,
    );
    if (!anim) return _sc.jumpTo(off);
    _animating = true;
    _sc
        .animateTo(
          off,
          duration: MotionScope.read(context).focusDuration,
          curve: MotionScope.read(context).standardCurve,
        )
        .whenComplete(() => _animating = false);
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
    _scroll(true);
  }

  void _action() {
    HapticFeedback.mediumImpact();
  }

  // Kuiboo shows the trailer in the carousel card; sections hide it.
  // The parent schedules the preview on true and disposes it on false.
  void _setView(_View v) {
    if (v == _view) return;
    final wasVisible = _view != _View.sections;
    setState(() => _view = v);
    if (wasVisible != (v != _View.sections)) {
      widget.onDetailViewChanged?.call(!wasVisible);
    }
  }

  void _enterSections() {
    _setView(_View.sections);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _sectionsKey.currentState?.enterFromTop(),
    );
  }

  void _exitSections() {
    if (_vSc.hasClients) {
      unawaited(
        _vSc.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    _setView(_View.carousel);
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
        if (_view == _View.sections) {
          final consumed =
              _sectionsKey.currentState?.handleKeyEvent(k) ?? false;
          if (consumed) return KeyEventResult.handled;
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
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            _action();
            _enterSections();
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
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            _move(1);
          } else if (v > 300) {
            _move(-1);
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 300 &&
              _view == _View.sections &&
              _vSc.hasClients &&
              _vSc.offset <= 24) {
            _action();
            _exitSections();
          } else if (v < -300 && _view == _View.carousel) {
            _action();
            _enterSections();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bgApp != null)
              Positioned.fill(
                child: GameBackdropArt(
                  app: bgApp,
                  heroCacheWidth: context
                      .read<ThemeProvider>()
                      .backgroundArtCacheWidth,
                  fallbackColor: tp.background,
                  enableKenBurns: false,
                ),
              )
            else
              Positioned.fill(child: Container(color: tp.background)),

            Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.50)),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final vh = constraints.maxHeight;
                    return SingleChildScrollView(
                      controller: _vSc,
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          SizedBox(height: vh, child: _carousel(tp, s, l)),
                          StackedNewsSections(
                            key: _sectionsKey,
                            allApps: widget.allApps,
                            apps: widget.apps,
                            hasFocus: _view == _View.sections,
                            parentScrollController: _vSc,
                            onPlayApp: widget.onAppSelected,
                            onAppDetails: widget.onAppDetails,
                            onExitUp: () {
                              _action();
                              _exitSections();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
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
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final vw = box.maxWidth;
                final ah = box.maxHeight;
                final compact = ah < 360;
                final titleSize = compact ? 20.0 : 24.0;
                final titleBlockHeight = compact ? 100.0 : 112.0;
                final compositionGap = compact ? 12.0 : 18.0;
                final cardBudget = ah - titleBlockHeight - compositionGap;
                final maxCardHeight = cardBudget <= 1
                    ? 1.0
                    : cardBudget.clamp(1.0, ah * 0.52);
                var w = vw * 0.42;
                if (w > 720) w = 720;
                if (w * 9 / 16 > maxCardHeight) {
                  w = maxCardHeight * 16 / 9;
                }
                _selW = w;
                _selH = w * 9 / 16;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_animating) _scroll(false);
                });
                final showTrailer =
                    widget.videoWidget != null && _view == _View.carousel;
                final hasFilter =
                    widget.activeFilterLabel != null &&
                    widget.activeFilterLabel!.isNotEmpty &&
                    widget.activeFilterLabel != l.all;
                final chips = <String>[
                  if (s != null && s.metadataGenres.isNotEmpty)
                    s.metadataGenres.first,
                  if (s?.pluginName?.isNotEmpty ?? false)
                    _platform(s!.pluginName!),
                  if (s != null && s.playtimeLabel.isNotEmpty) s.playtimeLabel,
                  if (s?.isRunning ?? false) l.running,
                ];
                return Center(
                  child: SizedBox(
                    width: vw,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.appName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                ),
                                if (chips.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: chips.map(_metaChip).toList(),
                                  ),
                                ],
                                if (hasFilter)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: GestureDetector(
                                      onTap: () {
                                        _action();
                                        widget.onFilter?.call();
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.filter_list,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              widget.activeFilterLabel!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          const Icon(
                                            Icons.close,
                                            color: Colors.white54,
                                            size: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        SizedBox(height: compositionGap),
                        // Title pins top-left; carousel sits on the bottom
                        // edge with a small breathing gap.
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                height: _selH,
                                child: ListView.builder(
                                  controller: _sc,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  // Keep off-screen cards built so their posters are already
                                  // decoded when fast D-pad movement arrives.
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.pixels(800),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: vw / 2,
                                  ),
                                  itemCount: widget.apps.length,
                                  itemBuilder: (_, i) {
                                    final a = widget.apps[i];
                                    final sel = i == _idx;
                                    final lp = context
                                        .read<LauncherPreferences>();
                                    return GestureDetector(
                                      onTap: () {
                                        if (sel) {
                                          _action();
                                          widget.onAppSelected(a);
                                        } else {
                                          _move(i - _idx);
                                        }
                                      },
                                      // Touch path to details (Y on a pad).
                                      onLongPress: () {
                                        _action();
                                        widget.onAppDetails(a);
                                      },
                                      child: AnimatedContainer(
                                        key: sel
                                            ? const ValueKey(
                                                'kuiboo-focused-card',
                                              )
                                            : null,
                                        duration: MotionScope.of(
                                          context,
                                        ).focusDuration,
                                        curve: MotionScope.of(
                                          context,
                                        ).standardCurve,
                                        width: sel ? _selW : _cw,
                                        height: sel ? _selH : _ch,
                                        margin: EdgeInsets.only(
                                          right: _gap,
                                          top: sel ? 0 : (_selH - _ch),
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            lp.cardBorderRadius,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: sel ? 0.0 : 0.10,
                                            ),
                                            width: 1,
                                          ),
                                          boxShadow: null,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            lp.cardBorderRadius,
                                          ),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (a.posterUrl != null &&
                                                  a.posterUrl!.isNotEmpty)
                                                PosterImage(
                                                  url: a.posterUrl!,
                                                  cacheKey: a.artCacheKey(
                                                    'poster',
                                                  ),
                                                  fit: BoxFit.cover,
                                                  memCacheWidth: sel
                                                      ? 640
                                                      : 340,
                                                  fadeInDuration:
                                                      const Duration(
                                                        milliseconds: 120,
                                                      ),
                                                  errorWidget: (_, _, _) =>
                                                      Container(
                                                        color: tp.surface,
                                                        child: Center(
                                                          child: Icon(
                                                            Icons
                                                                .videogame_asset,
                                                            color:
                                                                Colors.white12,
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
                                                          ? a.appName.substring(
                                                              0,
                                                              2,
                                                            )
                                                          : a.appName,
                                                      style: TextStyle(
                                                        color: tp.accentLight,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (sel &&
                                                  showTrailer &&
                                                  widget.videoForAppId ==
                                                      a.appId)
                                                Positioned.fill(
                                                  child:
                                                      TweenAnimationBuilder<
                                                        double
                                                      >(
                                                        tween: Tween(
                                                          begin: 0,
                                                          end: 1,
                                                        ),
                                                        duration:
                                                            MotionScope.of(
                                                              context,
                                                            ).focusDuration,
                                                        curve: MotionScope.of(
                                                          context,
                                                        ).standardCurve,
                                                        builder:
                                                            (_, v, child) =>
                                                                Opacity(
                                                                  opacity: v,
                                                                  child: child,
                                                                ),
                                                        child:
                                                            widget.videoWidget!,
                                                      ),
                                                ),
                                              if (!sel)
                                                Container(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.30),
                                                ),
                                              if (a.isRunning)
                                                Positioned(
                                                  top: 3,
                                                  left: 3,
                                                  child: Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Colors
                                                              .greenAccent,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                ),
                                              if (widget.favoriteIds.contains(
                                                a.appId.toString(),
                                              ))
                                                Positioned(
                                                  top: 3,
                                                  right: 3,
                                                  child: Icon(
                                                    Icons.star,
                                                    color: Colors.amberAccent,
                                                    size: 10,
                                                    shadows: [
                                                      Shadow(
                                                        color: Colors.black54,
                                                        blurRadius: 3,
                                                      ),
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // Quiet metadata pill: flat fill, no border, no accent colour.
  Widget _metaChip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: const TextStyle(
        color: Color(0xE6FFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    ),
  );

  static String _platform(String plugin) {
    final p = plugin.toLowerCase();
    if (p.contains('steam')) return 'Steam';
    if (p.contains('epic')) return 'Epic';
    if (p.contains('gog')) return 'GOG';
    if (p.contains('xbox') || p.contains('gamepass')) return 'Xbox';
    if (p.contains('ubisoft') || p.contains('uplay')) return 'Ubisoft';
    if (p.contains('battle') || p.contains('blizzard')) return 'Battle.net';
    if (p.contains('origin') || p == 'ea' || p.startsWith('ea ')) return 'EA';
    return plugin;
  }
}
