import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/navigation/async_single_flight.dart';

void main() {
  test('ignores repeated attempts until the active operation finishes', () async {
    final gate = AsyncSingleFlight();
    final release = Completer<void>();
    var calls = 0;

    final first = gate.run(() async {
      calls++;
      await release.future;
    });
    final duplicate = await gate.run(() async => calls++);

    expect(duplicate, isFalse);
    expect(calls, 1);
    expect(gate.isActive, isTrue);

    release.complete();
    expect(await first, isTrue);
    expect(gate.isActive, isFalse);
  });

  test('releases the gate after an error', () async {
    final gate = AsyncSingleFlight();

    await expectLater(
      gate.run(() async => throw StateError('failed')),
      throwsStateError,
    );

    expect(await gate.run(() async {}), isTrue);
  });
}
