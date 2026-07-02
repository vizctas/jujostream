import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/mirrored_notification.dart';
import 'package:jujostream/services/notifications/notification_mirror_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MirroredNotification sample({
    String id = 'n1',
    String packageName = 'com.ubercab',
    String title = 'Uber',
    String body = 'Driver arriving soon',
    bool isOngoing = false,
    bool isSilent = false,
    bool isGroupSummary = false,
    DateTime? postedAt,
  }) {
    return MirroredNotification(
      id: id,
      sourceDeviceId: 'phone-1',
      sourceDeviceName: 'Pixel',
      packageName: packageName,
      appLabel: 'Uber',
      title: title,
      body: body,
      postedAt: postedAt ?? DateTime.utc(2026, 6, 14, 18),
      isOngoing: isOngoing,
      isSilent: isSilent,
      isGroupSummary: isGroupSummary,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mirrored notification roundtrips through json and keeps dedup key', () {
    final notification = sample();
    final decoded = MirroredNotification.fromJson(notification.toJson());

    expect(decoded.toJson(), notification.toJson());
    expect(decoded.dedupKey, 'phone-1|com.ubercab|n1|1781460000000');
  });

  test(
    'controller requires explicit app allowlist for local capture',
    () async {
      final controller = NotificationMirrorController();
      await controller.load();
      await controller.setMode(NotificationMirrorMode.receiver);

      controller.handleLocalPosted(sample());
      expect(controller.visibleNotifications, isEmpty);

      await controller.setAllowedPackage('com.ubercab', true);
      controller.handleLocalPosted(sample(id: 'n2'));
      expect(controller.visibleNotifications.single.title, 'Uber');
    },
  );

  test('mode controls local display and broadcast independently', () async {
    final sent = <MirroredNotification>[];
    final controller = NotificationMirrorController(
      sendFn: (notification) async {
        sent.add(notification);
        return true;
      },
    );
    await controller.load();
    await controller.setAllowedPackage('com.ubercab', true);
    final request = controller.receivePairRequest(
      receiverDeviceId: 'tv-1',
      receiverName: 'TV',
      receiverUrl: 'http://192.168.1.40:9876',
      receiverToken: 'token',
    );
    await controller.acceptPairRequest(request.requestId);

    await controller.setMode(NotificationMirrorMode.broadcaster);
    controller.handleLocalPosted(sample(id: 'n1'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.visibleNotifications, isEmpty);
    expect(sent.map((n) => n.id), ['n1']);

    await controller.setMode(NotificationMirrorMode.both);
    controller.handleLocalPosted(sample(id: 'n2'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.visibleNotifications.single.id, 'n2');
    expect(sent.map((n) => n.id), ['n1', 'n2']);
  });

  test(
    'controller filters ongoing and silent notifications by default',
    () async {
      final controller = NotificationMirrorController();
      await controller.load();
      await controller.setMode(NotificationMirrorMode.receiver);
      await controller.setAllowedPackage('com.ubercab', true);

      controller.handleLocalPosted(sample(id: 'ongoing', isOngoing: true));
      controller.handleLocalPosted(sample(id: 'silent', isSilent: true));

      expect(controller.visibleNotifications, isEmpty);
    },
  );

  test('controller filters Android group summary notifications', () async {
    final controller = NotificationMirrorController();
    await controller.load();
    await controller.setMode(NotificationMirrorMode.receiver);
    await controller.setAllowedPackage('com.ubercab', true);

    controller.handleLocalPosted(
      sample(id: 'summary', title: '2 notifications', isGroupSummary: true),
    );

    expect(controller.visibleNotifications, isEmpty);
  });

  test(
    'controller enforces max stack and dedupes repeated notifications',
    () async {
      final controller = NotificationMirrorController();
      await controller.load();
      await controller.setMode(NotificationMirrorMode.receiver);
      await controller.setAllowedPackage('com.ubercab', true);
      await controller.setMaxVisible(2);

      controller.handleLocalPosted(sample(id: 'n1'));
      controller.handleLocalPosted(sample(id: 'n1'));
      controller.handleLocalPosted(sample(id: 'n2'));
      controller.handleLocalPosted(sample(id: 'n3'));

      expect(controller.visibleNotifications.map((n) => n.id), ['n2', 'n3']);
    },
  );

  test(
    'remote notifications display in receiver mode without local allowlist',
    () async {
      final controller = NotificationMirrorController();
      await controller.load();
      await controller.setMode(NotificationMirrorMode.receiver);

      controller.handleRemotePosted(sample(packageName: 'com.ubercab'));

      expect(controller.visibleNotifications.single.packageName, 'com.ubercab');
    },
  );

  test('overlay presentation settings persist and clamp size', () async {
    final controller = NotificationMirrorController();
    await controller.load();

    expect(controller.detailMode, NotificationDetailMode.full);
    expect(controller.position, NotificationOverlayPosition.bottomRight);
    expect(controller.sizeScale, 1.0);
    expect(controller.opacity, 0.86);
    expect(controller.streamEnabled, isTrue);

    await controller.setDetailMode(NotificationDetailMode.summary);
    await controller.setPosition(NotificationOverlayPosition.topLeft);
    await controller.setSizeScale(2);
    await controller.setOpacity(0);
    await controller.setStreamEnabled(false);

    final restored = NotificationMirrorController();
    await restored.load();

    expect(restored.detailMode, NotificationDetailMode.summary);
    expect(restored.position, NotificationOverlayPosition.topLeft);
    expect(restored.sizeScale, 2.0);
    expect(restored.opacity, 0.2);
    expect(restored.streamEnabled, isFalse);
  });
}
