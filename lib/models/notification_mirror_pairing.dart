import 'dart:convert';
import 'dart:io';

enum NotificationPairStatus {
  pending,
  accepted,
  denied;

  static NotificationPairStatus fromName(String? value) {
    return NotificationPairStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => NotificationPairStatus.pending,
    );
  }
}

class AuthorizedNotificationReceiver {
  final String receiverDeviceId;
  final String receiverName;
  final String receiverUrl;
  final String receiverToken;
  final DateTime acceptedAt;

  const AuthorizedNotificationReceiver({
    required this.receiverDeviceId,
    required this.receiverName,
    required this.receiverUrl,
    required this.receiverToken,
    required this.acceptedAt,
  });

  Map<String, dynamic> toJson() => {
    'receiverDeviceId': receiverDeviceId,
    'receiverName': receiverName,
    'receiverUrl': receiverUrl,
    'receiverToken': receiverToken,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
  };

  factory AuthorizedNotificationReceiver.fromJson(Map<String, dynamic> json) {
    return AuthorizedNotificationReceiver(
      receiverDeviceId: (json['receiverDeviceId'] ?? '').toString(),
      receiverName: (json['receiverName'] ?? '').toString(),
      receiverUrl: (json['receiverUrl'] ?? '').toString(),
      receiverToken: (json['receiverToken'] ?? '').toString(),
      acceptedAt:
          DateTime.tryParse((json['acceptedAt'] ?? '').toString())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class NotificationPairRequest {
  final String requestId;
  final String receiverDeviceId;
  final String receiverName;
  final String receiverUrl;
  final String receiverToken;
  final NotificationPairStatus status;
  final DateTime requestedAt;

  const NotificationPairRequest({
    required this.requestId,
    required this.receiverDeviceId,
    required this.receiverName,
    required this.receiverUrl,
    required this.receiverToken,
    required this.status,
    required this.requestedAt,
  });

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'receiverDeviceId': receiverDeviceId,
    'receiverName': receiverName,
    'receiverUrl': receiverUrl,
    'receiverToken': receiverToken,
    'status': status.name,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory NotificationPairRequest.fromJson(Map<String, dynamic> json) {
    return NotificationPairRequest(
      requestId: (json['requestId'] ?? '').toString(),
      receiverDeviceId: (json['receiverDeviceId'] ?? '').toString(),
      receiverName: (json['receiverName'] ?? '').toString(),
      receiverUrl: (json['receiverUrl'] ?? '').toString(),
      receiverToken: (json['receiverToken'] ?? '').toString(),
      status: NotificationPairStatus.fromName(json['status']?.toString()),
      requestedAt:
          DateTime.tryParse((json['requestedAt'] ?? '').toString())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  NotificationPairRequest copyWith({NotificationPairStatus? status}) {
    return NotificationPairRequest(
      requestId: requestId,
      receiverDeviceId: receiverDeviceId,
      receiverName: receiverName,
      receiverUrl: receiverUrl,
      receiverToken: receiverToken,
      status: status ?? this.status,
      requestedAt: requestedAt,
    );
  }
}

class DiscoveredNotificationBroadcaster {
  final String deviceId;
  final String deviceName;
  final String role;
  final String apiVersion;
  final String url;

  const DiscoveredNotificationBroadcaster({
    required this.deviceId,
    required this.deviceName,
    required this.role,
    required this.apiVersion,
    required this.url,
  });

  bool get canBroadcast => role == 'broadcaster' || role == 'both';

  Map<String, String> toTxt() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'role': role,
    'apiVersion': apiVersion,
    'port': Uri.tryParse(url)?.port.toString() ?? '',
  };

  static DiscoveredNotificationBroadcaster? fromNsd({
    required String? host,
    required int? port,
    required Map<String, List<int>?>? txt,
    List<InternetAddress> addresses = const [],
  }) {
    if (port == null || port <= 0) return null;
    final fields = <String, String>{};
    for (final entry in (txt ?? const <String, List<int>?>{}).entries) {
      final bytes = entry.value;
      fields[entry.key] = bytes == null ? '' : utf8.decode(bytes);
    }
    final id = fields['deviceId'] ?? '';
    if (id.isEmpty) return null;
    final address = addresses
        .where((addr) => !addr.isLoopback && !addr.address.startsWith('fe80:'))
        .firstOrNull;
    final hostValue = address?.address ?? host?.replaceAll(RegExp(r'\.$'), '');
    if (hostValue == null || hostValue.isEmpty) return null;
    return DiscoveredNotificationBroadcaster(
      deviceId: id,
      deviceName: fields['deviceName']?.isNotEmpty == true
          ? fields['deviceName']!
          : id,
      role: fields['role'] ?? 'broadcaster',
      apiVersion: fields['apiVersion'] ?? '1',
      url: 'http://$hostValue:$port',
    );
  }
}

class PairedNotificationBroadcaster {
  final String deviceId;
  final String deviceName;
  final String url;
  final DateTime acceptedAt;

  const PairedNotificationBroadcaster({
    required this.deviceId,
    required this.deviceName,
    required this.url,
    required this.acceptedAt,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'url': url,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
  };

  factory PairedNotificationBroadcaster.fromJson(Map<String, dynamic> json) {
    return PairedNotificationBroadcaster(
      deviceId: (json['deviceId'] ?? '').toString(),
      deviceName: (json['deviceName'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      acceptedAt:
          DateTime.tryParse((json['acceptedAt'] ?? '').toString())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
