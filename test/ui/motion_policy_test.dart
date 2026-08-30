import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/themes/launcher_theme.dart';
import 'package:jujostream/ui/motion_policy.dart';

void main() {
  group('MotionPolicy', () {
    test('premium motion stays inside approved timing bounds', () {
      const motion = MotionPolicy(reduceMotion: false, performanceMode: false);
      expect(motion.tier, MotionTier.premium);
      expect(motion.allowContinuousEffects, isTrue);
      expect(motion.focusDuration, const Duration(milliseconds: 160));
      expect(motion.routeDuration, const Duration(milliseconds: 320));
    });

    test('accessibility wins over every device capability', () {
      expect(
        MotionPolicy.resolveTier(
          reduceMotion: true,
          performanceMode: true,
          lowRamDevice: true,
          tvDevice: true,
        ),
        MotionTier.reduced,
      );
    });

    test('performance and low RAM select constrained independently', () {
      expect(
        MotionPolicy.resolveTier(
          reduceMotion: false,
          performanceMode: true,
          lowRamDevice: false,
          tvDevice: false,
        ),
        MotionTier.constrained,
      );
      expect(
        MotionPolicy.resolveTier(
          reduceMotion: false,
          performanceMode: false,
          lowRamDevice: true,
          tvDevice: true,
        ),
        MotionTier.constrained,
      );
    });

    test('TV defaults to standard and other capable devices to premium', () {
      expect(
        MotionPolicy.resolveTier(
          reduceMotion: false,
          performanceMode: false,
          lowRamDevice: false,
          tvDevice: true,
        ),
        MotionTier.standard,
      );
      expect(
        MotionPolicy.resolveTier(
          reduceMotion: false,
          performanceMode: false,
          lowRamDevice: false,
          tvDevice: false,
        ),
        MotionTier.premium,
      );
    });

    test('all launcher personalities remain distinct and bounded', () {
      final profiles = LauncherThemeId.values
          .map(LauncherMotionProfile.forTheme)
          .toList();
      expect(profiles.map((p) => p.personality).toSet(), hasLength(5));
      for (final profile in profiles) {
        expect(profile.focusScale, inInclusiveRange(1.0, 1.025));
        expect(profile.directionalTravel, inInclusiveRange(0, 12));
      }
    });

    test('reduced and constrained never allow ornamental loops', () {
      for (final tier in [MotionTier.reduced, MotionTier.constrained]) {
        final motion = MotionPolicy(
          reduceMotion: tier == MotionTier.reduced,
          performanceMode: tier == MotionTier.constrained,
          resolvedTier: tier,
        );
        expect(motion.allowContinuousEffects, isFalse);
      }
    });
  });
}
