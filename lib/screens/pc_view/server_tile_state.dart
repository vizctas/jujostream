import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../ui/computer_connection_status.dart';

/// Everything a server tile needs to render its state, derived once.
///
/// The grid card, the focus-mode card and the focus-mode circle each derived
/// this independently — three copies of the same six lines, which is how the
/// three layouts ended up disagreeing about type sizes and colours for the
/// same states.
@immutable
class ServerTileState {
  const ServerTileState({
    required this.isOnline,
    required this.isPaired,
    required this.isCloud,
    required this.statusColor,
    required this.statusText,
    required this.actionText,
    required this.address,
    required this.connectionStatus,
    required this.semanticLabel,
  });

  factory ServerTileState.of(
    BuildContext context,
    ComputerDetails computer, {
    required bool cloudSignedIn,
    Color offlineColor = Colors.white24,
  }) {
    final l = AppLocalizations.of(context);
    final isSpanish = l.locale.languageCode == 'es';
    final isOnline = computer.isReachable;
    final isPaired = computer.isPaired;

    final statusText = isOnline
        ? (isPaired ? l.connected : l.notPaired)
        : l.disconnected;
    final address = isOnline
        ? (computer.activeAddress.isNotEmpty
              ? computer.activeAddress
              : computer.localAddress)
        : '';
    final connectionStatus = computerConnectionStatusLabel(
      computerConnectionStatus(computer, cloudSignedIn: cloudSignedIn),
      isSpanish: isSpanish,
    );

    return ServerTileState(
      isOnline: isOnline,
      isPaired: isPaired,
      isCloud: computer.isCloud,
      statusColor: isOnline
          ? (isPaired ? Colors.greenAccent : Colors.orangeAccent)
          : offlineColor,
      statusText: statusText,
      actionText: isOnline ? (isPaired ? l.enter : l.pairAction) : '',
      address: address,
      connectionStatus: connectionStatus,
      semanticLabel: [
        computer.name,
        statusText,
        if (isPaired) connectionStatus,
        if (address.isNotEmpty) address,
        if (computer.isCloud) isSpanish ? 'servidor en la nube' : 'cloud server',
      ].join(', '),
    );
  }

  final bool isOnline;
  final bool isPaired;
  final bool isCloud;

  /// Green when reachable and paired, amber when reachable but unpaired.
  final Color statusColor;
  final String statusText;

  /// What activating the tile does — empty when the server is unreachable.
  final String actionText;
  final String address;
  final String connectionStatus;

  /// One sentence for a screen reader, identical across all three layouts.
  final String semanticLabel;
}
