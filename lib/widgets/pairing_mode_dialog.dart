import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/tv/tv_focus_helpers.dart';
import '../ui/motion_policy.dart';

/// How the user wants to pair this device.
enum PairingMode { watchword, pin }

/// Lets the user pick the pairing method instead of guessing for them.
///
/// This screen exists because auto-detection was wrong: a watchword challenge
/// only exists after someone presses the button in StreamAdmin, so probing for
/// one first meant the option was invisible in the normal case and the user
/// always landed on PIN without knowing there was an alternative.
///
/// [watchwordWaiting] is a live hint, not a gate. Both modes stay selectable.
Future<PairingMode?> showPairingModeDialog(
  BuildContext context, {
  required bool watchwordWaiting,
}) {
  return showDialog<PairingMode>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PairingModeDialog(watchwordWaiting: watchwordWaiting),
  );
}

class _PairingModeDialog extends StatelessWidget {
  const _PairingModeDialog({required this.watchwordWaiting});

  final bool watchwordWaiting;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>().colors;
    final motion = MotionPolicy.fromContext(
      context,
      context.read<ThemeProvider>(),
    );
    final isEs = Localizations.localeOf(context).languageCode == 'es';

    return Dialog(
      backgroundColor: tp.surface,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(accent: tp.accent, isEs: isEs),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ModeOption(
                    icon: Icons.vpn_key_rounded,
                    title: isEs ? 'Consigna' : 'Watchword',
                    subtitle: isEs
                        ? 'Selecciona palabras con el control. Sin teclado.'
                        : 'Pick words with the remote. No keyboard.',
                    badge: watchwordWaiting
                        ? (isEs ? 'Listo' : 'Ready')
                        : null,
                    accent: tp.accent,
                    motion: motion,
                    autofocus: true,
                    onSelect: () =>
                        Navigator.of(context).pop(PairingMode.watchword),
                  ),
                  const SizedBox(height: 12),
                  _ModeOption(
                    icon: Icons.dialpad_rounded,
                    title: isEs ? 'PIN' : 'PIN',
                    subtitle: isEs
                        ? 'Escribe un código de 4 dígitos en el servidor.'
                        : 'Type a 4-digit code on the server.',
                    badge: null,
                    accent: tp.accent,
                    motion: motion,
                    autofocus: false,
                    onSelect: () => Navigator.of(context).pop(PairingMode.pin),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TvFocusable(
                      onSelect: () => Navigator.of(context).pop(),
                      borderRadius: 10,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          isEs ? 'Cancelar' : 'Cancel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
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

class _Header extends StatelessWidget {
  const _Header({required this.accent, required this.isEs});

  final Color accent;
  final bool isEs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.20),
            accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEs ? 'Emparejar dispositivo' : 'Pair device',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isEs ? 'Elige cómo quieres emparejar' : 'Choose how to pair',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable method. Full-width rows rather than side-by-side cards so
/// D-pad up/down moves between them predictably.
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.accent,
    required this.motion,
    required this.autofocus,
    required this.onSelect,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Color accent;
  final MotionPolicy motion;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: 14,
      semanticLabel: title,
      child: AnimatedContainer(
        duration: motion.focusDuration,
        curve: motion.standardCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
