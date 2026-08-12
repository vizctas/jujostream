import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/library/latest_window_scheduler.dart';

void main() {
  test('never exceeds its concurrency budget', () async {
    final gates = <int, Completer<void>>{};
    var peak = 0;
    var active = 0;
    final scheduler = LatestWindowScheduler<int>(
      keyOf: (item) => '$item',
      load: (item) async {
        active++;
        peak = active > peak ? active : peak;
        await (gates[item] = Completer<void>()).future;
        active--;
      },
    );

    scheduler.schedule([1, 2, 3, 4]);
    await Future<void>.delayed(Duration.zero);
    expect(gates.keys, {1, 2});
    expect(peak, 2);

    gates[1]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(gates.keys, {1, 2, 3});
    expect(peak, 2);

    for (var turn = 0; turn < 4; turn++) {
      for (final gate in gates.values.toList()) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    scheduler.dispose();
  });

  test('new window replaces obsolete pending work', () async {
    final started = <int>[];
    final gates = <int, Completer<void>>{};
    final scheduler = LatestWindowScheduler<int>(
      keyOf: (item) => '$item',
      load: (item) async {
        started.add(item);
        await (gates[item] = Completer<void>()).future;
      },
    );

    scheduler.schedule([1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    scheduler.schedule([4, 4, 5]);
    expect(scheduler.pendingCount, 2);

    gates[1]!.complete();
    gates[2]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 4, 5]);
    expect(started, isNot(contains(3)));

    gates[4]!.complete();
    gates[5]!.complete();
    scheduler.dispose();
  });
}
