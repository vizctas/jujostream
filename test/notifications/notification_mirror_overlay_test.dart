import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/mirrored_notification.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/services/notifications/notification_mirror_controller.dart';
import 'package:jujostream/widgets/notification_mirror_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MirroredNotification sample(String id) => MirroredNotification(
    id: id,
    sourceDeviceId: 'phone-1',
    sourceDeviceName: 'Pixel',
    packageName: 'com.ubercab',
    appLabel: 'Uber',
    title: 'Ride update $id',
    body: 'Driver arriving soon',
    postedAt: DateTime.utc(2026, 6, 14, 18, 0, id.codeUnitAt(0)),
    isOngoing: false,
  );

  testWidgets('overlay stacks visible notifications and dismisses one card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();
    final controller = NotificationMirrorController();
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setMode(NotificationMirrorMode.receiver);
    controller.handleRemotePosted(sample('a'));
    controller.handleRemotePosted(sample('b'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [SizedBox.expand(), NotificationMirrorOverlay()],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Ride update a'), findsOneWidget);
    expect(find.textContaining('Ride update b'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();

    expect(controller.visibleNotifications.length, 1);
    for (final notification in controller.visibleNotifications) {
      controller.dismiss(notification.dedupKey);
    }
  });

  testWidgets('stream overlay hides when stream notifications are disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();
    final controller = NotificationMirrorController();
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setMode(NotificationMirrorMode.receiver);
    await controller.setStreamEnabled(false);
    controller.handleRemotePosted(sample('c'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SizedBox.expand(),
                NotificationMirrorOverlay(streamOverlay: true),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ride update c'), findsNothing);
    for (final notification in controller.visibleNotifications) {
      controller.dismiss(notification.dedupKey);
    }
  });

  testWidgets('summary detail mode hides notification body', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();
    final controller = NotificationMirrorController();
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setMode(NotificationMirrorMode.receiver);
    await controller.setDetailMode(NotificationDetailMode.summary);
    controller.handleRemotePosted(sample('d'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [SizedBox.expand(), NotificationMirrorOverlay()],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ride update d'), findsOneWidget);
    expect(find.text('Driver arriving soon'), findsNothing);
    for (final notification in controller.visibleNotifications) {
      controller.dismiss(notification.dedupKey);
    }
  });
}
