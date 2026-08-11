import 'dart:async';

import 'package:http/http.dart' as http;

import '../../models/mirrored_notification.dart';
import 'notification_mirror_envelope.dart';

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
    if (uri == null || !_isPrivateEndpoint(uri)) return false;

    try {
      final body = await NotificationMirrorEnvelope().seal(
        notification.toJson(),
        authToken,
      );
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      final response = await request.send().timeout(const Duration(seconds: 3));
      await response.stream.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static bool _isPrivateEndpoint(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      return false;
    }
    final parts = uri.host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}
