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

/// Minimalist, discrete, gamepad-focusable scope selector and per-server
/// override toggle. Placed inside each Settings tab's scrollable list so it
/// participates in the tab's [OrderedTraversalPolicy] focus index and never
/// consumes permanent vertical screen space.
class SettingsScopeBar extends StatefulWidget {
  final String? fallbackServerId;
  final String? fallbackServerName;
  final EdgeInsetsGeometry padding;

  const SettingsScopeBar({
    super.key,
    this.fallbackServerId,
    this.fallbackServerName,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<SettingsScopeBar> createState() => _SettingsScopeBarState();
}

class _SettingsScopeBarState extends State<SettingsScopeBar> {
  final FocusNode _scopeRowFocusNode = FocusNode(
    debugLabel: 'settings-scope-row',
  );
  bool _scopeFocused = false;
  bool _switchFocused = false;
  bool _openingPicker = false;

  @override
  void dispose() {
    _scopeRowFocusNode.dispose();
    super.dispose();
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

  Future<void> _openScopePicker(
    BuildContext context,
    List<SettingsScopeEntry> entries,
    SettingsScopeEntry activeEntry,
    SettingsProvider settings,
    LauncherPreferences launcherPrefs,
    ThemeProvider tp,
    AppLocalizations l,
  ) async {
    if (_openingPicker) return;
    _openingPicker = true;

    final isServerSelected = !activeEntry.isGlobal;
    final overrideEnabled =
        isServerSelected && settings.hasServerOverride(activeEntry.hostId);

    final action = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.gameButtonB): () =>
              Navigator.pop(dialogCtx),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(dialogCtx),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              Navigator.pop(dialogCtx),
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          },
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SimpleDialog(
              backgroundColor: tp.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                l.serverConfigScopeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final entry in entries)
                  Builder(
                    builder: (itemCtx) {
                      final selected = entry.hostId == activeEntry.hostId;
                      final valueToken = entry.isGlobal
                          ? '__global__'
                          : 'srv:${entry.hostId}';
                      return ListTile(
                        key: ValueKey(
                          'scope-picker-${entry.hostId ?? "global"}',
                        ),
                        dense: true,
                        autofocus: selected,
                        selected: selected,
                        focusColor: tp.accent.withValues(alpha: 0.22),
                        leading: Icon(
                          entry.isGlobal
                              ? Icons.public_rounded
                              : Icons.dns_rounded,
                          size: 18,
                          color: selected
                              ? tp.accentLight
                              : (entry.hasOverride
                                    ? tp.accentLight.withValues(alpha: 0.8)
                                    : Colors.white54),
                        ),
                        title: Text(
                          entry.label,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: !entry.isGlobal && entry.hasOverride
                            ? Text(
                                l.serverOverrideBadgeCustom,
                                style: TextStyle(
                                  color: tp.accentLight.withValues(alpha: 0.85),
                                  fontSize: 11,
                                ),
                              )
                            : null,
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                color: tp.accentLight,
                                size: 18,
                              )
                            : null,
                        onFocusChange: (focused) {
                          if (!focused) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (itemCtx.mounted) {
                              Scrollable.ensureVisible(
                                itemCtx,
                                alignment: 0.5,
                              );
                            }
                          });
                        },
                        onTap: () => Navigator.pop(dialogCtx, valueToken),
                      );
                    },
                  ),
                if (isServerSelected && overrideEnabled) ...[
                  const Divider(color: Colors.white12, height: 12),
                  ListTile(
                    key: const ValueKey('scope-picker-reset'),
                    dense: true,
                    focusColor: Colors.redAccent.withValues(alpha: 0.18),
                    leading: const Icon(
                      Icons.restart_alt_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                    title: Text(
                      l.serverOverrideResetBtn,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => Navigator.pop(dialogCtx, '__reset__'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    _openingPicker = false;
    if (!mounted) return;
    _scopeRowFocusNode.requestFocus();

    if (action == null) return;
    if (action == '__reset__' && activeEntry.hostId != null) {
      await settings.resetServerToGlobal(
        activeEntry.hostId!,
        serverName: activeEntry.label,
        launcherPreferences: launcherPrefs,
        themeProvider: tp,
      );
      return;
    }

    if (action == '__global__') {
      await settings.setScope(
        null,
        launcherPreferences: launcherPrefs,
        themeProvider: tp,
      );
    } else if (action.startsWith('srv:')) {
      final targetId = action.substring(4);
      final picked = entries.firstWhere(
        (e) => e.hostId == targetId,
        orElse: () => entries.first,
      );
      await settings.setScope(
        picked.hostId,
        serverName: picked.isGlobal ? null : picked.label,
        launcherPreferences: launcherPrefs,
        themeProvider: tp,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final launcherPrefs = context.watch<LauncherPreferences>();
    final computers = context.watch<ComputerProvider>().computers;

    final entries = _buildEntries(l, settings, computers);
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

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Discrete single-line scope selector tile
          Focus(
            focusNode: _scopeRowFocusNode,
            onFocusChange: (f) => setState(() => _scopeFocused = f),
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.gameButtonA) {
                _openScopePicker(
                  context,
                  entries,
                  activeEntry,
                  settings,
                  launcherPrefs,
                  tp,
                  l,
                );
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _scopeFocused
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent,
                border: Border.all(
                  color: _scopeFocused
                      ? tp.accentLight.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  isServerSelected
                      ? Icons.dns_rounded
                      : Icons.public_rounded,
                  size: 18,
                  color: overrideEnabled ? tp.accentLight : Colors.white54,
                ),
                title: Text(
                  l.serverConfigScopeLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overrideEnabled) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tp.accentLight,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        activeEntry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isServerSelected
                              ? (overrideEnabled
                                    ? tp.accentLight
                                    : Colors.white70)
                              : Colors.white54,
                          fontSize: 13,
                          fontWeight: isServerSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: _scopeFocused ? Colors.white : Colors.white38,
                    ),
                  ],
                ),
                onTap: () => _openScopePicker(
                  context,
                  entries,
                  activeEntry,
                  settings,
                  launcherPrefs,
                  tp,
                  l,
                ),
              ),
            ),
          ),

          // Row 2: Shown ONLY when a server is selected — discrete override switch
          if (isServerSelected)
            Focus(
              onFocusChange: (f) => setState(() => _switchFocused = f),
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.gameButtonA) {
                  settings.setServerOverrideEnabled(
                    activeEntry.hostId!,
                    !overrideEnabled,
                    serverName: activeEntry.label,
                    launcherPreferences: launcherPrefs,
                    themeProvider: tp,
                  );
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: _switchFocused
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
                  border: Border.all(
                    color: _switchFocused
                        ? tp.accentLight.withValues(alpha: 0.3)
                        : Colors.transparent,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    '${l.serverOverrideToggleTitle} (${activeEntry.label})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    overrideEnabled
                        ? l.serverOverrideToggleSubOn
                        : l.serverOverrideToggleSubOff,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: overrideEnabled
                          ? tp.accentLight.withValues(alpha: 0.85)
                          : Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                  value: overrideEnabled,
                  activeThumbColor: tp.accent,
                  onChanged: (val) => settings.setServerOverrideEnabled(
                    activeEntry.hostId!,
                    val,
                    serverName: activeEntry.label,
                    launcherPreferences: launcherPrefs,
                    themeProvider: tp,
                  ),
                ),
              ),
            ),

          const Divider(color: Colors.white10, height: 8),
        ],
      ),
    );
  }
}
