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
                    notificationCount:
                        notification.dedupKey == notifications.last.dedupKey &&
                            notifications.length > 1
                        ? notifications.length
                        : null,
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
  final int? notificationCount;
  final VoidCallback onDismiss;

  const _NotificationMirrorCard({
    required this.notification,
    required this.detailMode,
    required this.sizeScale,
    required this.opacity,
    required this.notificationCount,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final fg = isLight ? Colors.black87 : const Color(0xFF202124);
    final sub = isLight ? Colors.black54 : Colors.black.withValues(alpha: 0.66);
    final width = MediaQuery.sizeOf(context).width;
    final scale = sizeScale.clamp(0.50, 2.0);
    final effectiveOpacity = opacity.clamp(0.20, 1.00);
    final cardWidth = width < 520
        ? width - 32
        : (242.0 * scale).clamp(170.0, 484.0);
    final header = notification.appLabel.isEmpty
        ? notification.packageName
        : notification.appLabel;
    final message = _messageText(notification, detailMode);
    final bg = isLight
        ? tp.surface.withValues(alpha: effectiveOpacity)
        : Colors.white.withValues(alpha: 0.96 * effectiveOpacity);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: cardWidth.clamp(170.0, 484.0),
        constraints: BoxConstraints(minHeight: 72 * scale),
        padding: EdgeInsets.fromLTRB(
          10 * scale,
          9 * scale,
          8 * scale,
          10 * scale,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8 * scale),
          border: Border.all(
            color: isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.18 * effectiveOpacity),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: (isLight ? 0.12 : 0.24) * effectiveOpacity,
              ),
              blurRadius: 14 * scale,
              offset: Offset(0, 5 * scale),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 11 * scale,
                  height: 11 * scale,
                  decoration: BoxDecoration(
                    color: tp.accent,
                    borderRadius: BorderRadius.circular(3 * scale),
                  ),
                ),
                SizedBox(width: 7 * scale),
                Expanded(
                  child: Text(
                    header,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
                if (notificationCount != null) ...[
                  SizedBox(width: 6 * scale),
                  _NotificationCountBadge(
                    count: notificationCount!,
                    scale: scale,
                    accent: tp.accent,
                  ),
                ],
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: Padding(
                    padding: EdgeInsets.all(3 * scale),
                    child: Icon(
                      Icons.close_rounded,
                      color: sub,
                      size: 14 * scale,
                    ),
                  ),
                ),
              ],
            ),
            if (message.isNotEmpty) ...[
              SizedBox(height: 9 * scale),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 18 * scale, right: 6 * scale),
                  child: Text(
                    message,
                    maxLines: detailMode == NotificationDetailMode.full ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sub,
                      fontSize: 10.5 * scale,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _messageText(
    MirroredNotification notification,
    NotificationDetailMode detailMode,
  ) {
    final title = notification.title.trim();
    final body = notification.body.trim();
    if (detailMode == NotificationDetailMode.summary) {
      return title.isNotEmpty ? title : body;
    }
    if (title.isEmpty) return body;
    if (body.isEmpty || body == title) return title;
    return '$title\n$body';
  }
}

class _NotificationCountBadge extends StatelessWidget {
  final int count;
  final double scale;
  final Color accent;

  const _NotificationCountBadge({
    required this.count,
    required this.scale,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: BoxConstraints(minWidth: 18 * scale),
      padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 9 * scale,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
