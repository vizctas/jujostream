import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/mirrored_notification.dart';
import 'package:jujostream/models/notification_mirror_pairing.dart';
import 'package:jujostream/services/notifications/notification_mirror_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MirroredNotification sample() => MirroredNotification(
    id: 'n1',
    sourceDeviceId: 'phone-1',
    sourceDeviceName: 'Pixel',
    packageName: 'com.ubercab',
    appLabel: 'Uber',
    title: 'Uber',
    body: 'Driver arriving soon',
    postedAt: DateTime.utc(2026, 6, 14, 18),
    isOngoing: false,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('discovery model parses broadcaster TXT record', () {
    final record = DiscoveredNotificationBroadcaster.fromNsd(
      host: 'phone.local.',
      port: 9876,
      txt: {
        'deviceId': utf8.encode('phone-1'),
        'deviceName': utf8.encode('Pixel'),
        'role': utf8.encode('broadcaster'),
        'apiVersion': utf8.encode('1'),
      },
    );

    expect(record, isNotNull);
    expect(record!.url, 'http://phone.local:9876');
    expect(record.canBroadcast, isTrue);
  });

  test(
    'pair request can be accepted and persisted as authorized receiver',
    () async {
      final controller = NotificationMirrorController();
      await controller.load();

      final request = controller.receivePairRequest(
        receiverDeviceId: 'tv-1',
        receiverName: 'Living Room TV',
        receiverUrl: 'http://192.168.1.40:9876',
        receiverToken: 'receiver-token',
      );

      expect(request.status, NotificationPairStatus.pending);
      expect(controller.pendingPairRequests.single.receiverDeviceId, 'tv-1');

      await controller.acceptPairRequest(request.requestId);

      expect(controller.pendingPairRequests, isEmpty);
      expect(
        controller.authorizedReceivers.single.receiverName,
        'Living Room TV',
      );
      expect(
        controller.pairRequestStatus(request.requestId),
        NotificationPairStatus.accepted,
      );
    },
  );

  test('broadcaster sends only to authorized receivers', () async {
    var sent = 0;
    final controller = NotificationMirrorController(
      sendFn: (_) async {
        sent++;
        return true;
      },
    );
    await controller.load();
    await controller.setMode(NotificationMirrorMode.broadcaster);
    await controller.setAllowedPackage('com.ubercab', true);

    controller.handleLocalPosted(sample());
    await Future<void>.delayed(Duration.zero);
    expect(sent, 0);

    final request = controller.receivePairRequest(
      receiverDeviceId: 'tv-1',
      receiverName: 'TV',
      receiverUrl: 'http://192.168.1.40:9876',
      receiverToken: 'token',
    );
    await controller.acceptPairRequest(request.requestId);

    controller.handleLocalPosted(sample().copyWith(id: 'n2'));
    await Future<void>.delayed(Duration.zero);
    expect(sent, 1);
  });

  test('receiver stores accepted broadcaster after pairing succeeds', () async {
    final controller = NotificationMirrorController();
    await controller.load();

    await controller.addPairedBroadcaster(
      deviceId: 'phone-1',
      deviceName: 'Pixel',
      url: 'http://192.168.1.20:9876',
    );

    expect(controller.pairedBroadcasters.single.deviceName, 'Pixel');
  });
}
