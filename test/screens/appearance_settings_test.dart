import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jujostream/models/theme_config.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/screens/settings/appearance_settings.dart';
import 'package:jujostream/services/preferences/launcher_preferences.dart';
import 'package:jujostream/themes/launcher_theme.dart';

void main() {
  late ThemeProvider theme;
  late LauncherPreferences preferences;

  Future<void> mount(WidgetTester tester, {String color = 'oled'}) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': color,
      'launcher_theme': 'classic',
      'bigScreen_lp_cardWidth': 211.0,
    });
    theme = await ThemeProvider.load();
    preferences = LauncherPreferences();
    await preferences.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: AppearanceSettings())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.descendant(
    of: find.byKey(ValueKey('appearance-$name')),
    matching: find.byType(ListTile),
  );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'appearance has one focus stop per row and restores it on cancel',
    (tester) async {
      await mount(tester);
      final layoutFocus = tester.widget<ListTile>(row('layout')).focusNode!;
      final colorFocus = tester.widget<ListTile>(row('color')).focusNode!;
      layoutFocus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(colorFocus.hasFocus, isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('appearance-option-AppThemeId.oled')),
            )
            .selected,
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.gameButtonB);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(theme.themeId, AppThemeId.oled);
      expect(colorFocus.hasFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(layoutFocus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'gamepad selects Big Screen without Steam credentials and loads its profile',
    (tester) async {
      await mount(tester);
      final focus = tester.widget<ListTile>(row('layout')).focusNode!;
      focus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.gameButtonA);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.gameButtonA);
      expect(theme.launcherThemeId, LauncherThemeId.bigScreen);
      expect(preferences.cardWidth, 211.0);
      expect(
        (await SharedPreferences.getInstance()).getString('launcher_theme'),
        'bigScreen',
      );
      expect(find.byType(SimpleDialog), findsNothing);
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'color selection starts at current option and persists only on confirmation',
    (tester) async {
      await mount(tester);
      await tester.tap(row('color'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(theme.themeId, AppThemeId.oled);
      await press(tester, LogicalKeyboardKey.enter);
      expect(theme.themeId, AppThemeId.cyberpunk);
      expect(
        (await SharedPreferences.getInstance()).getString('app_theme'),
        'cyberpunk',
      );
    },
  );

  testWidgets(
    'last color remains visible on small screens and Escape cancels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, color: 'light');
      await tester.tap(row('color'));
      await tester.pumpAndSettle();
      final selected = find.byKey(
        const ValueKey('appearance-option-AppThemeId.light'),
      );
      expect(selected.hitTestable(), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(theme.themeId, AppThemeId.light);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
