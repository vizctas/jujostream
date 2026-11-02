import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theme_config.dart';
import '../../providers/theme_provider.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../../themes/launcher_theme.dart';
import '../../themes/launcher_theme_registry.dart';

/// Two single-focus rows instead of nested horizontal theme carousels.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final spanish = AppLocalizations.of(context).locale.languageCode == 'es';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AppearanceChoice<LauncherThemeId>(
          key: const ValueKey('appearance-layout'),
          title: spanish ? 'Tema de interfaz' : 'Layout Theme',
          icon: Icons.dashboard_outlined,
          value: tp.launcherThemeId,
          options: [
            for (final theme in LauncherThemeRegistry.all)
              (theme.id, theme.name(context)),
          ],
          onChanged: (id) {
            tp.setLauncherTheme(id);
            context.read<LauncherPreferences>().switchProfile(id.name);
          },
        ),
        _AppearanceChoice<AppThemeId>(
          key: const ValueKey('appearance-color'),
          title: spanish ? 'Esquema de color' : 'Color Scheme',
          icon: Icons.palette_outlined,
          value: tp.themeId,
          options: [
            for (final id in AppThemeId.values) (id, AppThemes.label(id)),
          ],
          onChanged: tp.setTheme,
        ),
      ],
    );
  }
}

class _AppearanceChoice<T> extends StatefulWidget {
  const _AppearanceChoice({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  State<_AppearanceChoice<T>> createState() => _AppearanceChoiceState<T>();
}

class _AppearanceChoiceState<T> extends State<_AppearanceChoice<T>> {
  final _focusNode = FocusNode();
  bool _opening = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_opening) return;
    _opening = true;
    final tp = context.read<ThemeProvider>();
    final selected = await showDialog<T>(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.gameButtonB): () =>
              Navigator.pop(dialogContext),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(dialogContext),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              Navigator.pop(dialogContext),
        },
        child: _activationShortcuts(
          FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SimpleDialog(
              backgroundColor: tp.surface,
              title: Text(
                widget.title,
                style: const TextStyle(color: Colors.white),
              ),
              children: [
                for (final option in widget.options)
                  Builder(
                    builder: (optionContext) {
                      final active = option.$1 == widget.value;
                      return ListTile(
                        key: ValueKey('appearance-option-${option.$1}'),
                        autofocus: active,
                        selected: active,
                        focusColor: tp.accent.withValues(alpha: 0.25),
                        textColor: Colors.white70,
                        selectedColor: tp.accentLight,
                        title: Text(option.$2),
                        trailing: active ? const Icon(Icons.check) : null,
                        onFocusChange: (focused) {
                          if (!focused) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (optionContext.mounted) {
                              Scrollable.ensureVisible(
                                optionContext,
                                alignment: 0.5,
                              );
                            }
                          });
                        },
                        onTap: () => Navigator.pop(dialogContext, option.$1),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    _opening = false;
    if (!mounted) return;
    _focusNode.requestFocus();
    if (selected != null && selected != widget.value) {
      widget.onChanged(selected);
    }
  }

  Widget _activationShortcuts(Widget child) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final label = widget.options
        .firstWhere((option) => option.$1 == widget.value)
        .$2;
    return _activationShortcuts(
      ListTile(
        focusNode: _focusNode,
        leading: Icon(widget.icon, color: Colors.white54),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(label, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        focusColor: tp.accent.withValues(alpha: 0.18),
        onTap: _pick,
      ),
    );
  }
}
