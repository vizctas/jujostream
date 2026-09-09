import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/ui/input_idle.dart';

void main() {
  double opacityOf(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('hints fade out after 3s idle and return on input', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: IdleFade(child: Text('hint'))),
    );
    InputIdle.instance.poke();
    await tester.pump();
    expect(opacityOf(tester), 1);

    await tester.pump(InputIdle.timeout + const Duration(milliseconds: 10));
    await tester.pump();
    expect(opacityOf(tester), 0);

    InputIdle.instance.poke();
    await tester.pump();
    expect(opacityOf(tester), 1);

    // Let the re-armed idle timer fire so no timer outlives the test.
    await tester.pump(InputIdle.timeout + const Duration(milliseconds: 10));
  });
}
