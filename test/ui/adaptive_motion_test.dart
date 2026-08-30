import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/ui/adaptive_motion.dart';
import 'package:jujostream/ui/motion_policy.dart';
import 'package:jujostream/ui/motion_scope.dart';

void main() {
  testWidgets('reduced focus is immediate and does not scale content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MotionScope(
        policy: MotionPolicy(
          reduceMotion: true,
          performanceMode: false,
          resolvedTier: MotionTier.reduced,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AdaptiveFocusSurface(
            focused: true,
            child: SizedBox(key: Key('content')),
          ),
        ),
      ),
    );
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
  });

  testWidgets('launcher profile controls focus expression', (tester) async {
    await tester.pumpWidget(
      const MotionScope(
        policy: MotionPolicy(
          reduceMotion: false,
          performanceMode: false,
          resolvedTier: MotionTier.premium,
          profile: LauncherMotionProfile(
            personality: MotionPersonality.bigScreen,
            focusScale: 1.025,
            focusTravel: 2,
            directionalTravel: 2,
            artworkDepth: false,
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AdaptiveFocusSurface(
            focused: true,
            child: SizedBox(key: Key('content')),
          ),
        ),
      ),
    );
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.025);
    expect(scale.duration, const Duration(milliseconds: 160));
  });

  test('motion policy never gates automatic video preview features', () {
    final source = File(
      'lib/screens/app_view/app_view_video_preview.dart',
    ).readAsStringSync();
    final start = source.indexOf('void _scheduleVideoPreview');
    final end = source.indexOf('String? _previewUrlFor', start);
    final scheduler = source.substring(start, end);
    expect(scheduler, isNot(contains('MotionPolicy')));
    expect(scheduler, isNot(contains('MotionScope')));
    expect(scheduler, isNot(contains('reduceEffects')));
    expect(scheduler, isNot(contains('performanceMode')));
    expect(scheduler, contains("isEnabled('game_video')"));
  });
}
