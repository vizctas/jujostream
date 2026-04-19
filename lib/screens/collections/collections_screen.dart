import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../models/game_collection.dart';
import '../../providers/theme_provider.dart';
import '../../services/database/achievement_service.dart';
import '../../services/database/collections_service.dart';
import '../../services/input/gamepad_button_helper.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<GameCollection> _collections = const [];
  bool _loading = true;

  static const _swatchColors = [
    Color(0xFF533483),
    Color(0xFF00B4D8),
    Color(0xFF06D6A0),
    Color(0xFFFFB703),
    Color(0xFFEF233C),
    Color(0xFFFF6B35),
    Color(0xFF9B5DE5),
    Color(0xFF415A77),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWip());
  }

  Future<void> _maybeShowWip() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('collections_wip_shown') ?? false;
    if (shown || !mounted) return;
    await prefs.setBool('collections_wip_shown', true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final k = event.logicalKey;
            if (k == LogicalKeyboardKey.gameButtonA ||
                k == LogicalKeyboardKey.enter ||
                k == LogicalKeyboardKey.gameButtonB ||
                k == LogicalKeyboardKey.escape ||
                k == LogicalKeyboardKey.goBack) {
              Navigator.pop(ctx);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AlertDialog(
            backgroundColor: context.read<ThemeProvider>().colors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.construction_rounded, color: Color(0xFFFFB703), size: 22),
                const SizedBox(width: 10),
                const Text('Collections — WIP',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            content: const Text(
              'This feature is still in development.\n\nYou can create and manage collections, but adding games to a collection is not available yet.',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  backgroundColor: context.read<ThemeProvider>().colors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                ),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    final cols = await CollectionsService.getAll();
    if (!mounted) return;
    setState(() {
      _collections = cols;
      _loading = false;
    });
  }

  Future<void> _createCollection() async {
    final result = await _showNameDialog(title: AppLocalizations.of(context).newCollection);
    if (result == null || result.$1.trim().isEmpty) return;
    await CollectionsService.create(result.$1.trim(), colorValue: result.$2.toARGB32());

    unawaited(AchievementService.instance.unlock('first_collection'));
    _load();
  }

  Future<void> _renameCollection(GameCollection col) async {
    final result = await _showNameDialog(
      title: AppLocalizations.of(context).renameCollection,
      initial: col.name,
      initialColor: Color(col.colorValue),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    await CollectionsService.rename(col.id!, result.$1.trim());
    _load();
  }

  Future<void> _deleteCollection(GameCollection col) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var selectedIndex = 0;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void confirm() {
              Navigator.pop(ctx, selectedIndex == 1);
            }
            return Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
                  setState(() => selectedIndex = 0);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
                  setState(() => selectedIndex = 1);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.gameButtonA) {
                  confirm();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.gameButtonB ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) {
                  Navigator.pop(ctx, false);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                backgroundColor: ctx.read<ThemeProvider>().colors.surface,
                title: Text(AppLocalizations.of(ctx).deleteCollection, style: const TextStyle(color: Colors.white)),
                content: Text(
                  '¿Eliminar "${col.name}"?',
                  style: const TextStyle(color: Colors.white70),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx, false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedIndex == 0 ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedIndex == 0 ? ctx.read<ThemeProvider>().colors.accentLight : Colors.white24,
                                width: selectedIndex == 0 ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(AppLocalizations.of(ctx).cancel, style: TextStyle(
                              color: Colors.white,
                              fontWeight: selectedIndex == 0 ? FontWeight.w700 : FontWeight.w500,
                            )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx, true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedIndex == 1 ? Colors.redAccent.withValues(alpha: 0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedIndex == 1 ? Colors.redAccent : Colors.white24,
                                width: selectedIndex == 1 ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(AppLocalizations.of(ctx).deleteCollectionConfirm, style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: selectedIndex == 1 ? FontWeight.w700 : FontWeight.w500,
                            )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    await CollectionsService.delete(col.id!);
    _load();
  }

  Future<(String, Color)?> _showNameDialog({
    required String title,
    String initial = '',
    Color? initialColor,
  }) async {
    final controller = TextEditingController(text: initial);
    Color selected = initialColor ?? _swatchColors.first;

    return showDialog<(String, Color)>(
      context: context,
      builder: (ctx) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ctx.read<ThemeProvider>().colors.surface,
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx).collectionName,
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: ctx.read<ThemeProvider>().colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(ctx).colorLabel, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _swatchColors.map((c) {
                  final isSelected = c.toARGB32() == selected.toARGB32();
                  return GestureDetector(
                    onTap: () => setDialogState(() => selected = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, (controller.text, selected));
                }
              },
              child: Text(AppLocalizations.of(ctx).save),
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.watch<ThemeProvider>().colors.background,
      appBar: AppBar(
        backgroundColor: context.read<ThemeProvider>().colors.surface,
        foregroundColor: Colors.white,
        title: Text(AppLocalizations.of(context).myCollections),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).newCollection,
            icon: const Icon(Icons.add),
            onPressed: _createCollection,
          ),
        ],
      ),
      body: Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.maybePop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _collections.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _collections.length,
                    itemBuilder: (_, i) => _buildCollectionTile(_collections[i], autofocus: i == 0),
                  ),
      ),
      floatingActionButton: _collections.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: context.read<ThemeProvider>().colors.accent,
              foregroundColor: Colors.white,
              onPressed: _createCollection,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).newCollection),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_add_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).noCollections,
            style: const TextStyle(color: Colors.white60, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).createFirstCollection,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: context.read<ThemeProvider>().colors.accent),
            onPressed: _createCollection,
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context).createCollection),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionTile(GameCollection col, {bool autofocus = false}) {
    final color = Color(col.colorValue);
    return _FocusableCollectionTile(
      col: col,
      color: color,
      autofocus: autofocus,
      gameCountLabel: '${col.appIds.length} ${col.appIds.length == 1 ? AppLocalizations.of(context).gameCount : AppLocalizations.of(context).gamesCount}',
      onRename: () => _renameCollection(col),
      onDelete: () => _deleteCollection(col),
    );
  }
}

class _FocusableCollectionTile extends StatefulWidget {
  final GameCollection col;
  final Color color;
  final bool autofocus;
  final String gameCountLabel;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FocusableCollectionTile({
    required this.col,
    required this.color,
    this.autofocus = false,
    required this.gameCountLabel,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_FocusableCollectionTile> createState() => _FocusableCollectionTileState();
}

class _FocusableCollectionTileState extends State<_FocusableCollectionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.4,
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
          widget.onRename();
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.gameButtonX) {
          widget.onDelete();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onRename,
        onLongPress: widget.onDelete,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? widget.color.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? widget.color : Colors.white.withValues(alpha: 0.08),
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: widget.color.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 1)]
                : null,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: widget.color.withValues(alpha: 0.22),
                radius: 20,
                child: Icon(Icons.folder_outlined, color: widget.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.col.name,
                      style: TextStyle(
                        color: _focused ? Colors.white : Colors.white,
                        fontSize: 14,
                        fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.gameCountLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (_focused) ...[

                Row(mainAxisSize: MainAxisSize.min, children: [
                  GamepadHintIcon('A', size: 12),
                  const SizedBox(width: 2),
                  const Text('Edit', style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(width: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  GamepadHintIcon('X', size: 12),
                  const SizedBox(width: 2),
                  const Text('Del', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.w700)),
                ]),
              ] else
                Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
