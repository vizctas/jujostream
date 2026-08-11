import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/notifications/notification_mirror_envelope.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  final now = DateTime.utc(2026, 8, 11, 12);

  test('round trips authenticated notification payload', () async {
    final codec = NotificationMirrorEnvelope(clock: () => now);
    final encoded = await codec.seal({'title': 'Ready'}, token);

    expect(await codec.open(encoded, token), {'title': 'Ready'});
    expect(encoded, isNot(contains('Ready')));
  });

  test('rejects wrong token and replay', () async {
    final codec = NotificationMirrorEnvelope(clock: () => now);
    final encoded = await codec.seal({'title': 'Ready'}, token);

    await expectLater(
      codec.open(encoded, 'fedcba9876543210fedcba9876543210'),
      throwsA(anything),
    );
    expect(await codec.open(encoded, token), {'title': 'Ready'});
    await expectLater(codec.open(encoded, token), throwsFormatException);
  });

  test('rejects stale authenticated payload', () async {
    final sender = NotificationMirrorEnvelope(clock: () => now);
    final encoded = await sender.seal({'title': 'Old'}, token);
    final receiver = NotificationMirrorEnvelope(
      clock: () => now.add(const Duration(minutes: 2)),
    );

    await expectLater(receiver.open(encoded, token), throwsFormatException);
  });
}
