import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/ui/motion_policy.dart';

void main() {
  test('normal motion keeps bounded premium durations', () {
    const motion = MotionPolicy(reduceMotion: false, performanceMode: false);

    expect(motion.allowContinuousEffects, isTrue);
    expect(motion.focusDuration, const Duration(milliseconds: 160));
    expect(motion.routeDuration, const Duration(milliseconds: 260));
  });

  test('reduced motion removes continuous and focus movement', () {
    const motion = MotionPolicy(reduceMotion: true, performanceMode: false);

    expect(motion.allowContinuousEffects, isFalse);
    expect(motion.focusDuration, Duration.zero);
    expect(motion.routeDuration, const Duration(milliseconds: 120));
  });

  test('performance mode disables continuous effects', () {
    const motion = MotionPolicy(reduceMotion: false, performanceMode: true);

    expect(motion.allowContinuousEffects, isFalse);
  });
}
