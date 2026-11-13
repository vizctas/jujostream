import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/models/gaming_news_item.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/widgets/news_carousel/gaming_news_reader_dialog.dart';
import 'package:jujostream/widgets/news_carousel/stacked_news_sections.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<GamingNewsItem> _sampleItems() => const [
  GamingNewsItem(
    id: 'n1',
    type: GamingNewsType.news,
    title: 'Headline One',
    subtitle: 'PC GAMER — Story summary',
    dateLabel: 'NOW',
    sourceUrl: 'https://example.com/news-1',
  ),
  GamingNewsItem(
    id: 'n2',
    type: GamingNewsType.news,
    title: 'Headline Two',
    subtitle: 'EUROGAMER — Story two',
    dateLabel: 'TODAY',
    sourceUrl: 'https://example.com/news-2',
  ),
  GamingNewsItem(
    id: 'u1',
    type: GamingNewsType.update,
    title: 'Patch 2.0 Live',
    subtitle: 'Major expansion',
    dateLabel: 'UPDATE',
    relatedAppId: 1091500,
    sourceUrl: 'https://example.com/update-1',
  ),
  GamingNewsItem(
    id: 'r1',
    type: GamingNewsType.recommended,
    title: 'Cyberpunk 2077 -60%',
    subtitle: 'STEAM • DEAL',
    dateLabel: 'DEAL',
    sourceUrl: 'https://example.com/deal-1',
  ),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'renders localized stacked sections with distinct per-section card widths',
    (tester) async {
      final tp = await ThemeProvider.load();
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: tp,
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: const [Locale('en'), Locale('es')],
            home: Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: const Locale('es'),
                delegates: const [AppLocalizations.delegate],
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: StackedNewsSections(
                      allApps: const [],
                      apps: const [],
                      hasFocus: true,
                      onExitUp: () {},
                      initialItems: _sampleItems(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NOTICIAS GAMING'), findsOneWidget);
      expect(find.text('ACTUALIZACIONES Y LANZAMIENTOS'), findsOneWidget);
      expect(find.text('OFERTAS Y RECOMENDADOS'), findsOneWidget);
      // Empty types are omitted rather than showing empty shelves.
      expect(find.text('EVENTOS Y REGALOS'), findsNothing);
      expect(find.text('NOTAS DE PARCHE'), findsNothing);

      final n1Box = tester.getSize(
        find.ancestor(
          of: find.text('Headline One'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );
      final n2Box = tester.getSize(
        find.ancestor(
          of: find.text('Headline Two'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );
      final r1Box = tester.getSize(
        find.ancestor(
          of: find.text('Cyberpunk 2077 -60%'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );

      // Same section cards stay symmetrical; different sections vary dimensions.
      expect(n1Box, n2Box);
      expect(n1Box.width, greaterThan(r1Box.width));
    },
  );

  testWidgets('gamepad navigation traverses sections and exits up cleanly', (
    tester,
  ) async {
    final tp = await ThemeProvider.load();
    final key = GlobalKey<StackedNewsSectionsState>();
    var exited = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: tp,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('es')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: StackedNewsSections(
                key: key,
                allApps: const [],
                apps: const [],
                hasFocus: true,
                onExitUp: () => exited++,
                initialItems: _sampleItems(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = key.currentState!;
    expect(state.handleKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
    expect(state.handleKeyEvent(LogicalKeyboardKey.arrowDown), isTrue);
    expect(exited, 0);

    // Return up to section 0, then up out of sections.
    expect(state.handleKeyEvent(LogicalKeyboardKey.arrowUp), isTrue);
    expect(exited, 0);
    expect(state.handleKeyEvent(LogicalKeyboardKey.arrowUp), isTrue);
    expect(exited, 1);
  });

  testWidgets(
    'GamingNewsReaderDialog shows localized source action and linked Play action',
    (tester) async {
      final tp = await ThemeProvider.load();
      NvApp? launched;
      final app = NvApp(
        appId: 42,
        appName: 'Cyberpunk 2077',
        posterUrl: 'https://shared.fastly.steamstatic.com/steam/apps/1091500/library_600x900_2x.jpg',
      );
      final item = _sampleItems()[2];

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: tp,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: const [Locale('en'), Locale('es')],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      GamingNewsReaderDialog.show(
                        context,
                        item: item,
                        allApps: [app],
                        onPlayApp: (a) => launched = a,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Patch 2.0 Live'), findsOneWidget);
      expect(find.text('Open Source'), findsOneWidget);
      expect(find.textContaining('GPL-3.0'), findsNothing);
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(launched?.appName, 'Cyberpunk 2077');
    },
  );
}

