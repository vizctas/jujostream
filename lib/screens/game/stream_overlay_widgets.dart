import 'package:flutter/material.dart';

/// A toggle button used in the stream overlay quick-menu row.
///
/// Shows an icon inside a rounded container with active/focused states,
/// and an optional premium badge.
Widget buildQuickToggle(
  IconData icon,
  String label,
  bool active,
  VoidCallback onTap, {
  bool focused = false,
  bool premium = false,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.18)
                    : focused
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                boxShadow: (active || focused)
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: active || focused ? Colors.white : Colors.white54,
                size: 24,
              ),
            ),
            if (premium)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: active || focused ? Colors.white : Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

/// A ◀ value ▶ row in the stream overlay, stepped with D-pad left/right.
Widget buildStepperTile({
  required String label,
  required Widget value,
  required String semanticValue,
  required VoidCallback onPrev,
  required VoidCallback onNext,
  bool focused = false,
}) {
  final fg = focused ? Colors.white : Colors.white70;
  return Semantics(
    label: label,
    value: semanticValue,
    onIncrease: onNext,
    onDecrease: onPrev,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: focused
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: onPrev,
            icon: Icon(Icons.chevron_left_rounded, color: fg),
            visualDensity: VisualDensity.compact,
          ),
          value,
          IconButton(
            onPressed: onNext,
            icon: Icon(Icons.chevron_right_rounded, color: fg),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    ),
  );
}

/// A menu tile used in the stream overlay action list.
///
/// Shows an icon + label in a ListTile with focus highlight.
Widget buildMenuTile(
  IconData icon,
  String label,
  VoidCallback onTap, {
  Color color = Colors.white70,
  bool focused = false,
}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    decoration: BoxDecoration(
      color: focused
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: ListTile(
      dense: true,
      leading: Icon(icon, color: focused ? Colors.white : color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: focused ? Colors.white : color,
          fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      hoverColor: Colors.white.withValues(alpha: 0.05),
    ),
  );
}
