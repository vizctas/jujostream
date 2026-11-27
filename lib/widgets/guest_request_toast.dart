import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/sync/guest_link.dart';

/// Non-modal "guest wants to join" card for the stream overlay. Only the card
/// takes touches; everything around it still reaches the game.
class GuestRequestToast extends StatelessWidget {
  const GuestRequestToast({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
    this.queued = 0,
    this.focusedButton,
  });

  final GuestRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Further requests waiting behind this one.
  final int queued;

  /// 0 = accept, 1 = decline while the gamepad owns focus; null otherwise.
  final int? focusedButton;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xE6202028),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.guestWantsToJoin(
                request.guestEmail,
                l.coopRoleLabel(request.role),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            if (queued > 0)
              Text(
                '+$queued',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(l.accept, onAccept, focusedButton == 0, true),
                const SizedBox(width: 8),
                _button(l.decline, onDecline, focusedButton == 1, false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, bool focused, bool primary) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: primary ? Colors.teal : Colors.white12,
        side: focused ? const BorderSide(color: Colors.white, width: 2) : null,
      ),
      child: Text(label),
    );
  }
}
