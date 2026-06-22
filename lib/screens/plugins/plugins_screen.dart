import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/plugin_config.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/tv/tv_focus_helpers.dart';
import '../companion/companion_qr_screen.dart';
import 'plugin_edit_screen.dart';

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
        child: FocusTraversalGroup(
          // One group spans the QR button + the plugin list so gamepad up/down
          // loops through both. Without this the QR button (outside the list's
          // group) was unreachable once focus entered the looping list.
          policy: _VerticalLoopTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              if (TvDetector.instance.isTV)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FocusTraversalOrder(
                    // Order -1 keeps the QR button first; up from the first
                    // plugin lands here, down from here enters the list.
                    order: const NumericFocusOrder(-1),
                    child: TvFocusable(
                      excludeChildFocus: true,
                      scrollOnFocus: true,
                      onSelect: () => CompanionQrScreen.show(context),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          onPressed: () => CompanionQrScreen.show(context),
                        ),
                      ),
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
                    return _PluginsList(plugins: plugins);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PluginsList extends StatefulWidget {
  final List<PluginConfig> plugins;

  const _PluginsList({required this.plugins});

  @override
  State<_PluginsList> createState() => _PluginsListState();
}

class _PluginsListState extends State<_PluginsList> {
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(
      widget.plugins.length,
      (i) => FocusNode(debugLabel: 'plugin-${widget.plugins[i].id}'),
    );
  }

  @override
  void didUpdateWidget(covariant _PluginsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugins.length != widget.plugins.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes.clear();
      _focusNodes.addAll(
        List.generate(
          widget.plugins.length,
          (i) => FocusNode(debugLabel: 'plugin-${widget.plugins[i].id}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _openEdit(PluginConfig plugin) {
    PluginEditScreen.open(context, plugin);
  }

  void _toggle(PluginConfig plugin) {
    final provider = context.read<PluginsProvider>();
    final newState = !plugin.enabled;
    provider.setEnabled(plugin.id, enabled: newState);
    if (newState) {
      context.read<AppListProvider>().triggerMetadataEnrichment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // No FocusTraversalGroup here — the parent (plugins_screen body) wraps the
    // QR button + this list in a single looping group so focus can cross between
    // them. Items keep their NumericFocusOrder for that shared policy.
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 200 + bottomPadding),
      itemCount: widget.plugins.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final plugin = widget.plugins[index];
        return FocusTraversalOrder(
          order: NumericFocusOrder(index.toDouble()),
          child: TvFocusable(
            focusNode: _focusNodes[index],
            autofocus: index == 0,
            borderRadius: 16,
            focusBorderWidth: 2,
            focusScale: 1.02,
            excludeChildFocus: true,
            scrollOnFocus: true,
            onSelect: () => _openEdit(plugin),
            onLongPress: () => _toggle(plugin),
            child: _PluginListItem(
              plugin: plugin,
              onToggle: () => _toggle(plugin),
            ),
          ),
        );
      },
    );
  }
}

class _PluginListItem extends StatelessWidget {
  final PluginConfig plugin;
  final VoidCallback onToggle;

  const _PluginListItem({required this.plugin, required this.onToggle});

  static IconData _iconFor(String pluginId) {
    return switch (pluginId) {
      'steam_connect' => Icons.videogame_asset,
      'steam_library_info' => Icons.library_books,
      'metadata' => Icons.image_search,
      'smart_genre_filters' => Icons.filter_alt,
      'discovery_boost' => Icons.recommend,
      'game_video' => Icons.movie,
      'rawg_trailer_video' => Icons.play_circle_outline,
      'startup_intro_video' => Icons.smart_display,
      'screensaver' => Icons.bedtime,
      _ => Icons.extension,
    };
  }

  Color _categoryColor(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => const Color(0xFF4FC3F7),
      PluginCategory.extraMetadata => const Color(0xFFCE93D8),
    };
  }

  String _categoryLabel(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => 'METADATA',
      PluginCategory.extraMetadata => 'EXTRA METADATA',
    };
  }

  String _localizedName(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (plugin.id) {
      'steam_library_info' => l.steamLibraryInfoName,
      'metadata_enrichment' => l.pluginMetadataName,
      'rawg_trailer_video' => l.pluginVideoName,
      _ => plugin.name,
    };
  }

  String _localizedDescription(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (plugin.id) {
      'steam_library_info' => l.steamLibraryInfoDesc,
      'metadata_enrichment' => l.pluginMetadataDesc,
      'rawg_trailer_video' => l.pluginVideoDesc,
      _ => plugin.description,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final enabled = plugin.enabled;
    final icon = _iconFor(plugin.id);
    final categoryColor = _categoryColor(plugin.category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: enabled ? tp.surface : tp.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? tp.accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
          width: enabled ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tp.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: enabled ? tp.accentLight : Colors.white54,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedName(context),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _localizedDescription(context),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _categoryLabel(plugin.category),
                        style: TextStyle(
                          color: categoryColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (enabled)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: tp.accentLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            AppLocalizations.of(context).enabled,
                            style: TextStyle(
                              color: tp.accentLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        AppLocalizations.of(context).disabled,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Always-visible gamepad hints help users discover A / X actions.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GamepadHintIcon('A', size: 12),
                  const SizedBox(width: 3),
                  const Text(
                    'Edit',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GamepadHintIcon('X', size: 12),
                  const SizedBox(width: 3),
                  Text(
                    enabled ? 'Off' : 'On',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Traversal policy that wraps up/down navigation on the plugin list.
///
/// Pressing Up on the first item jumps to the last, and pressing Down on the
/// last item jumps to the first.
class _VerticalLoopTraversalPolicy extends OrderedTraversalPolicy {
  List<FocusNode> _orderedNodes(FocusScopeNode scope) {
    final nodes = <FocusNode>[];
    for (final node in scope.traversalDescendants) {
      final context = node.context;
      if (context == null) continue;
      final order = FocusTraversalOrder.maybeOf(context);
      if (order is NumericFocusOrder) {
        nodes.add(node);
      }
    }
    nodes.sort((a, b) {
      final orderA = FocusTraversalOrder.of(a.context!) as NumericFocusOrder;
      final orderB = FocusTraversalOrder.of(b.context!) as NumericFocusOrder;
      return orderA.order.compareTo(orderB.order);
    });
    return nodes;
  }

  int? _indexOfNode(List<FocusNode> nodes, FocusNode node) {
    for (var i = 0; i < nodes.length; i++) {
      final candidate = nodes[i];
      if (candidate == node || candidate.descendants.contains(node)) {
        return i;
      }
    }
    return null;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return super.inDirection(currentNode, direction);
    }

    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);

    final nodes = _orderedNodes(scope);
    if (nodes.length < 2) {
      return super.inDirection(currentNode, direction);
    }

    final currentIndex = _indexOfNode(nodes, currentNode);
    if (currentIndex == null) {
      return super.inDirection(currentNode, direction);
    }

    final nextIndex = direction == TraversalDirection.up
        ? (currentIndex - 1 + nodes.length) % nodes.length
        : (currentIndex + 1) % nodes.length;

    nodes[nextIndex].requestFocus();
    return true;
  }
}
