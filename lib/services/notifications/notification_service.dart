import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static const _kEnrichId = 1;
  static const _kChannelId = 'jujo_enrichment';
  static const _kChannelName = 'Actualizaciones de metadata';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    _initialized = true;
  }

  static Future<void> showEnrichment(String message) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: 'Notificaciones de actualizaciones de metadata',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      indeterminate: true,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      id: _kEnrichId,
      title: 'JUJO Stream',
      body: message,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> dismissEnrichment() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _kEnrichId);
  }
}
