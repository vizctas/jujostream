import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/theme_provider.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../../services/input/gamepad_button_helper.dart';

class AppViewPresentationSettingsScreen extends StatelessWidget {
  final LauncherPreferences preferences;

  const AppViewPresentationSettingsScreen({
    super.key,
    required this.preferences,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
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
      child: Scaffold(
      backgroundColor: const Color(0xFF101018),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).presAppearance,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        backgroundColor: const Color(0xFF101018),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh, color: Colors.white38, size: 18),
            label: Text(AppLocalizations.of(context).presReset,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            onPressed: () async {
              final l = AppLocalizations.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => Focus(
                  skipTraversal: true,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.gameButtonB ||
                        key == LogicalKeyboardKey.escape ||
                        key == LogicalKeyboardKey.goBack) {
                      Navigator.pop(ctx, false);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AlertDialog(
                    backgroundColor: ctx.read<ThemeProvider>().background,
                    title: Text(l.presReset,
                        style: const TextStyle(color: Colors.white)),
                    content: Text(
                      l.presResetConfirm,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.cancel)),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.presYes,
                              style: const TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ),
              );
              if (ok == true) await preferences.resetDefaults();
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: preferences,
        builder: (context, _) {
          final l = AppLocalizations.of(context);
          return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [

            _sectionHeader(l.presSectionBackground),
            _sliderTile(
              icon: Icons.blur_on,
              label: l.presBlur,
              value: preferences.backgroundBlur,
              min: 0,
              max: 30,
              divisions: 30,
              format: (v) => v.round().toString(),
              onChanged: preferences.setBackgroundBlur,
            ),
            _sliderTile(
              icon: Icons.brightness_4,
              label: l.presOverlayDarkness,
              value: preferences.backgroundDim,
              min: 0,
              max: 0.85,
              divisions: 17,
              format: (v) => '${(v * 100).round()}%',
              onChanged: preferences.setBackgroundDim,
            ),
            _switchTile(
              context: context,
              icon: Icons.animation,
              label: l.presParallaxDrift,
              subtitle: l.presParallaxDriftSub,
              value: preferences.enableParallaxDrift,
              onChanged: preferences.setEnableParallaxDrift,
              autofocus: true,
            ),
            if (preferences.enableParallaxDrift)
              _sliderTile(
                icon: Icons.speed,
                label: l.presParallaxSpeed,
                value: preferences.parallaxSpeed,
                min: 4,
                max: 60,
                divisions: 14,
                format: (v) => '${v.round()}s',
                onChanged: preferences.setParallaxSpeed,
                subtitle: l.presParallaxSpeedSub,
              ),

            const SizedBox(height: 8),

            _sectionHeader(l.presSectionCards),
            _sliderTile(
              icon: Icons.crop_square,
              label: l.presBorderRadius,
              value: preferences.cardBorderRadius,
              min: 0,
              max: 28,
              divisions: 28,
              format: (v) => '${v.round()}px',
              onChanged: preferences.setCardBorderRadius,
            ),
            _sliderTile(
              icon: Icons.space_bar,
              label: l.presCardSpacing,
              value: preferences.cardSpacing,
              min: 2,
              max: 28,
              divisions: 26,
              format: (v) => '${v.round()}px',
              onChanged: preferences.setCardSpacing,
            ),
            _sliderTile(
              icon: Icons.width_normal,
              label: l.presCardWidth,
              value: preferences.cardWidth,
              min: 100,
              max: 240,
              divisions: 14,
              format: (v) => '${v.round()}px',
              onChanged: preferences.setCardWidth,
            ),
            _sliderTile(
              icon: Icons.height,
              label: l.presCardHeight,
              value: preferences.cardHeight,
              min: 140,
              max: 320,
              divisions: 18,
              format: (v) => '${v.round()}px',
              onChanged: preferences.setCardHeight,
            ),
            _switchTile(
              context: context,
              icon: Icons.label_outline,
              label: l.presShowGameName,
              value: preferences.showCardLabels,
              onChanged: preferences.setShowCardLabels,
            ),
            _switchTile(
              context: context,
              icon: Icons.fiber_manual_record,
              label: l.presRunningIndicator,
              subtitle: l.presRunningIndicatorSub,
              value: preferences.showRunningBadge,
              onChanged: preferences.setShowRunningBadge,
            ),

            const SizedBox(height: 8),

            _sectionHeader(l.presSectionCategoryBar),
            _switchTile(
              context: context,
              icon: Icons.filter_list,
              label: l.presShowFilterBar,
              subtitle: l.presFilterBarSub,
              value: preferences.showCategoryBar,
              onChanged: preferences.setShowCategoryBar,
            ),
            if (preferences.showCategoryBar)
              _switchTile(
                context: context,
                icon: Icons.numbers,
                label: l.presShowCounts,
                subtitle: l.presShowCountsSub,
                value: preferences.showCategoryCounts,
                onChanged: preferences.setShowCategoryCounts,
              ),

            const SizedBox(height: 8),

            _sectionHeader(l.presSectionSearch),
            _switchTile(
              context: context,
              icon: Icons.search,
              label: l.presInstantSearch,
              subtitle: l.presInstantSearchSub,
              value: preferences.searchActivatesOnType,
              onChanged: preferences.setSearchActivatesOnType,
            ),

            const SizedBox(height: 24),
          ],
        );
        },
      ),
    ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
    String? subtitle,
  }) {
    return _FocusableSliderTile(
      icon: icon,
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      format: format,
      onChanged: onChanged,
      subtitle: subtitle,
    );
  }

  Widget _switchTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
    bool autofocus = false,
  }) {
    return _FocusBorderCard(
      child: Card(
        color: context.read<ThemeProvider>().surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile(
          autofocus: autofocus,
          secondary: Icon(icon, color: Colors.white38, size: 20),
          title: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style:
                      const TextStyle(color: Colors.white30, fontSize: 12))
              : null,
          value: value,
          onChanged: onChanged,
          activeThumbColor: context.read<ThemeProvider>().accentLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        ),
      ),
    );
  }

  Widget _choiceTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return _FocusBorderCard(
      child: Card(
        color: context.read<ThemeProvider>().surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: Colors.white38, size: 20),
          title: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ButtonSchemePicker extends StatefulWidget {
  final String current;
  const _ButtonSchemePicker({required this.current});
  @override
  State<_ButtonSchemePicker> createState() => _ButtonSchemePickerState();
}

class _ButtonSchemePickerState extends State<_ButtonSchemePicker> {
  late int _idx;

  @override
  void initState() {
    super.initState();
    _idx = widget.current == 'playstation' ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    const schemes = [
      {'id': 'xbox', 'label': 'Xbox', 'icon': Icons.gamepad},
      {'id': 'playstation', 'label': 'PlayStation', 'icon': Icons.sports_esports},
    ];
    return Focus(
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
          setState(() => _idx = 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
          setState(() => _idx = 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          Navigator.pop(context, schemes[_idx]['id'] as String);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: context.read<ThemeProvider>().background,
        title: const Text('Button Style', style: TextStyle(color: Colors.white, fontSize: 16)),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(schemes.length, (i) {
            final s = schemes[i];
            final sel = i == _idx;
            return GestureDetector(
              onTap: () => Navigator.pop(context, s['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? context.read<ThemeProvider>().accentLight.withValues(alpha: 0.4) : Colors.white12,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(s['icon'] as IconData,
                        color: sel ? Colors.white : Colors.white38, size: 20),
                    const SizedBox(width: 12),
                    Text(s['label'] as String,
                        style: TextStyle(
                          color: sel ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        )),
                    const Spacer(),
                    if (widget.current == s['id'])
                      Icon(Icons.check, color: context.read<ThemeProvider>().accentLight, size: 18),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FocusableSliderTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final String? subtitle;

  const _FocusableSliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    this.subtitle,
  });

  @override
  State<_FocusableSliderTile> createState() => _FocusableSliderTileState();
}

class _FocusableSliderTileState extends State<_FocusableSliderTile> {
  bool _focused = false;
  bool _editing = false;

  double get _step => (widget.max - widget.min) / widget.divisions;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (_editing) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        final v = (widget.value - _step).clamp(widget.min, widget.max);
        widget.onChanged(v);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        final v = (widget.value + _step).clamp(widget.min, widget.max);
        widget.onChanged(v);
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
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
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
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _editing
        ? context.read<ThemeProvider>().accentLight.withValues(alpha: 0.5)
        : _focused
            ? context.read<ThemeProvider>().accentLight.withValues(alpha: 0.25)
            : Colors.transparent;

    return Focus(
      onFocusChange: (f) => setState(() {
        _focused = f;
        if (!f) _editing = false;
      }),
      onKeyEvent: _onKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _focused ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Card(
          color: _editing ? context.read<ThemeProvider>().surfaceVariant : context.read<ThemeProvider>().surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(widget.icon, color: Colors.white38, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (_editing)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GamepadDirectionalHint(size: 16),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _editing
                            ? context.read<ThemeProvider>().accentLight.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.format(widget.value),
                        style: TextStyle(
                            color: _editing
                                ? context.read<ThemeProvider>().accentLight
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 28),
                    child: Text(widget.subtitle!,
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 12)),
                  ),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _editing
                        ? context.read<ThemeProvider>().accentLight
                        : context.read<ThemeProvider>().accentLight.withValues(alpha: 0.5),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.06),
                    thumbColor:
                        _editing ? context.read<ThemeProvider>().accentLight : Colors.white70,
                    overlayColor: Colors.transparent,
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: ExcludeFocus(
                    child: Slider(
                      value: widget.value.clamp(widget.min, widget.max),
                      min: widget.min,
                      max: widget.max,
                      divisions: widget.divisions,
                      onChanged: widget.onChanged,
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

class _FocusBorderCard extends StatefulWidget {
  final Widget child;
  const _FocusBorderCard({required this.child});
  @override
  State<_FocusBorderCard> createState() => _FocusBorderCardState();
}

class _FocusBorderCardState extends State<_FocusBorderCard> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(skipTraversal: true);
    _node.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _node.removeListener(_rebuild);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: _node.hasFocus
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(
            color: context.read<ThemeProvider>().accentLight.withValues(alpha: 0.25), width: 1),
              )
            : null,
        child: widget.child,
      ),
    );
  }
}
