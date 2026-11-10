import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../providers/computer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/preferences/launcher_preferences.dart';

class SettingsScopeEntry {
  final String? hostId;
  final String label;
  final bool isOnline;
  final bool hasOverride;

  const SettingsScopeEntry({
    required this.hostId,
    required this.label,
    this.isOnline = false,
    this.hasOverride = false,
  });

  bool get isGlobal => hostId == null || hostId!.isEmpty;
}

/// Modular scope selector & per-server override control bar for [SettingsScreen]
/// and [AppViewPresentationSettingsScreen].
///
/// Follows "The Dark Room" design system: tonal surface steps (`tp.surface`,
/// `tp.surfaceVariant`), rationed accent (`tp.accent`, `tp.accentLight`),
/// and full gamepad/TV D-pad focus support.
class SettingsScopeBar extends StatefulWidget {
  final String? fallbackServerId;
  final String? fallbackServerName;
  final EdgeInsetsGeometry padding;

  const SettingsScopeBar({
    super.key,
    this.fallbackServerId,
    this.fallbackServerName,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 6),
  });

  @override
  State<SettingsScopeBar> createState() => _SettingsScopeBarState();
}

class _SettingsScopeBarState extends State<SettingsScopeBar> {
  bool _hasCustomLauncherKeys = false;
  String? _lastCheckedHostId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshLauncherCustomCheck();
  }

  Future<void> _refreshLauncherCustomCheck() async {
    final settings = context.read<SettingsProvider>();
    final launcherPrefs = context.read<LauncherPreferences>();
    final hostId = settings.activeServerScopeId;
    if (hostId == null || hostId.isEmpty) {
      if (_hasCustomLauncherKeys || _lastCheckedHostId != null) {
        setState(() {
          _hasCustomLauncherKeys = false;
          _lastCheckedHostId = null;
        });
      }
      return;
    }
    final hasKeys = await launcherPrefs.hasServerCustomKeys(hostId);
    if (!mounted) return;
    if (_hasCustomLauncherKeys != hasKeys || _lastCheckedHostId != hostId) {
      setState(() {
        _hasCustomLauncherKeys = hasKeys;
        _lastCheckedHostId = hostId;
      });
    }
  }

  List<SettingsScopeEntry> _buildEntries(
    AppLocalizations l,
    SettingsProvider settings,
    List<ComputerDetails> computers,
  ) {
    final entries = <SettingsScopeEntry>[
      SettingsScopeEntry(
        hostId: null,
        label: l.scopeGlobalLabel,
        hasOverride: false,
      ),
    ];

    final seenIds = <String>{};
    for (final c in computers) {
      final id = c.hostId;
      if (id.isEmpty || !seenIds.add(id)) continue;
      entries.add(
        SettingsScopeEntry(
          hostId: id,
          label: c.name,
          isOnline: c.state == ComputerState.online,
          hasOverride: settings.hasServerOverride(id),
        ),
      );
    }

    final fallbackId = widget.fallbackServerId;
    if (fallbackId != null &&
        fallbackId.isNotEmpty &&
        !seenIds.contains(fallbackId)) {
      final profile = settings.serverProfile(fallbackId);
      entries.add(
        SettingsScopeEntry(
          hostId: fallbackId,
          label: (widget.fallbackServerName?.isNotEmpty == true)
              ? widget.fallbackServerName!
              : (profile?.serverName.isNotEmpty == true
                    ? profile!.serverName
                    : fallbackId),
          isOnline: false,
          hasOverride: settings.hasServerOverride(fallbackId),
        ),
      );
    }

    return entries;
  }

  Future<void> _selectScope(
    SettingsScopeEntry entry,
    SettingsProvider settings,
    LauncherPreferences launcherPrefs,
    ThemeProvider themeProvider,
  ) async {
    await settings.setScope(
      entry.hostId,
      serverName: entry.isGlobal ? null : entry.label,
      launcherPreferences: launcherPrefs,
      themeProvider: themeProvider,
    );
    await _refreshLauncherCustomCheck();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEs = l.locale.languageCode == 'es';
    final tp = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final launcherPrefs = context.watch<LauncherPreferences>();
    final computers = context.watch<ComputerProvider>().computers;

    final entries = _buildEntries(l, settings, computers);
    // If no servers exist yet and no server scope is active, keep UI minimal.
    if (entries.length <= 1 && !settings.isEditingServerScope) {
      return const SizedBox.shrink();
    }

    final activeHostId = settings.activeServerScopeId;
    final activeEntry = entries.firstWhere(
      (e) => e.hostId == activeHostId,
      orElse: () => entries.first,
    );
    final isServerSelected = !activeEntry.isGlobal;
    final overrideEnabled =
        isServerSelected && settings.hasServerOverride(activeEntry.hostId);
    final profile = isServerSelected
        ? settings.serverProfile(activeEntry.hostId)
        : null;
    final diffBadges = (profile != null && overrideEnabled)
        ? profile.diffBadges(
            settings.globalConfig,
            globalLauncherThemeName: tp.globalLauncherThemeId.name,
            isEs: isEs,
            hasCustomLauncherPrefs: _hasCustomLauncherKeys,
          )
        : const <String>[];

    return Padding(
      padding: widget.padding,
      child: Container(
        decoration: BoxDecoration(
          color: tp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: overrideEnabled
                ? tp.accent.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Scope header + horizontal server scope selector pills
            Row(
              children: [
                Icon(
                  isServerSelected
                      ? Icons.dns_rounded
                      : Icons.public_rounded,
                  size: 16,
                  color: overrideEnabled ? tp.accentLight : Colors.white54,
                ),
                const SizedBox(width: 8),
                Text(
                  l.serverConfigScopeLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < entries.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          _ScopePill(
                            key: ValueKey(
                              'settings-scope-${entries[i].hostId ?? "global"}',
                            ),
                            entry: entries[i],
                            selected: entries[i].hostId == activeEntry.hostId,
                            accent: tp.accent,
                            accentLight: tp.accentLight,
                            surfaceVariant: tp.surfaceVariant,
                            onSelect: () => _selectScope(
                              entries[i],
                              settings,
                              launcherPrefs,
                              tp,
                            ),
                            onHorizontalMove: (delta) {
                              final nextIdx = (i + delta).clamp(
                                0,
                                entries.length - 1,
                              );
                              if (nextIdx != i) {
                                _selectScope(
                                  entries[nextIdx],
                                  settings,
                                  launcherPrefs,
                                  tp,
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Row 2: Active scope description or Server Override controls
            if (!isServerSelected)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l.serverOverrideBadgeGlobal,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.scopeGlobalDesc,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tp.surfaceVariant.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: overrideEnabled
                                ? tp.accent.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            overrideEnabled
                                ? l.serverOverrideBadgeCustom
                                : l.serverOverrideBadgeGlobal,
                            style: TextStyle(
                              color: overrideEnabled
                                  ? tp.accentLight
                                  : Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${activeEntry.label} — ${l.serverOverrideToggleTitle}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                overrideEnabled
                                    ? l.serverOverrideToggleSubOn
                                    : l.serverOverrideToggleSubOff,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (overrideEnabled) ...[
                          const SizedBox(width: 8),
                          _FocusableActionChip(
                            icon: Icons.restart_alt_rounded,
                            label: l.serverOverrideResetBtn,
                            accentLight: tp.accentLight,
                            onActivate: () async {
                              final hostId = activeEntry.hostId;
                              if (hostId == null) return;
                              await settings.resetServerToGlobal(
                                hostId,
                                serverName: activeEntry.label,
                                launcherPreferences: launcherPrefs,
                                themeProvider: tp,
                              );
                              await _refreshLauncherCustomCheck();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l.serverOverrideResetDone),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(width: 8),
                        _FocusableOverrideSwitch(
                          value: overrideEnabled,
                          accent: tp.accent,
                          accentLight: tp.accentLight,
                          onChanged: (val) async {
                            final hostId = activeEntry.hostId;
                            if (hostId == null) return;
                            await settings.setServerOverrideEnabled(
                              hostId,
                              val,
                              serverName: activeEntry.label,
                              launcherPreferences: launcherPrefs,
                              themeProvider: tp,
                            );
                            await _refreshLauncherCustomCheck();
                          },
                        ),
                      ],
                    ),
                    if (overrideEnabled && diffBadges.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final badge in diffBadges)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopePill extends StatefulWidget {
  final SettingsScopeEntry entry;
  final bool selected;
  final Color accent;
  final Color accentLight;
  final Color surfaceVariant;
  final VoidCallback onSelect;
  final ValueChanged<int> onHorizontalMove;

  const _ScopePill({
    super.key,
    required this.entry,
    required this.selected,
    required this.accent,
    required this.accentLight,
    required this.surfaceVariant,
    required this.onSelect,
    required this.onHorizontalMove,
  });

  @override
  State<_ScopePill> createState() => _ScopePillState();
}

class _ScopePillState extends State<_ScopePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final bgColor = isSelected
        ? widget.accent
        : (_focused
              ? Colors.white.withValues(alpha: 0.12)
              : widget.surfaceVariant);
    final borderColor = _focused
        ? Colors.white
        : (isSelected
              ? widget.accentLight.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08));

    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Scrollable.ensureVisible(context, alignment: 0.5);
            }
          });
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.space) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onHorizontalMove(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          widget.onHorizontalMove(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: borderColor,
              width: _focused ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.entry.isGlobal
                    ? Icons.public_rounded
                    : Icons.computer_rounded,
                size: 14,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                widget.entry.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (!widget.entry.isGlobal && widget.entry.hasOverride) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : widget.accentLight,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusableOverrideSwitch extends StatefulWidget {
  final bool value;
  final Color accent;
  final Color accentLight;
  final ValueChanged<bool> onChanged;

  const _FocusableOverrideSwitch({
    required this.value,
    required this.accent,
    required this.accentLight,
    required this.onChanged,
  });

  @override
  State<_FocusableOverrideSwitch> createState() =>
      _FocusableOverrideSwitchState();
}

class _FocusableOverrideSwitchState extends State<_FocusableOverrideSwitch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.space) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _focused ? widget.accentLight : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: ExcludeFocus(
          child: Switch(
            value: widget.value,
            activeThumbColor: widget.accent,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

class _FocusableActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accentLight;
  final VoidCallback onActivate;

  const _FocusableActionChip({
    required this.icon,
    required this.label,
    required this.accentLight,
    required this.onActivate,
  });

  @override
  State<_FocusableActionChip> createState() => _FocusableActionChipState();
}

class _FocusableActionChipState extends State<_FocusableActionChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.space) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onActivate,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? widget.accentLight : Colors.white12,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: Colors.white70),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

