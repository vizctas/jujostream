import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/ui/proportional_scale.dart';

void main() {
  testWidgets('scales layout footprint and child paint proportionally', (
    tester,
  ) async {
    const scaleKey = Key('scale');
    const childKey = Key('child');

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: ProportionalScale(
            key: scaleKey,
            scale: 0.70,
            baseWidth: 200,
            child: SizedBox(key: childKey, width: 200, height: 100),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(scaleKey)), const Size(140, 70));
    expect(tester.getSize(find.byKey(childKey)), const Size(200, 100));
  });
}
