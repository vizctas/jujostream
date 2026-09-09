import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cloud login uses the native TV IME bridge where Flutter loses DPAD',
    () {
      final source = File(
        'lib/screens/auth/cloud_auth_screen.dart',
      ).readAsStringSync();

      expect(source, contains('NativeTvImeBridge.instance'));
      expect(source, contains('readOnly: _usesNativeTvIme'));
      expect(source, contains('excludeChildFocus: _usesNativeTvIme'));
      expect(source, contains('canRequestFocus: !_usesNativeTvIme'));
      expect(source, contains('IgnorePointer(ignoring: _usesNativeTvIme'));
      expect(source, contains('interceptArrowKeys: !_usesNativeTvIme'));
      expect(source, isNot(contains("TextInput.show")));
    },
  );

  test('native bridge is a real Android EditText, not a custom keyboard', () {
    final source = File(
      'android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/NativeTvImeBridge.kt',
    ).readAsStringSync();

    expect(source, contains('EditText'));
    expect(source, contains('showSoftInput'));
    expect(source, isNot(contains('KeyboardView')));
  });

  test('JUJO Cloud panel is reduced proportionally by twenty-five percent', () {
    final source = File(
      'lib/screens/auth/cloud_auth_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ProportionalScale('));
    expect(source, contains('scale: 0.75'));
    expect(source, contains('baseWidth: 420'));
  });
}
