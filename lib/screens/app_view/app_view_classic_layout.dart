part of 'app_view_screen.dart';

/// Classic launcher on 16:9 screens (TV, desktop ≥ 960 px): full-bleed art,
/// icon rail on the left, reading column, poster row at the bottom and a
/// centered game dialog. Every value comes from ClassicTokens / MASTER.md.
mixin _AppViewClassicMixin on _AppViewScreenBase {
  final FocusNode _railFocusNode = FocusNode(debugLabel: 'classic-rail');

  @override
  void dispose() {
    _railFocusNode.dispose();
    super.dispose();
  }

  @override
  bool get _useCinematicLayout {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height &&
        (TvDetector.instance.isTV ||
            size.width >= ClassicTokens.cinematicMinWidth);
  }

  @override
  void _focusRail() => _railFocusNode.requestFocus();

  void _returnToCarousel() {
    final id = _selectedAppId;
    final node = id == null ? null : _cardFocusNodes[id];
    (node ?? _screenFocusNode).requestFocus();
  }

  @override
  Widget _buildCinematicLayout(
    List<NvApp> apps,
    List<NvApp> visibleApps,
    NvApp selected,
  ) {
    final l = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final columnWidth = (size.width * ClassicTokens.readingColumnFraction)
        .clamp(0.0, ClassicTokens.readingColumnMaxWidth);
    final compact = size.height < ClassicTokens.compactHeight;
    final rowLabel = _activeFilter == _AppFilter.all
        ? l.libraryLabel
        : _filterLabel(_activeFilter);
    NvApp? running;
    for (final app in apps) {
      if (app.isRunning) {
        running = app;
        break;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIconRail(apps, running),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: ClassicTokens.tvMarginY),
              Padding(
                padding: const EdgeInsets.only(
                  left: ClassicTokens.s16,
                  right: ClassicTokens.tvMarginX,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.computer.name.toUpperCase(),
                        style: ClassicTokens.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (running != null)
                      _ClassicPill(
                        icon: Icons.play_arrow_rounded,
                        text: running.appName,
                        color: ClassicTokens.success,
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(left: ClassicTokens.s16),
                child: SizedBox(
                  width: columnWidth,
                  child: _onSelection(
                    selected,
                    (app) => _buildReadingColumn(app, compact),
                  ),
                ),
              ),
              const SizedBox(height: ClassicTokens.s24),
              _buildCarouselHintsRow(),
              Padding(
                padding: const EdgeInsets.only(left: ClassicTokens.s16),
                child: Text(
                  '${rowLabel.toUpperCase()}  ·  ${visibleApps.length}',
                  style: ClassicTokens.label,
                ),
              ),
              _buildCollapsibleCarousel(visibleApps, selected),
              _buildDiscoveryBoostSection(selected, apps),
              _buildInlineFilterBar(apps),
              const SizedBox(height: ClassicTokens.s16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadingColumn(NvApp app, bool compact) {
    final l = AppLocalizations.of(context);
    final genres =
        (app.metadataGenres.isNotEmpty ? app.metadataGenres : app.tags)
            .take(ClassicTokens.maxChips)
            .toList();
    final meta = <String>[
      if (app.playtimeLabel.isNotEmpty) '${l.timePlayed} ${app.playtimeLabel}',
      if (app.lastPlayed != null && app.lastPlayed!.isNotEmpty)
        '${l.lastSessionLabel} '
            '${_classicRelativeDate(l, DateTime.tryParse(app.lastPlayed!))}',
      if (app.pluginName != null && app.pluginName!.isNotEmpty) app.pluginName!,
      if (app.isHdrSupported) 'HDR',
    ];
    final description = app.description?.trim();
    final titleStyle = compact
        ? ClassicTokens.displayCompact
        : ClassicTokens.display;
    final metaStyle = compact ? ClassicTokens.metaCompact : ClassicTokens.meta;
    final bodyStyle = compact ? ClassicTokens.bodyCompact : ClassicTokens.body;
    final bodyLines = compact
        ? ClassicTokens.descriptionLinesCompact
        : ClassicTokens.descriptionLines;
    // +s4: glyph descenders overshoot fontSize*height and were clipped.
    double lines(TextStyle s, int n) =>
        s.fontSize! * s.height! * n + ClassicTokens.s4;

    // Every block reserves its height whether or not the app fills it, so the
    // poster row never moves when the selection changes.
    Widget fixed(double height, Widget? child) => SizedBox(
      height: height,
      child: child == null
          ? null
          : Align(alignment: Alignment.topLeft, child: child),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        fixed(
          lines(titleStyle, 1),
          Text(
            app.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        const SizedBox(height: ClassicTokens.s8),
        fixed(
          lines(metaStyle, 1),
          meta.isEmpty
              ? null
              : Text(
                  meta.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
        ),
        const SizedBox(height: ClassicTokens.s12),
        fixed(
          ClassicTokens.chipHeight,
          genres.isEmpty
              ? null
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final g in genres) ...[
                        _ClassicChip(g),
                        const SizedBox(width: ClassicTokens.s8),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(height: ClassicTokens.s12),
        fixed(
          lines(bodyStyle, bodyLines),
          Text(
            description == null || description.isEmpty
                ? l.noDescription
                : description,
            maxLines: bodyLines,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle,
          ),
        ),
      ],
    );
  }

  Widget _buildIconRail(List<NvApp> apps, NvApp? running) {
    final l = AppLocalizations.of(context);
    return FocusScope(
      onKeyEvent: _onRailKey,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SizedBox(
          width: ClassicTokens.railWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ClassicTokens.tvMarginY - ClassicTokens.s8,
            ),
            child: Column(
              children: [
                _ClassicFocusable(
                  label: l.back,
                  onTap: () => Navigator.maybePop(context),
                  builder: (focused) => _railIcon(Icons.arrow_back, focused),
                ),
                const SizedBox(height: ClassicTokens.s24),
                _ClassicFocusable(
                  label: l.search,
                  focusNode: _railFocusNode,
                  onTap: _openSearch,
                  builder: (focused) => _railIcon(Icons.search, focused),
                ),
                _ClassicFocusable(
                  label: l.gridView,
                  onTap: () => _toggleViewMode(apps),
                  builder: (focused) =>
                      _railIcon(Icons.grid_view_rounded, focused),
                ),
                _ClassicFocusable(
                  label: l.smartFilters,
                  onTap: _openSmartGenreFilters,
                  builder: (focused) =>
                      _railIcon(Icons.auto_awesome_outlined, focused),
                ),
                _ClassicFocusable(
                  label: l.settings,
                  onTap: () {
                    _feedbackAction();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppViewPresentationSettingsScreen(
                          preferences: context.read<LauncherPreferences>(),
                        ),
                      ),
                    );
                  },
                  builder: (focused) => _railIcon(Icons.tune, focused),
                ),
                const Spacer(),
                if (running != null)
                  _ClassicFocusable(
                    label: l.quitSession,
                    onTap: () =>
                        _confirmQuitApp(context.read<AppListProvider>()),
                    builder: (focused) => _railIcon(
                      Icons.stop_circle_outlined,
                      focused,
                      color: ClassicTokens.danger,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _railIcon(IconData icon, bool focused, {Color? color}) {
    return SizedBox(
      width: ClassicTokens.s48,
      height: ClassicTokens.s48,
      child: Icon(
        icon,
        size: ClassicTokens.s24,
        color: focused
            ? (color ?? ClassicTokens.accentLight(_tp))
            : (color ?? ClassicTokens.textFaint),
      ),
    );
  }

  KeyEventResult _onRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final focused = FocusManager.instance.primaryFocus;
    if (key == LogicalKeyboardKey.arrowUp) {
      focused?.focusInDirection(TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (focused?.focusInDirection(TraversalDirection.down) != true) {
        _returnToCarousel();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _returnToCarousel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      // The screen-level handler would otherwise launch the selected game.
      final ctx = focused?.context;
      if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void _showClassicGameDialog(NvApp app) {
    final colors = _tp;
    final achievement = _achievementCache[app.appId];
    final reduce = MotionScope.read(context).reduceMotion;
    Navigator.of(context, rootNavigator: true).push(
      _ClassicDialogRoute(
        scrim: ClassicTokens.bg(
          colors,
        ).withValues(alpha: ClassicTokens.scrimAlpha),
        reduceMotion: reduce,
        builder: (ctx) => _ClassicGameDialog(
          app: app,
          colors: colors,
          achievement: achievement,
          onPlay: () {
            Navigator.pop(ctx);
            _launchApp(app);
          },
          onDetails: () {
            Navigator.pop(ctx);
            _openDetailsScreen(app);
          },
          onMore: () {
            Navigator.pop(ctx);
            _showActionsSheet(
              context.read<AppListProvider>().apps.toList(),
              app,
            );
          },
        ),
      ),
    );
  }
}

String _classicRelativeDate(AppLocalizations l, DateTime? date) {
  if (date == null) return l.never;
  final diff = DateTime.now().difference(date);
  if (diff.inDays == 0) return l.todayLabel;
  if (diff.inDays == 1) return l.yesterdayLabel;
  if (diff.inDays < 30) return l.daysAgo(diff.inDays);
  if (diff.inDays < 365) return l.monthsAgo(diff.inDays ~/ 30);
  return l.yearsAgo(diff.inDays ~/ 365);
}

class _ClassicDialogRoute extends RawDialogRoute<void> {
  _ClassicDialogRoute({
    required WidgetBuilder builder,
    required Color scrim,
    required bool reduceMotion,
  }) : _reduceMotion = reduceMotion,
       super(
         pageBuilder: (ctx, _, _) => builder(ctx),
         barrierColor: scrim,
         barrierDismissible: true,
         barrierLabel: 'dismiss',
         transitionDuration: reduceMotion
             ? Duration.zero
             : ClassicTokens.dialogIn,
         transitionBuilder: (_, animation, _, child) {
           final curved = animation.drive(
             CurveTween(curve: ClassicTokens.curve),
           );
           // Enter: fade + rise + settle from 0.94. Exit: fade, sink to 0.98.
           // Opacity finishes early so the card is solid while it settles.
           final exiting = animation.status == AnimationStatus.reverse;
           final t = curved.value;
           final dy = exiting ? 0.0 : (1 - t) * ClassicTokens.dialogSlide;
           final scale = exiting
               ? 0.98 + 0.02 * t
               : ClassicTokens.dialogScaleFrom +
                     (1 - ClassicTokens.dialogScaleFrom) * t;
           return Opacity(
             opacity: exiting ? t : (t / 0.6).clamp(0.0, 1.0),
             child: Transform.translate(
               offset: Offset(0, dy),
               child: Transform.scale(scale: scale, child: child),
             ),
           );
         },
       );

  final bool _reduceMotion;

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : ClassicTokens.dialogOut;
}

class _ClassicGameDialog extends StatefulWidget {
  const _ClassicGameDialog({
    required this.app,
    required this.colors,
    required this.achievement,
    required this.onPlay,
    required this.onDetails,
    required this.onMore,
  });

  final NvApp app;
  final AppThemeColors colors;
  final AchievementProgress? achievement;
  final VoidCallback onPlay;
  final VoidCallback onDetails;
  final VoidCallback onMore;

  @override
  State<_ClassicGameDialog> createState() => _ClassicGameDialogState();
}

class _ClassicGameDialogState extends State<_ClassicGameDialog> {
  int _localPlaytimeSec = 0;
  DateTime? _lastSessionEnd;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final id = widget.app.appId;
    final results = await Future.wait<Object?>([
      SessionHistoryService.totalPlaytimeSec(id),
      SessionHistoryService.lastSessionEnd(id),
    ]);
    if (!mounted) return;
    setState(() {
      _localPlaytimeSec = results[0] as int;
      _lastSessionEnd = results[1] as DateTime?;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonX) {
      widget.onPlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonY) {
      widget.onDetails();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = widget.app;
    final colors = widget.colors;
    final screen = MediaQuery.sizeOf(context);
    // TV boxes report 960x540 logical px (DPR 2), which doubled every token.
    // Lay the card out on a virtual >=720p canvas and scale it down as one
    // piece, so type, chips, stats and buttons all shrink together.
    final k = (screen.height / ClassicTokens.dialogDesignHeight).clamp(
      0.6,
      1.0,
    );
    final size = screen / k;
    final width = (size.width * ClassicTokens.dialogWidthFraction).clamp(
      0.0,
      ClassicTokens.dialogMaxWidth,
    );
    final compact = size.height < ClassicTokens.dialogCompactHeight;
    final pad = compact ? ClassicTokens.s16 : ClassicTokens.s24;
    final art = GameArtPolicy.selectBackdrop(app);
    final genres =
        (app.metadataGenres.isNotEmpty ? app.metadataGenres : app.tags)
            .take(ClassicTokens.maxChips)
            .toList();
    final description = app.description?.trim();

    final playtimeSec = _localPlaytimeSec > app.playtimeMinutes * 60
        ? _localPlaytimeSec
        : app.playtimeMinutes * 60;
    final playtimeText = playtimeSec > 0
        ? SessionHistoryService.formatDuration(playtimeSec)
        : '—';
    final lastDate =
        _lastSessionEnd ??
        (app.lastPlayed == null ? null : DateTime.tryParse(app.lastPlayed!));
    final achievement = widget.achievement;
    final surface = ClassicTokens.surface(colors);

    return Focus(
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Transform.scale(
        scale: k,
        child: OverflowBox(
          maxWidth: size.width,
          maxHeight: size.height,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                maxHeight: size.height - ClassicTokens.tvMarginY * 2,
              ),
              child: Material(
                color: surface,
                borderRadius: BorderRadius.circular(ClassicTokens.radiusDialog),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: compact
                            ? ClassicTokens.dialogArtAspectCompact
                            : ClassicTokens.dialogArtAspect,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (art.hasArt)
                              PosterImage(
                                url: art.url!,
                                cacheKey: art.cacheKey,
                                fit: art.fit,
                                alignment: art.alignment,
                                memCacheWidth:
                                    ClassicTokens.dialogArtCacheWidth,
                                placeholder: (_, _) => ColoredBox(
                                  color: ClassicTokens.surfaceVariant(colors),
                                ),
                                errorWidget: (_, _, _) => ColoredBox(
                                  color: ClassicTokens.surfaceVariant(colors),
                                ),
                              )
                            else
                              ColoredBox(
                                color: ClassicTokens.surfaceVariant(colors),
                              ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: const [
                                    ClassicTokens.dialogArtFadeStart,
                                    1.0,
                                  ],
                                  colors: [
                                    surface.withValues(alpha: 0),
                                    surface,
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: ClassicTokens.s24,
                              right: ClassicTokens.s24,
                              bottom: ClassicTokens.s16,
                              child: Text(
                                app.appName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: ClassicTokens.dialogTitle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          pad,
                          ClassicTokens.s8,
                          pad,
                          pad,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (genres.isNotEmpty) ...[
                              Wrap(
                                spacing: ClassicTokens.s8,
                                runSpacing: ClassicTokens.s8,
                                children: [
                                  for (final g in genres) _ClassicChip(g),
                                ],
                              ),
                              const SizedBox(height: ClassicTokens.s16),
                            ],
                            Text(
                              description == null || description.isEmpty
                                  ? l.noDescription
                                  : description,
                              maxLines: compact ? 3 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: ClassicTokens.body,
                            ),
                            SizedBox(height: pad),
                            Row(
                              children: [
                                _ClassicStat(
                                  label: l.timePlayed,
                                  value: playtimeText,
                                ),
                                const SizedBox(width: ClassicTokens.s32),
                                _ClassicStat(
                                  label: l.lastSessionLabel,
                                  value: _classicRelativeDate(l, lastDate),
                                ),
                                if (achievement != null) ...[
                                  const SizedBox(width: ClassicTokens.s32),
                                  _ClassicStat(
                                    label: l.achievements,
                                    value:
                                        '${achievement.unlocked}/${achievement.total}',
                                    valueColor: achievement.isComplete
                                        ? ClassicTokens.success
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: ClassicTokens.line),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: pad,
                          vertical: ClassicTokens.s16,
                        ),
                        child: FocusTraversalGroup(
                          policy: WidgetOrderTraversalPolicy(),
                          child: Row(
                            children: [
                              _ClassicFocusable(
                                label: l.play,
                                autofocus: true,
                                onTap: widget.onPlay,
                                builder: (focused) => _ClassicButtonBody(
                                  icon: Icons.play_arrow_rounded,
                                  text: l.play,
                                  hint: 'X',
                                  fill: ClassicTokens.accent(colors),
                                ),
                              ),
                              const SizedBox(width: ClassicTokens.s12),
                              _ClassicFocusable(
                                label: l.details,
                                onTap: widget.onDetails,
                                builder: (focused) => _ClassicButtonBody(
                                  icon: Icons.info_outline_rounded,
                                  text: l.details,
                                  hint: 'Y',
                                ),
                              ),
                              const Spacer(),
                              _ClassicFocusable(
                                label: l.options,
                                onTap: widget.onMore,
                                builder: (focused) => const _ClassicButtonBody(
                                  icon: Icons.settings_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Focus wrapper shared by rail icons, dialog buttons: 130 ms scale 1.06 and
/// a 3 px accent ring, nothing else.
class _ClassicFocusable extends StatefulWidget {
  const _ClassicFocusable({
    required this.label,
    required this.onTap,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget Function(bool focused) builder;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_ClassicFocusable> createState() => _ClassicFocusableState();
}

class _ClassicFocusableState extends State<_ClassicFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final duration = motion.reduceMotion ? Duration.zero : ClassicTokens.focus;
    // accentLight: an accent ring on the accent-filled primary button vanished.
    final accent = ClassicTokens.accentLight(
      context.read<ThemeProvider>().colors,
    );
    // AccessibleAction.onFocusChange only fires in the "traditional"
    // highlight mode, which a preceding touch/pointer event switches off; an
    // ancestor Focus reports hasFocus regardless of highlight mode.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (_focused != f) setState(() => _focused = f);
      },
      child: AccessibleAction(
        label: widget.label,
        tooltip: widget.label,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        showFocusRing: false,
        borderRadius: BorderRadius.circular(ClassicTokens.radiusChip),
        onActivate: widget.onTap,
        child: AnimatedScale(
          scale: _focused && !motion.reduceMotion
              ? ClassicTokens.focusScale
              : 1,
          duration: duration,
          curve: ClassicTokens.curve,
          child: AnimatedContainer(
            duration: duration,
            curve: ClassicTokens.curve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                ClassicTokens.radiusChip + ClassicTokens.focusRingGap,
              ),
              border: Border.all(
                color: _focused ? accent : accent.withValues(alpha: 0),
                width: ClassicTokens.focusRingWidth,
              ),
            ),
            padding: const EdgeInsets.all(ClassicTokens.focusRingGap),
            child: widget.builder(_focused),
          ),
        ),
      ),
    );
  }
}

class _ClassicButtonBody extends StatelessWidget {
  const _ClassicButtonBody({
    required this.icon,
    this.text,
    this.hint,
    this.fill,
  });

  final IconData icon;
  final String? text;
  final String? hint;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ClassicTokens.s48,
      padding: EdgeInsets.symmetric(
        horizontal: text == null ? ClassicTokens.s12 : ClassicTokens.s24,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: fill == null ? Border.all(color: ClassicTokens.line) : null,
        borderRadius: BorderRadius.circular(ClassicTokens.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ClassicTokens.text, size: ClassicTokens.s24),
          if (text != null) ...[
            const SizedBox(width: ClassicTokens.s8),
            Text(text!, style: ClassicTokens.button),
          ],
          if (hint != null) ...[
            const SizedBox(width: ClassicTokens.s12),
            GamepadHintIcon(
              hint!,
              size: ClassicTokens.hintIconSize,
              forceVisible: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ClassicChip extends StatelessWidget {
  const _ClassicChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ClassicTokens.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: ClassicTokens.s12),
      decoration: BoxDecoration(
        border: Border.all(color: ClassicTokens.line),
        borderRadius: BorderRadius.circular(ClassicTokens.radiusChip),
      ),
      // widthFactor keeps the chip hugging its text instead of filling the row.
      child: Center(
        widthFactor: 1,
        child: Text(text, style: ClassicTokens.chip),
      ),
    );
  }
}

class _ClassicPill extends StatelessWidget {
  const _ClassicPill({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ClassicTokens.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: ClassicTokens.s12),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(ClassicTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: ClassicTokens.s16),
          const SizedBox(width: ClassicTokens.s4),
          Text(text, style: ClassicTokens.chip.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ClassicStat extends StatelessWidget {
  const _ClassicStat({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: ClassicTokens.label),
        const SizedBox(height: ClassicTokens.s4),
        Text(
          value,
          style: valueColor == null
              ? ClassicTokens.stat
              : ClassicTokens.stat.copyWith(color: valueColor),
        ),
      ],
    );
  }
}
