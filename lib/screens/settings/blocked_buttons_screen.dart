import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../platform_channels/gamepad_channel.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';

/// Lets the user disable individual physical gamepad buttons — the extra rear
/// macro buttons on pads like ONIKUMA, which otherwise fire whatever their
/// firmware preset says.
///
/// A button is identified by capturing it rather than by picking from a list:
/// those rear buttons are usually preset to mirror a face button, so only the
/// scanCode separates them from the real one, and nothing in the app can know
/// that value up front.
class BlockedButtonsScreen extends StatefulWidget {
  const BlockedButtonsScreen({super.key});

  @override
  State<BlockedButtonsScreen> createState() => _BlockedButtonsScreenState();
}

class _BlockedButtonsScreenState extends State<BlockedButtonsScreen> {
  /// Capture swallows every gamepad button, so on a TV the gamepad cannot
  /// dismiss the dialog. It always releases itself after this long.
  static const _captureTimeout = Duration(seconds: 8);

  Timer? _captureTimer;
  int _secondsLeft = 0;
  bool _capturing = false;

  @override
  void dispose() {
    _stopCapture();
    super.dispose();
  }

  String _tr(String en, String es) =>
      Localizations.localeOf(context).languageCode == 'es' ? es : en;

  void _stopCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _capturing = false;
    GamepadChannel.onButtonCaptured = null;
    GamepadChannel.setButtonCapture(false);
  }

  Future<void> _startCapture() async {
    final settings = context.read<SettingsProvider>();
    _capturing = true;
    _secondsLeft = _captureTimeout.inSeconds;

    GamepadChannel.onButtonCaptured = (button) {
      final id = (button['key'] as num?)?.toInt();
      if (id == null) return;
      final label = _describe(button);
      final next = Map<int, String>.from(settings.config.blockedGamepadButtons)
        ..[id] = label;
      settings.updateConfig(
        settings.config.copyWith(blockedGamepadButtons: next),
      );
      if (mounted) Navigator.of(context).maybePop();
    };
    await GamepadChannel.setButtonCapture(true);

    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) Navigator.of(context).maybePop();
    });

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, _) => AlertDialog(
          title: Text(_tr('Press the button', 'Presiona el botón')),
          content: Text(
            _tr(
              'Press the gamepad button you want to disable. '
              'Releases on its own in $_secondsLeft s.',
              'Presiona el botón del mando que quieres desactivar. '
              'Se libera solo en $_secondsLeft s.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_tr('Cancel', 'Cancelar')),
            ),
          ],
        ),
      ),
    );
    _stopCapture();
    if (mounted) setState(() {});
  }

  static String _describe(Map<String, dynamic> button) {
    final label = (button['label'] as String? ?? '')
        .replaceFirst('KEYCODE_', '')
        .replaceAll('_', ' ');
    final scan = button['scanCode'];
    final name = label.isEmpty || label == 'UNKNOWN'
        ? 'keyCode ${button['keyCode']}'
        : label;
    return scan == null ? name : '$name · scan $scan';
  }

  void _unblock(SettingsProvider settings, int id) {
    final next = Map<int, String>.from(settings.config.blockedGamepadButtons)
      ..remove(id);
    settings.updateConfig(
      settings.config.copyWith(blockedGamepadButtons: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final blocked = settings.config.blockedGamepadButtons;

    return Scaffold(
      backgroundColor: tp.background,
      appBar: AppBar(
        title: Text(
          _tr('Blocked Buttons', 'Botones bloqueados'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tp.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _tr(
              'Blocked buttons do nothing, in the launcher and in game. Use it '
              'for the extra rear macro buttons on pads that fire a preset you '
              'did not ask for.',
              'Los botones bloqueados no hacen nada, ni en el launcher ni en '
              'el juego. Sirve para los botones traseros de macro que disparan '
              'una función predefinida que no pediste.',
            ),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          if (blocked.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _tr('No blocked buttons.', 'Ningún botón bloqueado.'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            )
          else
            for (final entry in blocked.entries)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: Text(
                  entry.value,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  tooltip: _tr('Unblock', 'Desbloquear'),
                  onPressed: () => _unblock(settings, entry.key),
                ),
              ),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            onPressed: _capturing ? null : _startCapture,
            icon: const Icon(Icons.add),
            label: Text(_tr('Block a button', 'Bloquear un botón')),
          ),
        ],
      ),
    );
  }
}
