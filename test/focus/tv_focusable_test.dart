import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/services/tv/tv_focus_helpers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TvFocusable exposes an accessible button contract', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: TvFocusable(
              semanticLabel: 'Play game',
              selected: true,
              onSelect: () {},
              child: const SizedBox(width: 80, height: 48),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Play game'), findsOneWidget);
    final semantics = tester.getSemantics(find.bySemanticsLabel('Play game'));
    final data = semantics.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  });
}
