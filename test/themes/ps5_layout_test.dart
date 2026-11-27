import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/services/preferences/launcher_preferences.dart';
import 'package:jujostream/themes/ps5/ps5_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PS5 details fill the right column below the strip, no overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();
    final launcherPreferences = LauncherPreferences();
    final description = List.filled(40, 'Long description line.').join(' ');
    const appName =
        'An exceptionally long title that should wrap without escaping its area';
    final app = NvApp(
      appId: 7,
      appName: appName,
      description: description,
      metadataGenres: const [
        'Strategy and simulation adventures',
        'Exploration with friends',
      ],
    );

    Future<void> render(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<LauncherPreferences>.value(
              value: launcherPreferences,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => Ps5Theme().buildBody(
                  context: context,
                  apps: [app],
                  allApps: [app],
                  selectedIndex: 0,
                  onAppSelected: (_) {},
                  onAppDetails: (_) {},
                  onIndexChanged: (_) {},
                  activeSessionAppId: null,
                  isGridView: false,
                  favoriteIds: const {},
                  onToggleFavorite: (_) {},
                  activeFilterLabel: 'A particularly long active filter label',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(find.text(appName).last);
      final descRect = tester.getRect(
        find.textContaining('Long description line.'),
      );
      // Description owns the right column and starts above the title block.
      expect(descRect.left, greaterThan(titleRect.right));
      expect(descRect.top, lessThan(titleRect.top));
      expect(descRect.left, greaterThan(size.width / 2));
      expect(tester.takeException(), isNull);
    }

    await render(const Size(1280, 720));
    await render(const Size(800, 420));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
