import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/ui/accessible_action.dart';
import 'package:jujostream/ui/motion_policy.dart';
import 'package:jujostream/ui/motion_scope.dart';

void main() {
  Widget harness({required VoidCallback onActivate}) {
    return MaterialApp(
      home: MotionScope(
        policy: const MotionPolicy(
          reduceMotion: true,
          performanceMode: false,
          resolvedTier: MotionTier.reduced,
        ),
        child: Scaffold(
          body: AccessibleAction(
            label: 'Abrir Tekken 8',
            onActivate: onActivate,
            autofocus: true,
            child: const Text('Tekken 8'),
          ),
        ),
      ),
    );
  }

  testWidgets('exposes one semantic button with the supplied label', (
    tester,
  ) async {
    await tester.pumpWidget(harness(onActivate: () {}));

    expect(find.bySemanticsLabel('Abrir Tekken 8'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Abrir Tekken 8')),
      matchesSemantics(
        label: 'Abrir Tekken 8',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('activates from keyboard and guarantees a 48px target', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(harness(onActivate: () => activations++));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 1);
    final size = tester.getSize(find.byType(AccessibleAction));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
