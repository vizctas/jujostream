import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/plugin_config.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/metadata/steam_connect_service.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../companion/companion_qr_screen.dart';
import 'steam_login_screen.dart';

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: tp.background,
      appBar: AppBar(
        title: Text(
          l.plugins,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tp.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.gameButtonB) {
            if (MediaQuery.viewInsetsOf(context).bottom > 0) {
              FocusManager.instance.primaryFocus?.unfocus();
            } else {
              Navigator.maybePop(context);
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            if (TvDetector.instance.isTV)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tp.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 22),
                    label: Text(
                      l.configureFromPhoneBtn,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: () => CompanionQrScreen.show(context),
                  ),
                ),
              ),
            if (TvDetector.instance.isTV) const SizedBox(height: 12),
            Expanded(
              child: Consumer<PluginsProvider>(
                builder: (context, provider, _) {
                  final plugins = provider.plugins
                      .where((p) => p.id != 'discovery_boost')
                      .toList();
                  return _PluginsBody(plugins: plugins);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adaptive plugin grid with a slide-in settings drawer.
///
/// Cards form a 1-4 column grid (by width). Dpad moves through the grid via
/// geometric focus traversal, A opens the settings drawer for the focused
/// plugin, X toggles it, B backs out (drawer first, then the screen).
class _PluginsBody extends StatefulWidget {
  const _PluginsBody({required this.plugins});

  final List<PluginConfig> plugins;

  @override
  State<_PluginsBody> createState() => _PluginsBodyState();
}

class _PluginsBodyState extends State<_PluginsBody> {
  PluginConfig? _drawerPlugin;
  int? _focusedCardIndex;
  final FocusNode _drawerFocusNode = FocusNode(debugLabel: 'pluginDrawer');
  late final List<FocusNode> _cardNodes;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _cardNodes = List.generate(
      widget.plugins.length,
      (i) => FocusNode(debugLabel: 'pluginCard$i'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _cardNodes.isNotEmpty) _cardNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _drawerFocusNode.dispose();
    for (final n in _cardNodes) {
      n.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // Column count of the current layout, kept in sync by the LayoutBuilder.
  int _cols = 3;

  /// Deterministic dpad movement over the bento grid. Geometric traversal
  /// reads mid-animation positions and lands on the wrong card, so arrows
  /// are resolved with plain col/row math instead.
  ///
  /// Indexing is strictly linear/row-major: (col1,row1)=0, (col2,row1)=1,
  /// (col3,row1)=2, (col1,row2)=3… Left/right follow that reading order and
  /// continue onto the previous/next row at the edges; up/down stay in the
  /// same column.
  bool _moveFocus(int from, int dx, int dy) {
    final n = widget.plugins.length;
    final rows = (n / _cols).ceil();
    int idx;
    if (dx != 0) {
      idx = from + dx;
      if (idx < 0 || idx >= n) return false;
    } else {
      final col = from % _cols;
      final row = from ~/ _cols + dy;
      if (row < 0 || row >= rows) return false;
      idx = row * _cols + col;
      if (idx >= n) idx = n - 1; // partial last row: land on its last card
    }
    _cardNodes[idx].requestFocus();
    return true;
  }

  void _openDrawer(int index) {
    setState(() => _drawerPlugin = widget.plugins[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drawerFocusNode.requestFocus();
    });
  }

  void _closeDrawer() {
    final closed = _drawerPlugin;
    setState(() => _drawerPlugin = null);
    if (closed != null) {
      final i = widget.plugins.indexWhere((p) => p.id == closed.id);
      // Post-frame: the grid sits in an ExcludeFocus while the drawer is
      // open, so the card can only take focus after this rebuild lands.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && i >= 0 && i < _cardNodes.length) {
          _cardNodes[i].requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = Localizations.localeOf(context).languageCode == 'es';
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      // System back closes the drawer first; only pops the screen when no
      // drawer is open.
      canPop: _drawerPlugin == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeDrawer();
      },
      child: Stack(
        children: [
          // While the drawer is open the whole grid leaves the focus tree:
          // arrows inside the drawer must never escape to the cards behind
          // the scrim.
          ExcludeFocus(
            excluding: _drawerPlugin != null,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Bento grid: the focused card's column and row tracks
                      // expand (the card grows toward a square) while every
                      // neighbor is pushed aside on the same animation curve.
                      final n = widget.plugins.length;
                      final cols = constraints.maxWidth < 640 ? 2 : 3;
                      _cols = cols;
                      final rows = (n / cols).ceil();
                      const pad = 20.0;
                      const gap = 14.0;
                      const colWeight = 1.35;
                      final innerW =
                          constraints.maxWidth - pad * 2 - gap * (cols - 1);
                      final innerH =
                          constraints.maxHeight - 12 - 24 - gap * (rows - 1);
                      final focusIdx = _drawerPlugin == null
                          ? _focusedCardIndex
                          : null;
                      final focusCol = focusIdx == null ? -1 : focusIdx % cols;
                      final focusRow = focusIdx == null ? -1 : focusIdx ~/ cols;

                      final wOther = focusCol < 0
                          ? innerW / cols
                          : innerW / (colWeight + cols - 1);
                      final wFocus = focusCol < 0 ? wOther : wOther * colWeight;
                      final baseH = (innerH / rows).clamp(138.0, 200.0);
                      final hFocus = focusRow < 0
                          ? baseH
                          : math.min(wFocus * 0.82, baseH * 1.8);

                      double colX(int c) {
                        var x = pad;
                        for (var i = 0; i < c; i++) {
                          x += (i == focusCol ? wFocus : wOther) + gap;
                        }
                        return x;
                      }

                      double rowY(int r) {
                        var y = 12.0;
                        for (var i = 0; i < r; i++) {
                          y += (i == focusRow ? hFocus : baseH) + gap;
                        }
                        return y;
                      }

                      final totalH = rowY(rows) - gap + 24 + bottomInset;
                      final canvasH = math.max(totalH, constraints.maxHeight);

                      // Scroll is driven here (not via ensureVisible): the
                      // focused row's final rect is known before the cards
                      // animate, so the scroll runs in sync with the growth.
                      if (focusIdx != null) {
                        final target =
                            (rowY(focusRow) -
                                    (constraints.maxHeight - hFocus) / 2)
                                .clamp(
                                  0.0,
                                  math.max(
                                    0.0,
                                    canvasH - constraints.maxHeight,
                                  ),
                                )
                                .toDouble();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || !_scroll.hasClients) return;
                          if ((_scroll.offset - target).abs() > 4) {
                            _scroll.animateTo(
                              target,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        });
                      }

                      return FocusTraversalGroup(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: SizedBox(
                            height: canvasH,
                            width: constraints.maxWidth,
                            child: Stack(
                              children: [
                                for (var i = 0; i < n; i++)
                                  AnimatedPositioned(
                                    key: ValueKey(widget.plugins[i].id),
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    left: colX(i % cols),
                                    top: rowY(i ~/ cols),
                                    width: i % cols == focusCol
                                        ? wFocus
                                        : wOther,
                                    height: i ~/ cols == focusRow
                                        ? hFocus
                                        : baseH,
                                    child: _PluginGridCard(
                                      plugin: widget.plugins[i],
                                      focusNode: _cardNodes[i],
                                      isDimmed:
                                          _drawerPlugin == null &&
                                          _focusedCardIndex != null &&
                                          _focusedCardIndex != i,
                                      onFocusChanged: (focused) {
                                        setState(() {
                                          if (focused) {
                                            _focusedCardIndex = i;
                                          } else if (_focusedCardIndex == i) {
                                            _focusedCardIndex = null;
                                          }
                                        });
                                      },
                                      onMove: (dx, dy) => _moveFocus(i, dx, dy),
                                      onOpen: () => _openDrawer(i),
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
                // Gamepad hint bar — same convention as the Settings screen.
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 10 + bottomInset),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GamepadHintIcon('A', size: 16),
                      const SizedBox(width: 4),
                      Text(
                        isEs ? 'Configurar' : 'Configure',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 18),
                      GamepadHintIcon('X', size: 16),
                      const SizedBox(width: 4),
                      Text(
                        isEs ? 'Activar' : 'Toggle',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 18),
                      GamepadHintIcon('B', size: 16),
                      const SizedBox(width: 4),
                      Text(
                        isEs ? 'Atrás' : 'Back',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_drawerPlugin != null) ...[
            // Scrim — isolates the drawer, tap to dismiss.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDrawer,
                child: Container(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: math.min(480, MediaQuery.sizeOf(context).width * 0.92),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, dx, child) => FractionalTranslation(
                  translation: Offset(dx, 0),
                  child: child,
                ),
                child: _PluginSettingsDrawer(
                  key: ValueKey(_drawerPlugin!.id),
                  plugin: _drawerPlugin!,
                  focusNode: _drawerFocusNode,
                  onClose: _closeDrawer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tile of the plugin grid: icon, name, type, truncated description,
/// status pill and a touch toggle. The tile fills whatever rect the bento
/// layout assigns it; only decoration and content react to focus here.
class _PluginGridCard extends StatefulWidget {
  const _PluginGridCard({
    required this.plugin,
    required this.focusNode,
    required this.isDimmed,
    required this.onFocusChanged,
    required this.onMove,
    required this.onOpen,
  });

  final PluginConfig plugin;
  final FocusNode focusNode;
  final bool isDimmed;
  final ValueChanged<bool> onFocusChanged;
  final bool Function(int dx, int dy) onMove;
  final VoidCallback onOpen;

  @override
  State<_PluginGridCard> createState() => _PluginGridCardState();
}

class _PluginGridCardState extends State<_PluginGridCard> {
  bool _focused = false;
  bool _pressed = false;

  static const _motionDuration = Duration(milliseconds: 260);
  static const _motionCurve = Curves.easeOutCubic;

  // Tabler icons (via Iconify), bundled under assets/icons/plugins/.
  static String _iconAssetFor(String id) => switch (id) {
    'metadata' => 'assets/icons/plugins/world-search.svg',
    'game_video' => 'assets/icons/plugins/video.svg',
    'smart_genre_filters' => 'assets/icons/plugins/filter.svg',
    'steam_connect' => 'assets/icons/plugins/brand-steam.svg',
    'steam_library_info' => 'assets/icons/plugins/chart-dots.svg',
    _ => 'assets/icons/plugins/puzzle.svg',
  };

  String _localizedName(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoName,
      'metadata_enrichment' => l.pluginMetadataName,
      'rawg_trailer_video' => l.pluginVideoName,
      _ => widget.plugin.name,
    };
  }

  String _localizedDescription(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoDesc,
      'metadata_enrichment' => l.pluginMetadataDesc,
      'rawg_trailer_video' => l.pluginVideoDesc,
      _ => widget.plugin.description,
    };
  }

  void _toggle() {
    final provider = context.read<PluginsProvider>();
    final newState = !widget.plugin.enabled;
    provider.setEnabled(widget.plugin.id, enabled: newState);
    if (newState && context.mounted) {
      context.read<AppListProvider>().triggerMetadataEnrichment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final provider = context.watch<PluginsProvider>();
    final enabled = widget.plugin.enabled;
    final isEs = Localizations.localeOf(context).languageCode == 'es';

    final cs = Theme.of(context).colorScheme;

    final needsSetup =
        enabled &&
        ((widget.plugin.id == 'smart_genre_filters' &&
                !provider.canUseSmartGenreFilters) ||
            (widget.plugin.id == 'steam_library_info' &&
                !provider.isEnabled('steam_connect')));

    // Category uses the theme's two accent tones — no hardcoded hues.
    final categoryColor = switch (widget.plugin.category) {
      PluginCategory.metadata => tp.accentLight,
      PluginCategory.extraMetadata => tp.secondary,
    };
    final categoryLabel = switch (widget.plugin.category) {
      PluginCategory.metadata => 'Metadata',
      PluginCategory.extraMetadata => 'Extra Metadata',
    };

    // Status pill — tinted from theme, not neon literals.
    final pillBg = needsSetup
        ? tp.warm.withValues(alpha: 0.18)
        : enabled
        ? tp.accent.withValues(alpha: 0.14)
        : cs.onSurface.withValues(alpha: 0.07);
    final pillFg = needsSetup
        ? tp.warm
        : enabled
        ? tp.accentLight
        : cs.onSurface.withValues(alpha: 0.40);
    final pillText = needsSetup
        ? (isEs ? 'Configurar' : 'Setup')
        : enabled
        ? (isEs ? 'Activo' : 'Active')
        : 'Off';

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChanged(f);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonX) {
          _toggle();
          return KeyEventResult.handled;
        }
        // Arrows are always consumed so geometric traversal never kicks in;
        // at a grid edge the focus simply stays put.
        if (key == LogicalKeyboardKey.arrowRight) {
          widget.onMove(1, 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onMove(-1, 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          widget.onMove(0, 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          widget.onMove(0, -1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: () {
            // First touch only focuses (hover equivalent); a second touch on
            // the already-focused card opens the settings drawer.
            if (widget.focusNode.hasFocus) {
              widget.onOpen();
            } else {
              widget.focusNode.requestFocus();
            }
          },
          child: AnimatedOpacity(
            opacity: widget.isDimmed ? 0.70 : 1,
            duration: _motionDuration,
            curve: _motionCurve,
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: _motionDuration,
              curve: _motionCurve,
              child: AnimatedContainer(
                duration: _motionDuration,
                curve: _motionCurve,
                padding: EdgeInsets.all(_focused ? 18 : 14),
                decoration: BoxDecoration(
                  color: _focused
                      ? Color.alphaBlend(
                          tp.accent.withValues(alpha: 0.09),
                          tp.surfaceVariant,
                        )
                      : tp.surface,
                  borderRadius: BorderRadius.circular(_focused ? 20 : 16),
                  border: Border.all(
                    color: _focused
                        ? tp.accent.withValues(alpha: 0.80)
                        : cs.onSurface.withValues(
                            alpha: widget.isDimmed ? 0.04 : 0.09,
                          ),
                    width: _focused ? 1.5 : 1,
                  ),
                  // Depth-only shadow — no coloured glow.
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: cs.shadow.withValues(
                              alpha: widget.isDimmed ? 0.06 : 0.14,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedScale(
                          scale: _focused ? 1.10 : 1,
                          duration: _motionDuration,
                          curve: _motionCurve,
                          child: SvgPicture.asset(
                            _iconAssetFor(widget.plugin.id),
                            width: 30,
                            height: 30,
                            colorFilter: ColorFilter.mode(
                              enabled || _focused
                                  ? tp.accentLight
                                  : cs.onSurface.withValues(alpha: 0.35),
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _localizedName(context),
                                style: TextStyle(
                                  color: cs.onSurface.withValues(
                                    alpha: _focused ? 1.0 : 0.88,
                                  ),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: categoryColor.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      categoryLabel,
                                      style: TextStyle(
                                        color: categoryColor.withValues(
                                          alpha: 0.70,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: pillBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pillText,
                            style: TextStyle(
                              color: pillFg,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _focused ? 12 : 10),
                    Expanded(
                      child: Text(
                        _localizedDescription(context),
                        style: TextStyle(
                          color: cs.onSurface.withValues(
                            alpha: _focused ? 0.62 : 0.42,
                          ),
                          fontSize: 12,
                          height: 1.4,
                        ),
                        maxLines: _focused ? 5 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 14,
                          color: cs.onSurface.withValues(
                            alpha: _focused ? 0.55 : 0.22,
                          ),
                        ),
                        const Spacer(),
                        ExcludeFocus(
                          child: SizedBox(
                            height: 28,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch(
                                value: enabled,
                                activeThumbColor: tp.accent,
                                onChanged: (_) => _toggle(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-docked settings drawer hosting the full plugin configuration.
class _PluginSettingsDrawer extends StatelessWidget {
  const _PluginSettingsDrawer({
    super.key,
    required this.plugin,
    required this.focusNode,
    required this.onClose,
  });

  final PluginConfig plugin;
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;
    final isEs = Localizations.localeOf(context).languageCode == 'es';

    return Container(
      decoration: BoxDecoration(
        color: tp.surfaceVariant,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        border: Border(
          left: BorderSide(color: cs.onSurface.withValues(alpha: 0.09)),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.38),
            blurRadius: 32,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEs ? 'AJUSTES DEL PLUGIN' : 'PLUGIN SETTINGS',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  GamepadHintIcon('B', size: 15),
                  const SizedBox(width: 4),
                  Text(
                    isEs ? 'Cerrar' : 'Close',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ExcludeFocus(
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.50),
                      ),
                      onPressed: onClose,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  300 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  _PluginCard(
                    plugin: plugin,
                    detailMode: true,
                    detailFocusNode: focusNode,
                    onExitDetail: onClose,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _pluginApiKeyLabels = <String, _ApiKeyInfo>{
  'metadata': _ApiKeyInfo(
    label: 'RAWG API Key',
    hint: 'Paste your rawg.io API key here',
    helpUrl: 'https://rawg.io/apidocs',
    helpText: 'Free key — register at rawg.io/apidocs',
  ),
  'steam_connect': _ApiKeyInfo(
    label: 'Steam Web API Key',
    hint: 'Paste your Steam Web API key',
    helpUrl: 'https://steamcommunity.com/dev/apikey',
    helpText: 'Get your key from steamcommunity.com/dev/apikey',
  ),
};

class _ApiKeyInfo {
  final String label;
  final String hint;
  final String helpUrl;
  final String helpText;
  const _ApiKeyInfo({
    required this.label,
    required this.hint,
    required this.helpUrl,
    required this.helpText,
  });
}

class _PluginCard extends StatefulWidget {
  const _PluginCard({
    required this.plugin,
    this.detailMode = false,
    this.detailFocusNode,
    this.onExitDetail,
  });

  final PluginConfig plugin;

  /// True when hosted in the settings drawer: always expanded, no collapse
  /// chevron, B/left at the root hands focus back (closes the drawer).
  final bool detailMode;
  final FocusNode? detailFocusNode;
  final VoidCallback? onExitDetail;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  final _keyController = TextEditingController();
  final _steamIdController = TextEditingController();

  late final FocusNode _keyFocusNode;
  late final FocusNode _steamIdFocusNode;
  bool _keyLoaded = false;
  bool _obscure = true;
  bool _isConnectingSteam = false;
  bool _showSteamAdvanced = false;
  String? _steamPersona;
  bool _cardFocused = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();

    _keyFocusNode = FocusNode(skipTraversal: true);
    _steamIdFocusNode = FocusNode(skipTraversal: true);
    if (widget.detailMode) _expanded = true;
    _loadApiKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _steamIdController.dispose();
    _keyFocusNode.dispose();
    _steamIdFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final provider = context.read<PluginsProvider>();
    final key = await provider.getApiKey(widget.plugin.id);
    final steamId = await provider.getSetting(widget.plugin.id, 'steam_id');
    final steamPersona = await provider.getSetting(
      widget.plugin.id,
      'steam_persona',
    );
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _steamIdController.text = steamId ?? '';
      _steamPersona = steamPersona;
      _keyLoaded = true;
    });
  }

  Future<void> _saveApiKey(String value) async {
    final provider = context.read<PluginsProvider>();
    await provider.setApiKey(widget.plugin.id, value.trim());
    if (value.trim().isNotEmpty && mounted) {
      context.read<AppListProvider>().triggerMetadataEnrichment();
    }
  }

  Future<void> _saveSteamId(String value) async {
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'steam_id', value.trim());
  }

  Future<void> _connectSteam() async {
    final apiKey = _keyController.text.trim();
    final steamId = _steamIdController.text.trim();

    if (steamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pluginSteamLoginFirst),
        ),
      );
      return;
    }

    if (apiKey.isEmpty) {
      await _connectSteamBasic(steamId);
      return;
    }

    setState(() => _isConnectingSteam = true);
    final info = await SteamConnectService().validateConnection(
      apiKey: apiKey,
      steamId: steamId,
    );
    if (!mounted) return;
    setState(() => _isConnectingSteam = false);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).pluginSteamValidationFailed,
          ),
        ),
      );
      return;
    }

    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'steam_id', info.steamId);
    await provider.setSetting(
      widget.plugin.id,
      'steam_persona',
      info.personaName ?? '',
    );
    if (!provider.isEnabled(widget.plugin.id)) {
      await provider.setEnabled(widget.plugin.id, enabled: true);
    }
    if (!mounted) return;
    setState(() {
      _steamIdController.text = info.steamId;
      _steamPersona = info.personaName;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          info.personaName == null
              ? '${AppLocalizations.of(context).pluginSteamConnectedMsg}.'
              : '${AppLocalizations.of(context).pluginSteamConnectedMsg}: ${info.personaName}',
        ),
      ),
    );
  }

  Future<void> _connectSteamBasic(String steamId) async {
    setState(() => _isConnectingSteam = true);
    final info = await SteamConnectService().fetchPublicProfile(steamId);
    if (!mounted) return;
    setState(() => _isConnectingSteam = false);

    final provider = context.read<PluginsProvider>();
    final persona = info?.personaName;
    if (persona != null && persona.isNotEmpty) {
      await provider.setSetting(widget.plugin.id, 'steam_persona', persona);
      if (mounted) setState(() => _steamPersona = persona);
    }
    if (!provider.isEnabled(widget.plugin.id)) {
      await provider.setEnabled(widget.plugin.id, enabled: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            persona != null
                ? '${AppLocalizations.of(context).pluginSteamConnectedMsg}: $persona'
                : AppLocalizations.of(context).pluginSteamLinkedPrivate,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginsProvider>();
    final tc = context.read<ThemeProvider>();
    final isEnabled = widget.plugin.enabled;
    final apiKeyInfo = _pluginApiKeyLabels[widget.plugin.id];
    final requiresMetadataReady = widget.plugin.id == 'smart_genre_filters';
    final requiresSteamReady = widget.plugin.id == 'steam_library_info';
    final requiresMetadataForDiscovery = widget.plugin.id == 'discovery_boost';
    final steamConnected = provider.isEnabled('steam_connect');
    final smartFiltersReady = provider.canUseSmartGenreFilters;
    // steam_connect is considered ready when a persona is stored (auto-connect
    // succeeded by either the key path or the keyless fallback path)
    final steamConnectReady =
        widget.plugin.id == 'steam_connect' &&
        (_steamPersona != null && _steamPersona!.isNotEmpty);
    final statusNeedsSetup =
        (apiKeyInfo != null &&
            _keyController.text.isEmpty &&
            !steamConnectReady) ||
        requiresMetadataReady && !smartFiltersReady ||
        requiresSteamReady && !steamConnected ||
        requiresMetadataForDiscovery && !provider.isEnabled('metadata');
    final statusIcon = statusNeedsSetup
        ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;
    final statusColor = statusNeedsSetup ? Colors.amberAccent : tc.accentLight;
    final statusText = requiresMetadataReady && !smartFiltersReady
        ? 'Metadata + API key required'
        : requiresSteamReady && !steamConnected
        ? 'Steam Connect required'
        : requiresMetadataForDiscovery && !provider.isEnabled('metadata')
        ? 'Metadata plugin required'
        : apiKeyInfo != null &&
              _keyController.text.isEmpty &&
              !steamConnectReady
        ? 'API key required'
        : 'Active';

    return Focus(
      focusNode: widget.detailFocusNode,
      onFocusChange: (focused) {
        setState(() => _cardFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (node.hasPrimaryFocus) {
          if (widget.detailMode &&
              (key == LogicalKeyboardKey.gameButtonB ||
                  key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.arrowLeft)) {
            widget.onExitDetail?.call();
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.gameButtonA) {
            if (widget.detailMode) {
              // Always expanded — A dives straight into the settings.
              if (isEnabled) {
                for (final d in node.descendants) {
                  if (d.canRequestFocus && !d.skipTraversal) {
                    d.requestFocus();
                    return KeyEventResult.handled;
                  }
                }
              }
              return KeyEventResult.handled;
            }
            setState(() => _expanded = !_expanded);
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.gameButtonX) {
            final newState = !widget.plugin.enabled;
            provider.setEnabled(widget.plugin.id, enabled: newState);
            if (newState && context.mounted) {
              context.read<AppListProvider>().triggerMetadataEnrichment();
            }
            if (newState && !_expanded) setState(() => _expanded = true);
            return KeyEventResult.handled;
          }

          if (_expanded && isEnabled && key == LogicalKeyboardKey.arrowDown) {
            for (final d in node.descendants) {
              if (d.canRequestFocus && !d.skipTraversal) {
                d.requestFocus();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape) {
          node.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.35,
                duration: const Duration(milliseconds: 200),
              );
            }
          });
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          final focusedChild = node.descendants
              .where((d) => d.hasPrimaryFocus)
              .firstOrNull;
          final firstFocusable = node.descendants
              .where((d) => d.canRequestFocus && !d.skipTraversal)
              .firstOrNull;
          if (focusedChild != null && focusedChild == firstFocusable) {
            node.requestFocus();
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: _expanded ? null : const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          color: _cardFocused ? tc.surfaceVariant : tc.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _cardFocused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: _cardFocused ? 10 : 6,
              offset: Offset(0, _cardFocused ? 4 : 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, _expanded ? 40 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: widget.detailMode
                    ? null
                    : () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _localizedName(context),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          _categoryBadge(widget.plugin.category),
                        ],
                      ),
                    ),

                    if (!widget.detailMode) ...[
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          color: _cardFocused ? Colors.white : Colors.white38,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],

                    ExcludeFocus(
                      child: Switch(
                        value: isEnabled,
                        activeThumbColor: tc.accent,
                        onChanged: (v) {
                          provider.setEnabled(widget.plugin.id, enabled: v);
                          if (v && context.mounted) {
                            context
                                .read<AppListProvider>()
                                .triggerMetadataEnrichment();

                            if (!_expanded) setState(() => _expanded = true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                Text(
                  _localizedDescription(context),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],

              if (_cardFocused)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      GamepadHintIcon('A', size: 14),
                      const SizedBox(width: 3),
                      Text(
                        widget.detailMode
                            ? 'Configure'
                            : _expanded
                            ? 'Collapse'
                            : 'Expand',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GamepadHintIcon('X', size: 14),
                      const SizedBox(width: 3),
                      Text(
                        isEnabled ? 'Disable' : 'Enable',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isEnabled) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tc.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isEnabled && _expanded) ...[
                FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      if (apiKeyInfo != null && _keyLoaded) ...[
                        // For steam_connect the sign-in flow is the primary
                        // path: the webview login auto-extracts SteamID64 and
                        // the web API key. Manual entry lives under Advanced.
                        if (widget.plugin.id == 'steam_connect') ...[
                          ElevatedButton.icon(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: tc.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 2,
                                  shadowColor: Colors.black26,
                                ).copyWith(
                                  side: WidgetStateProperty.all(
                                    BorderSide.none,
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith((
                                        states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.focused,
                                        )) {
                                          return Color.lerp(
                                            tc.accent,
                                            Colors.white,
                                            0.15,
                                          );
                                        }
                                        return tc.accent;
                                      }),
                                ),
                            icon: _isConnectingSteam
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login, size: 18),
                            label: Text(
                              _isConnectingSteam
                                  ? AppLocalizations.of(
                                      context,
                                    ).pluginSteamConnecting
                                  : AppLocalizations.of(
                                      context,
                                    ).pluginSteamLogin,
                            ),
                            onPressed: _isConnectingSteam
                                ? null
                                : () async {
                                    // Capture provider before any async gap
                                    final provider = context
                                        .read<PluginsProvider>();
                                    final result =
                                        await SteamLoginScreen.show(context);
                                    if (result == null || !mounted) return;
                                    _steamIdController.text = result.steamId;
                                    await _saveSteamId(result.steamId);
                                    if (result.hasApiKey) {
                                      _keyController.text = result.apiKey!;
                                      await _saveApiKey(result.apiKey!);
                                      await _connectSteam();
                                    } else {
                                      if (result.hasFallbackAppIds) {
                                        await provider.setSetting(
                                          widget.plugin.id,
                                          'steam_owned_appids',
                                          result.ownedAppIds.join(','),
                                        );
                                      }
                                      await _connectSteamBasic(result.steamId);
                                    }
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Inicia sesión y obtenemos tu SteamID y API key automáticamente.'
                                : 'Sign in and we grab your SteamID and API key automatically.',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          if (_steamPersona != null &&
                              _steamPersona!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${AppLocalizations.of(context).pluginSteamAccount}: $_steamPersona',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => setState(
                              () => _showSteamAdvanced = !_showSteamAdvanced,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showSteamAdvanced
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Advanced (manual SteamID / API key)',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_showSteamAdvanced) ...[
                            const SizedBox(height: 8),
                            _ApiKeyField(
                              label: 'SteamID64',
                              hint: 'SteamID64 (17 digits)',
                              helpText: '',
                              controller: _steamIdController,
                              focusNode: _steamIdFocusNode,
                              obscure: false,
                              onToggleObscure: () {},
                              onChanged: _saveSteamId,
                            ),
                            const SizedBox(height: 8),
                            _ApiKeyField(
                              label: apiKeyInfo.label,
                              hint: apiKeyInfo.hint,
                              helpText: apiKeyInfo.helpText,
                              controller: _keyController,
                              focusNode: _keyFocusNode,
                              obscure: _obscure,
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              onChanged: _saveApiKey,
                            ),
                            const SizedBox(height: 8),
                            _PluginActionButton(
                              icon: Icons.open_in_new,
                              label: 'Get Key',
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://steamcommunity.com/dev/apikey',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                        ] else ...[
                          _ApiKeyField(
                            label: apiKeyInfo.label,
                            hint: apiKeyInfo.hint,
                            helpText: apiKeyInfo.helpText,
                            controller: _keyController,
                            focusNode: _keyFocusNode,
                            obscure: _obscure,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                            onChanged: _saveApiKey,
                          ),
                          const SizedBox(height: 8),
                          if (widget.plugin.id == 'metadata')
                            _PluginActionButton(
                              icon: Icons.open_in_new,
                              label: 'Get Key',
                              onTap: () => launchUrl(
                                Uri.parse('https://rawg.io/apidocs'),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ],

                      if (widget.plugin.id == 'metadata')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'es'
                                      ? 'Es importante que los juegos tengan los nombres correctos en el servidor, o no se podrán obtener los metadatos.'
                                      : 'Games must have their correct names on the server, otherwise metadata cannot be fetched.',
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.plugin.id == 'smart_genre_filters')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.tips_and_updates_outlined,
                                color: Colors.cyanAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'es'
                                      ? 'Este plugin solo funciona cuando Metadata esta activo y la API key de RAWG ya esta configurada.'
                                      : 'This plugin only works after Metadata is enabled and a RAWG API key has been configured.',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.plugin.id == 'steam_library_info')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Muestra datos de Steam en la ficha del juego: tiempo jugado, logros, reseñas, géneros y tráiler. También filtra por 100%, pendiente y nunca iniciado. Requiere Steam Connect activo con API key.'
                                : 'Shows Steam data in the game detail card: playtime, achievements, reviews, genres and trailer. Also filters by 100%, pending and never started. Requires Steam Connect with valid API key.',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (widget.plugin.id == 'discovery_boost')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Sugerencias "similar a este juego" usando géneros/tags de metadata.'
                                : '“Similar to this game” recommendations using metadata genres/tags.',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (widget.plugin.id == 'game_video') ...[
                        const SizedBox(height: 12),
                        _FocusableToggle(
                          icon: provider.microtrailerMuted
                              ? Icons.volume_off
                              : Icons.volume_up,
                          label: AppLocalizations.of(context).pluginStartMuted,
                          value: provider.microtrailerMuted,
                          onChanged: (v) => provider.setMicrotrailerMuted(v),
                        ),
                        const SizedBox(height: 12),
                        _FocusableSlider(
                          icon: Icons.timer_outlined,
                          label: AppLocalizations.of(context).pluginVideoDelay,
                          value: provider.videoDelaySeconds.toDouble(),
                          min: 1,
                          max: 10,
                          step: 1,
                          suffix: 's',
                          onChanged: (v) =>
                              provider.setVideoDelaySeconds(v.round()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _localizedName(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoName,
      'metadata_enrichment' => l.pluginMetadataName,
      'rawg_trailer_video' => l.pluginVideoName,
      _ => widget.plugin.name,
    };
  }

  String _localizedDescription(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoDesc,
      'metadata_enrichment' => l.pluginMetadataDesc,
      'rawg_trailer_video' => l.pluginVideoDesc,
      _ => widget.plugin.description,
    };
  }

  Color _categoryColor(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => const Color(0xFF4FC3F7),
      PluginCategory.extraMetadata => const Color(0xFFCE93D8),
    };
  }

  Widget _categoryBadge(PluginCategory cat) {
    final label = switch (cat) {
      PluginCategory.metadata => 'METADATA',
      PluginCategory.extraMetadata => 'EXTRA METADATA',
    };
    final color = _categoryColor(cat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PluginActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PluginActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_PluginActionButton> createState() => _PluginActionButtonState();
}

class _PluginActionButtonState extends State<_PluginActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        context.read<ThemeProvider>().accentLight;
    return Focus(
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.86,
            duration: const Duration(milliseconds: 220),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.gameButtonA ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? accent.withValues(alpha: 0.24)
                : accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.20),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _focused ? Colors.white : accent,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _focused ? Colors.white : accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusableToggle extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FocusableToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_FocusableToggle> createState() => _FocusableToggleState();
}

class _FocusableToggleState extends State<_FocusableToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? tp.accent.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: _focused ? Colors.white70 : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
              ExcludeFocus(
                child: Switch(
                  value: widget.value,
                  activeThumbColor: tp.accent,
                  onChanged: (v) => widget.onChanged(v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusableSlider extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _FocusableSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.suffix,
    required this.onChanged,
  });

  @override
  State<_FocusableSlider> createState() => _FocusableSliderState();
}

class _FocusableSliderState extends State<_FocusableSlider> {
  bool _focused = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final borderColor = _editing
        ? const Color(0xFF7CF7FF)
        : _focused
        ? tp.accent.withValues(alpha: 0.6)
        : Colors.transparent;

    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (_editing) {
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onChanged(
              (widget.value - widget.step).clamp(widget.min, widget.max),
            );
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onChanged(
              (widget.value + widget.step).clamp(widget.min, widget.max),
            );
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        } else {
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            setState(() => _editing = true);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => setState(() => _editing = !_editing),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _editing
                ? Colors.white.withValues(alpha: 0.08)
                : _focused
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            border: (_focused || _editing)
                ? Border.all(color: borderColor, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.icon,
                    color: _focused ? Colors.white70 : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.label}: ${widget.value.round()}${widget.suffix}',
                      style: TextStyle(
                        color: _focused ? Colors.white : Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_editing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF7CF7FF).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        '◀ ▶',
                        style: TextStyle(
                          color: Color(0xFF7CF7FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _editing
                      ? const Color(0xFF7CF7FF)
                      : tp.accentLight,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: _editing ? const Color(0xFF7CF7FF) : tp.accent,
                  overlayColor: tp.accent.withValues(alpha: 0.2),
                  trackHeight: 3,
                ),
                child: ExcludeFocus(
                  child: Slider(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    divisions: ((widget.max - widget.min) / widget.step)
                        .round(),
                    label: '${widget.value.round()}${widget.suffix}',
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiKeyField extends StatefulWidget {
  const _ApiKeyField({
    required this.label,
    required this.hint,
    required this.helpText,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onChanged,
    this.focusNode,
  });

  final String label;
  final String hint;
  final String helpText;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  bool _focused = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (!_editing &&
            (key == LogicalKeyboardKey.gameButtonA ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select)) {
          setState(() => _editing = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.focusNode?.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          });
          return KeyEventResult.handled;
        }

        if (_editing &&
            (key == LogicalKeyboardKey.gameButtonB ||
                key == LogicalKeyboardKey.escape)) {
          widget.focusNode?.unfocus();
          setState(() => _editing = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(_focused ? 10 : 0),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.transparent,
          border: _focused
              ? Border.all(
                  color: _editing
                      ? const Color(0xFF7CF7FF).withValues(alpha: 0.6)
                      : tp.accent.withValues(alpha: 0.6),
                  width: 1.5,
                )
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_focused && !_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓐ Edit',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓑ Done',
                      style: TextStyle(
                        color: Color(0xFF7CF7FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _editing = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.focusNode?.requestFocus();
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                });
              },
              child: ExcludeFocus(
                excluding: !_editing,
                child: IgnorePointer(
                  ignoring: !_editing,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    obscureText: widget.obscure,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(
                        color: Colors.white24,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: tp.accent, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          widget.obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: Colors.white38,
                        ),
                        onPressed: widget.onToggleObscure,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.helpText,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusableTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  const _FocusableTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  State<_FocusableTextField> createState() => _FocusableTextFieldState();
}

class _FocusableTextFieldState extends State<_FocusableTextField> {
  bool _focused = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (!_editing &&
            (key == LogicalKeyboardKey.gameButtonA ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select)) {
          setState(() => _editing = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.focusNode.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          });
          return KeyEventResult.handled;
        }
        if (_editing &&
            (key == LogicalKeyboardKey.gameButtonB ||
                key == LogicalKeyboardKey.escape)) {
          widget.focusNode.unfocus();
          setState(() => _editing = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.transparent,
          border: _focused
              ? Border.all(
                  color: _editing
                      ? const Color(0xFF7CF7FF).withValues(alpha: 0.6)
                      : tp.accent.withValues(alpha: 0.6),
                  width: 1.5,
                )
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_focused && !_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓐ Edit',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓑ Done',
                      style: TextStyle(
                        color: Color(0xFF7CF7FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _editing = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.focusNode.requestFocus();
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                });
              },
              child: ExcludeFocus(
                excluding: !_editing,
                child: IgnorePointer(
                  ignoring: !_editing,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: tp.accent, width: 1.5),
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
