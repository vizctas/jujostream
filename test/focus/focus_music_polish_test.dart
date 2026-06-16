import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/screens/settings/settings_screen.dart';
import 'package:jujostream/widgets/focus_music_mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stand-by volume labels use real 0.00-1.00 values', () {
    expect(formatStandbyVolumeLabel(0), '0.00');
    expect(formatStandbyVolumeLabel(0.01), '0.01');
    expect(formatStandbyVolumeLabel(0.25), '0.25');
    expect(formatStandbyVolumeLabel(1), '1.00');
  });

  test('focus music tuning defaults small and clamps', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = await ThemeProvider.load();

    expect(provider.focusMusicScale, 0.40);
    expect(provider.focusMusicOpacity, 0.82);

    await provider.setFocusMusicScale(9);
    await provider.setFocusMusicOpacity(0);

    final restored = await ThemeProvider.load();
    expect(restored.focusMusicScale, 1.5);
    expect(restored.focusMusicOpacity, 0.2);
  });

  testWidgets('focus music mini player shows now playing and track name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusMusicMiniPlayer(trackName: 'Very large music name test'),
        ),
      ),
    );

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Very large music name test'), findsOneWidget);
    expect(find.byType(ScrollingOverflowText), findsOneWidget);
  });
}
