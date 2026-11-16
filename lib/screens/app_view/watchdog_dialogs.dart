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
/// pressure before launching a game. The primary action is focused on open so
/// a single Ⓐ press resolves it.
Future<WatchdogDialogDecision?> showWatchdogPreLaunchDialog({
  required BuildContext context,
  required WatchdogStatus status,
  required Color surface,
  required Color accent,
  String? hostName,
}) {
  return showGeneralDialog<WatchdogDialogDecision>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => WatchdogPreLaunchDialog(
      status: status,
      surface: surface,
      accent: accent,
      hostName: hostName,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(ctx)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
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

const _tabular = [FontFeature.tabularFigures()];
const _over = Colors.amberAccent;

/// 2px ring on keyboard/gamepad focus; no scale, no glow.
WidgetStateProperty<BorderSide?> _focusRing(Color color) =>
    WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused)
          ? BorderSide(color: color, width: 2)
          : null,
    );

class WatchdogPreLaunchDialog extends StatefulWidget {
  final WatchdogStatus status;
  final Color surface;
  final Color accent;
  final String? hostName;

  const WatchdogPreLaunchDialog({
    super.key,
    required this.status,
    required this.surface,
    required this.accent,
    this.hostName,
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

  void _pop(WatchdogDialogDecision d) => Navigator.pop(context, d);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = widget.status;
    final accent = widget.accent;
    final candidates = s.candidates;
    final hasCandidates = candidates.isNotEmpty;
    final maxRam = candidates.fold<int>(
      1,
      (m, c) => c.ramBytes > m ? c.ramBytes : m,
    );

    final ramWorst = s.ramPressure;
    final load = l10n.watchdogLoadTitle
        .replaceAll('{metric}', ramWorst ? 'RAM' : 'CPU')
        .replaceAll(
          '{pct}',
          (ramWorst ? s.memoryLoadPercent : s.cpuUsagePercent)
              .toStringAsFixed(0),
        );
    final host = widget.hostName;
    final title = host == null || host.isEmpty ? load : '$host · $load';

    void launchAnyway() =>
        _pop(const WatchdogDialogDecision(WatchdogDialogOutcome.launchAnyway));
    final primaryStyle = FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor:
          ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : Colors.black,
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(side: _focusRing(Colors.white));
    final secondaryStyle = TextButton.styleFrom(
      foregroundColor: Colors.white70,
    ).copyWith(side: _focusRing(accent));

    return _GamepadDialogShell(
      onBack: () =>
          _pop(const WatchdogDialogDecision(WatchdogDialogOutcome.cancel)),
      child: Dialog(
        backgroundColor: widget.surface,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(height: 16),
                _LoadBar(
                  label: 'CPU',
                  percent: s.cpuUsagePercent,
                  limit: s.maxCpuPercent,
                  over: s.cpuPressure,
                  accent: accent,
                ),
                const SizedBox(height: 10),
                _LoadBar(
                  label: 'RAM',
                  percent: s.memoryLoadPercent.toDouble(),
                  limit: s.maxMemoryLoadPercent,
                  over: s.ramPressure,
                  accent: accent,
                ),
                const SizedBox(height: 20),
                if (hasCandidates)
                  FilledButton(
                    autofocus: _selected.isNotEmpty,
                    style: primaryStyle,
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _pop(
                            WatchdogDialogDecision(
                              WatchdogDialogOutcome.closeAndLaunch,
                              _selected.toList(growable: false),
                            ),
                          ),
                    child: Text(
                      l10n.watchdogCloseAndLaunch.replaceAll(
                        '{n}',
                        '${_selected.length}',
                      ),
                    ),
                  )
                else
                  FilledButton(
                    autofocus: true,
                    style: primaryStyle,
                    onPressed: launchAnyway,
                    child: Text(l10n.watchdogLaunchAnyway),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasCandidates)
                      TextButton(
                        autofocus: _selected.isEmpty,
                        style: secondaryStyle,
                        onPressed: launchAnyway,
                        child: Text(l10n.watchdogLaunchAnyway),
                      ),
                    TextButton(
                      style: secondaryStyle,
                      onPressed: () => _pop(
                        const WatchdogDialogDecision(
                          WatchdogDialogOutcome.cancel,
                        ),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                if (!hasCandidates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.watchdogNoClosableApps,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final c = candidates[index];
                        return _CandidateRow(
                          candidate: c,
                          share: c.ramBytes / maxRam,
                          checked: _selected.contains(c.id),
                          accent: accent,
                          onToggle: () => setState(() {
                            if (!_selected.remove(c.id)) _selected.add(c.id);
                          }),
                        );
                      },
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

/// Load bar with a hairline tick at the configured limit; fills once on open.
class _LoadBar extends StatelessWidget {
  final String label;
  final double percent;
  final double limit;
  final bool over;
  final Color accent;

  const _LoadBar({
    required this.label,
    required this.percent,
    required this.limit,
    required this.over,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final fill = over ? _over : accent;
    final value = (percent / 100).clamp(0.0, 1.0);
    final tick = (limit / 100).clamp(0.0, 1.0);
    final instant = MediaQuery.disableAnimationsOf(context);
    final text =
        '${percent.toStringAsFixed(0)}% / ${limit.toStringAsFixed(0)}%';
    return Semantics(
      label: label,
      value: text,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 14,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: instant ? value : 0, end: value),
                      duration: instant
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      builder: (_, v, _) => Container(
                        width: box.maxWidth * v,
                        height: 6,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Positioned(
                      left: box.maxWidth * tick - 1,
                      child: Container(
                        width: 2,
                        height: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: over ? _over : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatefulWidget {
  final WatchdogCandidate candidate;
  final double share;
  final bool checked;
  final Color accent;
  final VoidCallback onToggle;

  const _CandidateRow({
    required this.candidate,
    required this.share,
    required this.checked,
    required this.accent,
    required this.onToggle,
  });

  @override
  State<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends State<_CandidateRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final ramMb = c.ramBytes / (1024 * 1024);
    final ram = ramMb >= 1024
        ? '${(ramMb / 1024).toStringAsFixed(1)} GB'
        : '${ramMb.round()} MB';
    return Semantics(
      checked: widget.checked,
      child: InkWell(
        onTap: widget.onToggle,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(8),
        focusColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? widget.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: widget.checked ? widget.accent : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.checked ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FractionallySizedBox(
                      widthFactor: widget.share.clamp(0.02, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$ram · ${c.cpuPercent.toStringAsFixed(0)}% CPU',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
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
