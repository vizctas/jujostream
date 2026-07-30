import 'package:flutter/material.dart';

/// Marks a server as cloud-registered.
///
/// Was written twice with different sizes — 9px text with a 12px glyph in the
/// grid, 8px with a 10px glyph in focus mode — so the same badge read
/// differently depending on the layout, and the smaller one fell below the
/// readable floor.
class CloudBadge extends StatelessWidget {
  const CloudBadge({super.key, this.compact = false});

  /// Slightly tighter, for the focus-mode circle where space is scarce.
  /// The type size does not shrink; only the padding does.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: Localizations.localeOf(context).languageCode == 'es'
          ? 'Servidor en la nube'
          : 'Cloud server',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud, size: 12, color: Colors.blueAccent),
            const SizedBox(width: 4),
            Text(
              'CLOUD',
              style: TextStyle(
                color: Colors.blueAccent.shade100,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
