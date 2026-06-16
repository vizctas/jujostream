import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';

import '../../models/mirrored_notification.dart';

class NotificationMirrorPlatform {
  NotificationMirrorPlatform._();

  static final instance = NotificationMirrorPlatform._();

  static const _method = MethodChannel('com.jujostream/notification_mirror');
  static const _events = EventChannel(
    'com.jujostream/notification_mirror_events',
  );

  Stream<MirroredNotification>? _notifications;

  Stream<MirroredNotification> get notifications {
    if (!io.Platform.isAndroid) return const Stream.empty();
    return _notifications ??= _events
        .receiveBroadcastStream()
        .where((event) {
          return event is Map && event['type'] == 'posted';
        })
        .map((event) {
          final data = Map<String, dynamic>.from(event as Map);
          data.remove('type');
          return MirroredNotification.fromJson(data);
        });
  }

  Future<bool> isNotificationAccessGranted() async {
    if (!io.Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('isNotificationAccessGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationAccessSettings() async {
    if (!io.Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>(
            'openNotificationAccessSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, String>>> getInstalledApps() async {
    if (!io.Platform.isAndroid) return const [];
    try {
      final raw = await _method.invokeMethod<List<dynamic>>(
        'getInstalledNotificationApps',
      );
      if (raw == null) return const [];
      return raw.whereType<Map>().map((item) {
        return item.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!io.Platform.isAndroid) return true;
    try {
      return await _method.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openBatteryOptimizationRequest() async {
    if (!io.Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>(
            'openBatteryOptimizationRequest',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
