import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';

/// Gamepad-friendly grid of the bundled Focus Mode wallpapers plus "Default"
/// and (optionally) "Custom…" entries. Emits via [onSelect]:
///   ''               → built-in default
///   `asset:path`     → a bundled wallpaper
///   'custom'         → caller should open a file picker
/// Reused by the Settings picker dialog and the onboarding chooser.
class WallpaperGrid extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;
  final bool showCustom;
  final Color accent;
  final int crossAxisCount;

  const WallpaperGrid({
    super.key,
    required this.current,
    required this.onSelect,
    required this.accent,
    this.showCustom = true,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final isEs = AppLocalizations.of(context).locale.languageCode == 'es';
    final entries = <(String value, String? asset, String? label)>[
      ('', 'assets/images/focus/default_focus000.jpg',
          isEs ? 'Predeterminado' : 'Default'),
      for (final a in kFocusWallpaperAssets) ('asset:$a', a, null),
      if (showCustom) ('custom', null, isEs ? 'Personalizado…' : 'Custom…'),
    ];

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: GridView.builder(
        shrinkWrap: true,
        // Both usages (settings dialog, onboarding chapter) live inside an
        // outer scrollable; focus traversal auto-scrolls via ensureVisible.
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 16 / 9,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: entries.length,
        itemBuilder: (ctx, i) {
          final (value, asset, label) = entries[i];
          final selected =
              value == current || (value.isEmpty && current.isEmpty);
          return _WallpaperTile(
            asset: asset,
            label: label,
            selected: selected,
            accent: accent,
            autofocus: selected,
            onTap: () => onSelect(value),
          );
        },
      ),
    );
  }
}

class _WallpaperTile extends StatefulWidget {
  final String? asset;
  final String? label;
  final bool selected;
  final bool autofocus;
  final Color accent;
  final VoidCallback onTap;

  const _WallpaperTile({
    this.asset,
    this.label,
    required this.selected,
    required this.autofocus,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<_WallpaperTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused
        ? widget.accent
        : (widget.selected ? widget.accent.withValues(alpha: 0.6)
                           : Colors.white12);
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: _focused ? 3 : 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.asset != null)
                  Image.asset(
                    widget.asset!,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    errorBuilder: (_, _, _) =>
                        Container(color: Colors.white10),
                  )
                else
                  Container(
                    color: Colors.white10,
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.white54,
                      size: 28,
                    ),
                  ),
                if (widget.label != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        widget.label!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (widget.selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: widget.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings dialog wrapper around [WallpaperGrid].
class WallpaperPickerDialog extends StatelessWidget {
  final double maxWidth;
  final double maxHeight;
  final Color surface;
  final String current;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const WallpaperPickerDialog({
    super.key,
    required this.maxWidth,
    required this.maxHeight,
    required this.surface,
    required this.current,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isEs = AppLocalizations.of(context).locale.languageCode == 'es';
    final accent = Theme.of(context).colorScheme.primary;
    return Focus(
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: maxWidth,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      isEs ? 'Fondo de inicio' : 'Focus background',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: WallpaperGrid(
                        current: current,
                        accent: accent,
                        onSelect: onSelect,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
