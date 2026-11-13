import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/http_api/nv_http_client.dart';

enum WatchdogDialogOutcome { closeAndLaunch, launchAnyway, cancel }

class WatchdogDialogDecision {
  final WatchdogDialogOutcome outcome;
  final List<String> selectedIds;

  const WatchdogDialogDecision(this.outcome, [this.selectedIds = const []]);
}

/// Controller-friendly modal displayed when Server Watchdog detects CPU or RAM
/// pressure before launching a game.
Future<WatchdogDialogDecision?> showWatchdogPreLaunchDialog({
  required BuildContext context,
  required WatchdogStatus status,
  required Color surface,
  required Color accent,
}) {
  return showDialog<WatchdogDialogDecision>(
    context: context,
    barrierDismissible: true,
    builder: (_) => WatchdogPreLaunchDialog(
      status: status,
      surface: surface,
      accent: accent,
    ),
  );
}

/// Controller-friendly prompt shown when a paused stream's game was closed
/// locally on the host.
Future<bool> showGameClosedOnHostDialog({
  required BuildContext context,
  required Color surface,
  required Color accent,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return _GamepadDialogShell(
        onBack: () => Navigator.pop(ctx, false),
        child: AlertDialog(
          backgroundColor: surface,
          title: Row(
            children: [
              Icon(Icons.videogame_asset_off_rounded, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.sessionClosedOnHostTitle,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: Text(
            l10n.sessionClosedOnHostBody,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              autofocus: true,
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.startNewSession),
            ),
          ],
        ),
      );
    },
  );
  return result == true;
}

class WatchdogPreLaunchDialog extends StatefulWidget {
  final WatchdogStatus status;
  final Color surface;
  final Color accent;

  const WatchdogPreLaunchDialog({
    super.key,
    required this.status,
    required this.surface,
    required this.accent,
  });

  @override
  State<WatchdogPreLaunchDialog> createState() =>
      _WatchdogPreLaunchDialogState();
}

class _WatchdogPreLaunchDialogState extends State<WatchdogPreLaunchDialog> {
  late final Set<String> _selected = {
    for (final c in widget.status.candidates)
      if (c.recommended) c.id,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final candidates = widget.status.candidates;
    final hasCandidates = candidates.isNotEmpty;
    final availGiB = widget.status.availRamBytes / (1024 * 1024 * 1024);
    final totalGiB = widget.status.totalRamBytes / (1024 * 1024 * 1024);

    return _GamepadDialogShell(
      onBack: () => Navigator.pop(
        context,
        const WatchdogDialogDecision(WatchdogDialogOutcome.cancel),
      ),
      child: AlertDialog(
        backgroundColor: widget.surface,
        title: Row(
          children: [
            Icon(Icons.health_and_safety_rounded, color: widget.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.watchdogPressureTitle,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.watchdogPressureBody,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricBadge(
                    label:
                        'CPU ${widget.status.cpuUsagePercent.toStringAsFixed(0)}% / ${widget.status.maxCpuPercent.toStringAsFixed(0)}%',
                    alert: widget.status.cpuPressure,
                    accent: widget.accent,
                  ),
                  _MetricBadge(
                    label:
                        'RAM ${widget.status.memoryLoadPercent}% (${availGiB.toStringAsFixed(1)}/${totalGiB.toStringAsFixed(1)} GiB)',
                    alert: widget.status.ramPressure,
                    accent: widget.accent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!hasCandidates)
                Text(
                  l10n.watchdogNoClosableApps,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      final checked = _selected.contains(candidate.id);
                      final ramMb = (candidate.ramBytes / (1024 * 1024))
                          .round();
                      return CheckboxListTile(
                        dense: true,
                        activeColor: widget.accent,
                        checkColor: Colors.black,
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(candidate.id);
                            } else {
                              _selected.remove(candidate.id);
                            }
                          });
                        },
                        title: Text(
                          candidate.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '$ramMb MB • ${candidate.cpuPercent.toStringAsFixed(1)}% CPU • ${candidate.category}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const WatchdogDialogDecision(WatchdogDialogOutcome.cancel),
            ),
            child: Text(l10n.cancel),
          ),
          OutlinedButton(
            autofocus: !hasCandidates || _selected.isEmpty,
            onPressed: () => Navigator.pop(
              context,
              const WatchdogDialogDecision(WatchdogDialogOutcome.launchAnyway),
            ),
            child: Text(l10n.watchdogLaunchAnyway),
          ),
          if (hasCandidates)
            FilledButton(
              autofocus: _selected.isNotEmpty,
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      WatchdogDialogDecision(
                        WatchdogDialogOutcome.closeAndLaunch,
                        _selected.toList(growable: false),
                      ),
                    ),
              child: Text(
                '${l10n.watchdogCloseAndLaunch} (${_selected.length})',
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final String label;
  final bool alert;
  final Color accent;

  const _MetricBadge({
    required this.label,
    required this.alert,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = alert
        ? Colors.amberAccent.withValues(alpha: 0.7)
        : accent.withValues(alpha: 0.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: alert ? Colors.amberAccent : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GamepadDialogShell extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;

  const _GamepadDialogShell({required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            onBack();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}

