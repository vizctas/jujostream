import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/stream_configuration.dart';
import 'package:jujostream/widgets/launch_reveal_transition.dart';

void main() {
  group('launch reveal selection', () {
    test('random always resolves to a concrete effect', () {
      for (var seed = 0; seed < 50; seed++) {
        final resolved = resolveLaunchRevealEffect(
          LaunchRevealEffect.random,
          reduceMotion: false,
          performanceMode: false,
          random: math.Random(seed),
        );
        expect(concreteLaunchRevealEffects, contains(resolved));
        expect(resolved, isNot(LaunchRevealEffect.random));
      }
    });

    test('accessibility and performance modes force Minimal Luxe', () {
      expect(
        resolveLaunchRevealEffect(
          LaunchRevealEffect.signalVeil,
          reduceMotion: true,
          performanceMode: false,
        ),
        LaunchRevealEffect.minimalLuxe,
      );
      expect(
        resolveLaunchRevealEffect(
          LaunchRevealEffect.prismBloom,
          reduceMotion: false,
          performanceMode: true,
        ),
        LaunchRevealEffect.minimalLuxe,
      );
      expect(
        launchRevealDuration(
          LaunchRevealEffect.minimalLuxe,
          reduceMotion: true,
          performanceMode: false,
        ),
        const Duration(milliseconds: 180),
      );
    });
  });

  for (final effect in concreteLaunchRevealEffects) {
    testWidgets('$effect renders safely throughout its timeline', (
      tester,
    ) async {
      for (final progress in const [0.0, 0.5, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: LaunchRevealTransition(
                effect: effect,
                animation: AlwaysStoppedAnimation(progress),
                child: const ColoredBox(
                  key: Key('opaque-launch-surface'),
                  color: Colors.black,
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('opaque-launch-surface')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
