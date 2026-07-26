import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

OverlayEntry showComputerEntryOverlay(
  BuildContext context, {
  required String computerName,
}) {
  final entry = OverlayEntry(
    builder: (_) => _ComputerEntryOverlay(computerName: computerName),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

class _ComputerEntryOverlay extends StatelessWidget {
  const _ComputerEntryOverlay({required this.computerName});

  final String computerName;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: l.connectingToComputer(computerName),
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0xA6000000)),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: const Color(0xFF121722),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 20),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.connectingToComputer(computerName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l.secureConnectionInProgress,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
