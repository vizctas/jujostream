import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mirrored_notification.dart';
import '../providers/theme_provider.dart';
import '../services/notifications/notification_mirror_controller.dart';

class NotificationMirrorOverlay extends StatelessWidget {
  final double bottomOffset;
  final double topOffset;
  final double rightOffset;
  final double leftOffset;
  final bool streamOverlay;

  const NotificationMirrorOverlay({
    super.key,
    this.bottomOffset = 24,
    this.topOffset = 24,
    this.rightOffset = 24,
    this.leftOffset = 24,
    this.streamOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationMirrorController>();
    final notifications = controller.visibleNotifications;
    if (streamOverlay && !controller.streamEnabled) {
      return const SizedBox.shrink();
    }
    if (notifications.isEmpty) return const SizedBox.shrink();
    final position = controller.position;
    final padding = MediaQuery.of(context).padding;
    final children = position.isTop ? notifications : notifications.reversed;

    return Positioned(
      left: position.isLeft ? leftOffset : null,
      right: position.isLeft ? null : rightOffset,
      top: position.isTop ? padding.top + topOffset : null,
      bottom: position.isTop ? null : padding.bottom + bottomOffset,
      child: IgnorePointer(
        ignoring: false,
        child: ExcludeFocus(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: position.isLeft
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              for (final notification in children)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _NotificationMirrorCard(
                    notification: notification,
                    detailMode: controller.detailMode,
                    sizeScale: controller.sizeScale,
                    opacity: controller.opacity,
                    onDismiss: () => controller.dismiss(notification.dedupKey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationMirrorCard extends StatelessWidget {
  final MirroredNotification notification;
  final NotificationDetailMode detailMode;
  final double sizeScale;
  final double opacity;
  final VoidCallback onDismiss;

  const _NotificationMirrorCard({
    required this.notification,
    required this.detailMode,
    required this.sizeScale,
    required this.opacity,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final fg = isLight ? Colors.black87 : Colors.white;
    final sub = isLight ? Colors.black54 : Colors.white70;
    final width = MediaQuery.sizeOf(context).width;
    final scale = sizeScale.clamp(0.50, 2.0);
    final effectiveOpacity = opacity.clamp(0.20, 1.00);
    final cardWidth = width < 520
        ? width - 32
        : (236.0 * scale).clamp(160.0, 472.0);
    final showBody =
        detailMode == NotificationDetailMode.full &&
        notification.body.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: cardWidth.clamp(160.0, 472.0),
        constraints: BoxConstraints(minHeight: 66 * scale),
        padding: EdgeInsets.fromLTRB(
          10 * scale,
          9 * scale,
          8 * scale,
          9 * scale,
        ),
        decoration: BoxDecoration(
          color: tp.surface.withValues(
            alpha: (isLight ? 0.94 : 0.86) * effectiveOpacity,
          ),
          borderRadius: BorderRadius.circular(86),
          border: Border.all(color: tp.accent.withValues(alpha: 0.30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.16 : 0.36),
              blurRadius: 22 * scale,
              offset: Offset(0, 8 * scale),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48 * scale,
              height: 48 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tp.accent.withValues(alpha: isLight ? 0.16 : 0.22),
              ),
              child: Icon(
                Icons.notifications_rounded,
                color: tp.accent,
                size: 24 * scale,
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.appLabel.isEmpty
                        ? notification.packageName
                        : notification.appLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sub,
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 3 * scale),
                  if (notification.title.isNotEmpty)
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (showBody) ...[
                    SizedBox(height: 2 * scale),
                    Text(
                      notification.body,
                      maxLines: scale < 1 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sub,
                        fontSize: 11 * scale,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: Padding(
                padding: EdgeInsets.all(5 * scale),
                child: Icon(Icons.close_rounded, color: sub, size: 16 * scale),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
