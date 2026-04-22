import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/computer_details.dart';
import '../providers/computer_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/server_info_card.dart';
import '../screens/pc_view/vibeapollo_screen.dart';

/// Shared server-options dialog used from both pc_view_screen and
/// focus_mode_screen. Accepts callbacks so each screen can manage its own
/// background-image state without coupling to a specific screen class.
class ComputerOptionsDialog {
  const ComputerOptionsDialog._();

  static void show({
    required BuildContext context,
    required ComputerDetails computer,
    required Map<String, String> bgPaths,
    required Future<void> Function(ComputerDetails) onPickBackground,
    required Future<void> Function(ComputerDetails) onRemoveBackground,
  }) {
    final l = AppLocalizations.of(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final sc = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final fc = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(sc),
          child: FadeTransition(opacity: fc, child: child),
        );
      },
      pageBuilder: (ctx, _, _) {
        final tp = context.read<ThemeProvider>();
        final provider = context.read<ComputerProvider>();
        final size = MediaQuery.sizeOf(ctx);
        final dialogWidth = size.width > 900
            ? 490.0
            : size.width > 600
            ? 500.0
            : size.width - 24;
        final dialogMaxHeight =
            ((size.height - 40) * 0.88).clamp(300.0, size.height - 20).toDouble();
        final dialogMinHeight =
            (dialogMaxHeight * 0.54).clamp(280.0, dialogMaxHeight).toDouble();
        final hasBg = bgPaths.containsKey(computer.uuid);

        return Focus(
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final k = event.logicalKey;
            if (k == LogicalKeyboardKey.gameButtonB ||
                k == LogicalKeyboardKey.escape ||
                k == LogicalKeyboardKey.goBack) {
              Navigator.pop(ctx);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SafeArea(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: dialogWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                  constraints: BoxConstraints(
                    minHeight: dialogMinHeight,
                    maxHeight: dialogMaxHeight,
                  ),
                  decoration: BoxDecoration(
                    color: tp.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        primary: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _tile(
                              icon: Icons.refresh,
                              iconColor: Colors.white70,
                              title: l.refresh,
                              autofocus: true,
                              onTap: () {
                                Navigator.pop(ctx);
                                provider.pollComputer(computer);
                              },
                            ),
                            _tile(
                              icon: provider.primaryServerUuid == computer.uuid
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              iconColor: provider.primaryServerUuid == computer.uuid
                                  ? Colors.amber
                                  : Colors.white70,
                              title: provider.primaryServerUuid == computer.uuid
                                  ? (l.locale.languageCode == 'es'
                                        ? 'Quitar servidor principal'
                                        : 'Remove Primary')
                                  : (l.locale.languageCode == 'es'
                                        ? 'Servidor principal'
                                        : 'Set as Primary'),
                              subtitle: provider.primaryServerUuid == computer.uuid
                                  ? (l.locale.languageCode == 'es'
                                        ? 'Este servidor se conecta automáticamente al iniciar'
                                        : 'This server auto-connects on launch')
                                  : (l.locale.languageCode == 'es'
                                        ? 'Conectar automáticamente al iniciar la app'
                                        : 'Auto-connect when the app starts'),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (provider.primaryServerUuid == computer.uuid) {
                                  provider.clearPrimaryServer();
                                } else {
                                  provider.setPrimaryServer(computer.uuid);
                                }
                              },
                            ),
                            _tile(
                              icon: Icons.photo_library_outlined,
                              iconColor: Colors.indigoAccent,
                              title: 'Background Image',
                              subtitle: hasBg
                                  ? 'Tap to change · Long press to remove'
                                  : 'Use a custom image as card backdrop',
                              onTap: () async {
                                Navigator.pop(ctx);
                                await onPickBackground(computer);
                              },
                            ),
                            if (hasBg)
                              _tile(
                                icon: Icons.image_not_supported_outlined,
                                iconColor: Colors.white38,
                                title: 'Remove Background',
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onRemoveBackground(computer);
                                },
                              ),
                            _tile(
                              icon: Icons.monitor_heart_outlined,
                              iconColor: Colors.cyanAccent,
                              title: l.locale.languageCode == 'es'
                                  ? 'Información del servidor'
                                  : 'Server details',
                              subtitle: computer.serverVersion.isNotEmpty
                                  ? _parseSunshineVersion(computer.serverVersion)
                                  : null,
                              onTap: () {
                                Navigator.pop(ctx);
                                ServerInfoCard.show(context, computer);
                              },
                            ),
                            if (computer.isReachable && computer.isPaired)
                              _tile(
                                icon: Icons.dashboard_customize_outlined,
                                iconColor: const Color(0xFFA78BFA),
                                title: 'VibeApollo API',
                                subtitle: 'Command center',
                                onTap: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          VibeApolloScreen(computer: computer),
                                    ),
                                  );
                                },
                              ),
                            if (computer.isReachable && computer.isPaired)
                              _tile(
                                icon: Icons.settings_ethernet_rounded,
                                iconColor: const Color(0xFF4FC3F7),
                                title: 'Server Configuration',
                                subtitle: 'Open web admin panel in browser',
                                onTap: () {
                                  Navigator.pop(ctx);
                                  final addr = computer.activeAddress.isNotEmpty
                                      ? computer.activeAddress
                                      : computer.localAddress;
                                  final cfgPort = computer.externalPort > 0
                                      ? computer.externalPort + 1
                                      : 47990;
                                  launchUrl(
                                    Uri.parse('https://$addr:$cfgPort'),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                              ),
                            _tile(
                              icon: Icons.info_outline,
                              iconColor: Colors.white70,
                              title: l.details,
                              subtitle:
                                  '${computer.localAddress}\nUUID: ${computer.uuid}',
                              onTap: () => Navigator.pop(ctx),
                            ),
                            _tile(
                              icon: Icons.power_settings_new,
                              iconColor: Colors.cyanAccent,
                              title: l.wakeOnLan,
                              subtitle: computer.macAddress.isEmpty
                                  ? l.macNotAvailable
                                  : computer.macAddress,
                              onTap: computer.macAddress.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      _showWolFeedback(
                                          context, provider, computer);
                                    },
                            ),
                            if (computer.isPaired)
                              _tile(
                                icon: Icons.link_off,
                                iconColor: Colors.orangeAccent,
                                title: 'Unpair',
                                titleColor: Colors.orangeAccent,
                                subtitle:
                                    'Remove pairing but keep server visible',
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  final success =
                                      await provider.unpairComputer(computer);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Unpaired from ${computer.name}'
                                              : 'Failed to unpair',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            _tile(
                              icon: Icons.delete,
                              iconColor: Colors.redAccent,
                              title: l.remove,
                              titleColor: Colors.redAccent,
                              onTap: () {
                                Navigator.pop(ctx);
                                provider.removeComputer(computer);
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _parseSunshineVersion(String v) {
    final p = v.split('.');
    return p.length >= 3 ? 'Sunshine ${p[0]}.${p[1]}.${p[2]}' : 'Sunshine $v';
  }

  static void _showWolFeedback(
    BuildContext context,
    ComputerProvider provider,
    ComputerDetails computer,
  ) {
    final statusNotifier = ValueNotifier<String>('Sending magic packet…');
    final messenger = ScaffoldMessenger.of(context);

    void updateStatus(String status) {
      statusNotifier.value = status;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<String>(
            valueListenable: statusNotifier,
            builder: (_, s, _) => Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.cyanAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(s, style: const TextStyle(color: Colors.white))),
              ],
            ),
          ),
          duration: const Duration(seconds: 60),
          backgroundColor: const Color(0xFF1E1E2E),
        ),
      );
    }

