import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/services/preferences/launcher_preferences.dart';
import 'package:jujostream/themes/kuiboo/kuiboo_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kuiboo pins title top-left above focused card without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.load();
    final launcherPreferences = LauncherPreferences();
    const appName =
        'An exceptionally long title that should wrap without escaping its area';
    final app = NvApp(
      appId: 7,
      appName: appName,
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
                builder: (context) => KuibooTheme().buildBody(
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

      final titleRect = tester.getRect(find.text(appName));
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('kuiboo-focused-card')),
      );
      expect(titleRect.left, lessThan(cardRect.left));
      expect(titleRect.top, lessThan(size.height / 3));
      expect(titleRect.bottom, lessThan(cardRect.top));
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
