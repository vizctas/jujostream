import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/notification_mirror_pairing.dart';
import '../companion/companion_server.dart';
import '../crypto/client_identity.dart';
import 'notification_mirror_controller.dart';

class NotificationMirrorPairingClient {
  const NotificationMirrorPairingClient._();

  static Future<NotificationPairStatus> requestAccess({
    required DiscoveredNotificationBroadcaster broadcaster,
    required NotificationMirrorController controller,
    Duration timeout = const Duration(seconds: 60),
    Duration pollEvery = const Duration(seconds: 2),
  }) async {
    final receiverUrl = await CompanionServer.instance.lanUrl;
    if (receiverUrl == null || receiverUrl.isEmpty) {
      return NotificationPairStatus.denied;
    }

    final requestUri = Uri.tryParse(
      '${broadcaster.url}/api/notifications/pair/request',
    );
    if (requestUri == null) return NotificationPairStatus.denied;

    final response = await _postJson(requestUri, {
      'receiverDeviceId': ClientIdentity.uniqueId,
      'receiverName': Platform.localHostname.isNotEmpty
          ? Platform.localHostname
          : 'Jujo Receiver',
      'receiverUrl': receiverUrl,
      'receiverToken': controller.receiverToken,
    });
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return NotificationPairStatus.denied;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final requestId = (data['requestId'] ?? '').toString();
    var status = NotificationPairStatus.fromName(data['status']?.toString());
    if (status == NotificationPairStatus.accepted) {
      await controller.addPairedBroadcaster(
        deviceId: broadcaster.deviceId,
        deviceName: broadcaster.deviceName,
        url: broadcaster.url,
      );
      return status;
    }
    if (requestId.isEmpty) return NotificationPairStatus.denied;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      final pollUri = Uri.tryParse(
        '${broadcaster.url}/api/notifications/pair/status'
        '?requestId=$requestId&receiverDeviceId=${ClientIdentity.uniqueId}',
      );
      if (pollUri == null) break;
      final poll = await _get(pollUri);
      if (poll == null || poll.statusCode < 200 || poll.statusCode >= 300) {
        continue;
      }
      final pollData = jsonDecode(poll.body) as Map<String, dynamic>;
      status = NotificationPairStatus.fromName(pollData['status']?.toString());
      if (status == NotificationPairStatus.accepted) {
        await controller.addPairedBroadcaster(
          deviceId: broadcaster.deviceId,
          deviceName: broadcaster.deviceName,
          url: broadcaster.url,
        );
        return status;
      }
      if (status == NotificationPairStatus.denied) return status;
    }
    return NotificationPairStatus.denied;
  }

  static Future<http.Response?> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    try {
      return await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  static Future<http.Response?> _get(Uri uri) async {
    try {
      return await http.get(uri).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }
}
