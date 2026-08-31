import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('details preserves official artwork without a full-screen blur pass', () {
    final source = File(
      'lib/screens/app_view/app_details_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _buildBackdrop()');
    final end = source.indexOf('Widget _buildTopBar()', start);
    final backdrop = source.substring(start, end);

    expect(backdrop, contains('GameBackdropArt('));
    expect(backdrop, isNot(contains('BackdropFilter(')));
    expect(backdrop, isNot(contains('ImageFilter.blur')));
  });

  test('launcher actions share the accessible interaction primitive', () {
    final source = File(
      'lib/screens/app_view/app_view_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../../ui/accessible_action.dart';"));
    expect(source, contains('label: label'));
    expect(source, contains('height: 48'));
  });

  test('rearrange motion is bounded by the global motion policy', () {
    final source = File(
      'lib/screens/pc_view/pc_view_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('void _startRearrangeMode()');
    final end = source.indexOf('void _handleRearrangeCancel()', start);
    final rearrange = source.substring(start, end);

    expect(rearrange, contains('MotionScope.read(context)'));
    expect(rearrange, contains('allowContinuousEffects'));
  });
}
