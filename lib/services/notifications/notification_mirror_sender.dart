import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/mirrored_notification.dart';

typedef NotificationMirrorSendFn =
    Future<bool> Function(MirroredNotification notification);

class NotificationMirrorSender {
  const NotificationMirrorSender._();

  static Future<bool> send({
    required MirroredNotification notification,
    required String receiverUrl,
    required String token,
  }) async {
    final base = receiverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final authToken = token.trim();
    if (base.isEmpty || authToken.isEmpty) return false;

    final uri = Uri.tryParse('$base/api/notifications/mirror');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Jujo-Notification-Token': authToken,
            },
            body: jsonEncode(notification.toJson()),
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
