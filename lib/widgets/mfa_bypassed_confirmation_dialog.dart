import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';

enum MfaBypassedAction {
  enterMfa,
  usePin,
  cancel,
}

class MfaBypassedConfirmationDialog extends StatefulWidget {
  const MfaBypassedConfirmationDialog({super.key});

  static Future<MfaBypassedAction?> show(BuildContext context) {
    return showDialog<MfaBypassedAction>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MfaBypassedConfirmationDialog(),
    );
  }

  @override
  State<MfaBypassedConfirmationDialog> createState() =>
      _MfaBypassedConfirmationDialogState();
}

class _MfaBypassedConfirmationDialogState
    extends State<MfaBypassedConfirmationDialog> {
  final FocusNode _mfaBtnFocus = FocusNode(debugLabel: 'dialog-mfa-btn');
  final FocusNode _pinBtnFocus = FocusNode(debugLabel: 'dialog-pin-btn');
  final FocusNode _cancelBtnFocus = FocusNode(debugLabel: 'dialog-cancel-btn');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mfaBtnFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _mfaBtnFocus.dispose();
    _pinBtnFocus.dispose();
    _cancelBtnFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final l = AppLocalizations.of(context);
    final isEs = l.locale.languageCode == 'es';

    final title = isEs ? 'Verificación 2FA Requerida' : '2FA Verification Required';
    final body = isEs
        ? 'No has completado la verificación 2FA. Sin esto, la conexión automática segura no está disponible.\n\n¿Quieres verificar el 2FA ahora o usar emparejamiento manual por PIN?'
        : 'You have not completed 2FA verification. Without this, secure automatic connection via Jujo Cloud is unavailable.\n\nWould you like to complete 2FA now, or switch to manual PIN pairing?';

    return Focus(
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.of(context).pop(MfaBypassedAction.cancel);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: tp.colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tp.colors.accent.withValues(alpha: 0.30),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.security_update_warning_rounded,
                  size: 44,
                  color: tp.colors.accentLight,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _buildButton(
                  focusNode: _mfaBtnFocus,
                  label: isEs ? 'Ingresar 2FA' : 'Enter 2FA',
                  isPrimary: true,
                  onPressed: () => Navigator.of(context).pop(MfaBypassedAction.enterMfa),
                  tp: tp,
                ),
                const SizedBox(height: 10),
                _buildButton(
                  focusNode: _pinBtnFocus,
                  label: isEs ? 'Usar código PIN' : 'Use PIN Pairing',
                  isPrimary: false,
                  onPressed: () => Navigator.of(context).pop(MfaBypassedAction.usePin),
                  tp: tp,
                ),
                const SizedBox(height: 10),
                _buildButton(
                  focusNode: _cancelBtnFocus,
                  label: l.cancel,
                  isPrimary: false,
                  isCancel: true,
                  onPressed: () => Navigator.of(context).pop(MfaBypassedAction.cancel),
                  tp: tp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required FocusNode focusNode,
    required String label,
    required bool isPrimary,
    bool isCancel = false,
    required VoidCallback onPressed,
    required ThemeProvider tp,
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        final bgColor = isPrimary
            ? (hasFocus ? tp.colors.accent : tp.colors.accentLight)
            : (hasFocus ? Colors.white.withValues(alpha: 0.1) : Colors.transparent);
        final fgColor = isPrimary
            ? Colors.white
            : (isCancel
                ? (hasFocus ? Colors.redAccent : Colors.white54)
                : (hasFocus ? tp.colors.accentLight : Colors.white70));
        final border = isPrimary
            ? (hasFocus ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none)
            : BorderSide(
                color: hasFocus
                    ? (isCancel ? Colors.redAccent : tp.colors.accentLight)
                    : Colors.white.withValues(alpha: 0.2),
                width: hasFocus ? 2 : 1,
              );

        return Focus(
          focusNode: focusNode,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.gameButtonA ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select) {
              onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 145),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.fromBorderSide(border),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 14,
                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
