import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/stream_configuration.dart';

void main() {
  group('launch reveal configuration', () {
    test('defaults to random', () {
      expect(
        const StreamConfiguration().launchRevealEffect,
        LaunchRevealEffect.random,
      );
    });

    test('round-trips every selection through JSON', () {
      for (final effect in LaunchRevealEffect.values) {
        final source = StreamConfiguration(launchRevealEffect: effect);
        final restored = StreamConfiguration.fromJson(source.toJson());
        expect(restored.launchRevealEffect, effect);
      }
    });

    test('corrupt or future enum values fail safely to random', () {
      expect(
        StreamConfiguration.fromJson({
          'launchRevealEffect': 999,
        }).launchRevealEffect,
        LaunchRevealEffect.random,
      );
      expect(
        StreamConfiguration.fromJson({
          'launchRevealEffect': 'cinematicIris',
        }).launchRevealEffect,
        LaunchRevealEffect.random,
      );
    });
  });
}