    updateStatus('Sending magic packet…');

    provider
        .sendWakeOnLanWithFeedback(
          computer,
          onStatus: (status) {
            if (context.mounted) updateStatus(status);
          },
        )
        .then((online) {
          if (!context.mounted) return;
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    online
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color:
                        online ? Colors.greenAccent : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    online
                        ? '${computer.name} is online!'
                        : 'WoL timed out — PC did not respond.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
              backgroundColor: online
                  ? const Color(0xFF1A3D2F)
                  : const Color(0xFF3D1A1A),
            ),
          );
          if (online) provider.pollComputer(computer);
        });
  }

  static Widget _tile({
    required IconData icon,
    Color iconColor = Colors.white70,
    required String title,
    Color titleColor = Colors.white,
    String? subtitle,
    VoidCallback? onTap,
    bool autofocus = false,
  }) {
    return Builder(
      builder: (context) {
        return Focus(
          autofocus: autofocus,
          onFocusChange: (focused) {
            (context as Element).markNeedsBuild();
            if (focused) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            }
          },
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final k = event.logicalKey;
            if ((k == LogicalKeyboardKey.enter ||
                    k == LogicalKeyboardKey.select ||
                    k == LogicalKeyboardKey.gameButtonA) &&
                onTap != null) {
              onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (ctx) {
              final focused = Focus.of(ctx).hasFocus;
              return GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  color: focused
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Icon(icon,
                          color: focused ? Colors.white : iconColor,
                          size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: focused ? Colors.white : titleColor,
                                fontWeight: focused
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: focused
                                      ? Colors.white54
                                      : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
