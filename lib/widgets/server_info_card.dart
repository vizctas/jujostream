import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/computer_details.dart';
import '../../providers/theme_provider.dart';

class ServerInfoCard extends StatelessWidget {
  final ComputerDetails computer;

  const ServerInfoCard({super.key, required this.computer});

  static void show(BuildContext context, ComputerDetails computer) {
    showDialog<void>(
      context: context,
      builder: (_) => ServerInfoCard(computer: computer),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
      backgroundColor: context.read<ThemeProvider>().surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.computer_outlined,
                      color: Colors.white70, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        computer.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _stateLabel(),
                        style: TextStyle(
                          color: _stateColor(),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),

            _row(Icons.lan_outlined, 'Dirección local', _activeAddr()),
            if (computer.remoteAddress.isNotEmpty)
              _row(Icons.cloud_outlined, 'Dirección remota',
                  computer.remoteAddress),
            _row(Icons.info_outline, 'Versión Sunshine', _sunshineVersion()),
            _row(Icons.videocam_outlined, 'Codecs soportados', _codecsLabel()),
            _row(
              Icons.vpn_key_outlined,
              'Estado de emparejamiento',
              computer.isPaired ? 'Emparejado ✓' : 'No emparejado',
            ),
            if (computer.runningGameId > 0)
              _row(Icons.play_circle_outline, 'Juego activo',
                  'App ID: ${computer.runningGameId}'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _activeAddr() {
    final addr = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;
    final port = computer.httpsPort > 0 ? computer.httpsPort : 47984;
    return '$addr:$port';
  }

  String _sunshineVersion() {
    if (computer.serverVersion.isEmpty) return 'Desconocida';

    final parts = computer.serverVersion.split('.');
    if (parts.length >= 3) {
      final major = parts[0];
      final minor = parts[1];
      final patch = parts[2];
      return 'Sunshine $major.$minor.$patch';
    }
    return computer.serverVersion;
  }

  String _codecsLabel() {
    final mask = computer.serverCodecModeSupport;
    final codecs = <String>[];
    if (mask & 0x0001 != 0 || mask & 0x000F != 0) codecs.add('H.264');
    if (mask & 0x0100 != 0 || mask & 0x0F00 != 0) codecs.add('H.265');
    if (mask & 0x1000 != 0 || mask & 0xF000 != 0) codecs.add('AV1');
    return codecs.isEmpty ? 'H.264' : codecs.join(', ');
  }

  String _stateLabel() {
    switch (computer.state) {
      case ComputerState.online:
        return 'En línea';
      case ComputerState.offline:
        return 'Desconectado';
      default:
        return 'Estado desconocido';
    }
  }

  Color _stateColor() {
    switch (computer.state) {
      case ComputerState.online:
        return Colors.greenAccent;
      case ComputerState.offline:
        return Colors.redAccent;
      default:
        return Colors.white38;
    }
  }
}
