import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stream overlay defaults to 75% opacity on the theme background', () async {
    SharedPreferences.setMockInitialValues({});
    final tp = await ThemeProvider.load();
    expect(tp.overlayOpacity, 0.75);
    expect(tp.overlayBgChoice, 'theme');
    expect(tp.overlayBackground, tp.background.withValues(alpha: 0.75));
  });

  test('opacity steps by 5% and clamps to 40–100%', () async {
    SharedPreferences.setMockInitialValues({});
    final tp = await ThemeProvider.load();
    await tp.setOverlayOpacity(tp.overlayOpacity + 0.05);
    expect(tp.overlayOpacity, 0.80);
    await tp.setOverlayOpacity(0.10);
    expect(tp.overlayOpacity, 0.40);
    await tp.setOverlayOpacity(1.7);
    expect(tp.overlayOpacity, 1.0);
  });

  test('background cycles both ways and ignores unknown stored values', () async {
    SharedPreferences.setMockInitialValues({'stream_overlay_bg': 'neon'});
    final tp = await ThemeProvider.load();
    expect(tp.overlayBgChoice, 'theme');
    await tp.cycleOverlayBg(-1);
    expect(tp.overlayBgChoice, 'accent');
    await tp.cycleOverlayBg(1);
    expect(tp.overlayBgChoice, 'theme');
    await tp.cycleOverlayBg(2);
    expect(tp.overlayBackground, Colors.black.withValues(alpha: 0.75));
  });
}
