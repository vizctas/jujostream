import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/widgets/game_backdrop_art.dart';
import 'package:jujostream/widgets/poster_image.dart';

void main() {
  testWidgets('hero renders full bleed without poster composition', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        NvApp(
          appId: 1,
          appName: 'Hades',
          heroImageUrl: 'https://host/hero.jpg',
          posterUrl: 'https://host/poster.jpg',
        ),
      ),
    );

    final hero = tester.widget<PosterImage>(
      find.byKey(const Key('game-backdrop-hero')),
    );
    expect(hero.fit, BoxFit.cover);
    expect(hero.memCacheWidth, 1920);
    expect(find.byKey(const Key('game-backdrop-poster')), findsNothing);
  });

  testWidgets('hero decoration runs only for an accepted hero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameBackdropArt(
          app: NvApp(
            appId: 1,
            appName: 'Hades',
            heroImageUrl: 'https://host/hero.jpg',
          ),
          validateHeroDimensions: false,
          heroBuilder: (_, hero) => Stack(
            children: [
              hero,
              const SizedBox(key: Key('hero-decoration')),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('hero-decoration')), findsOneWidget);
  });

  testWidgets(
    'poster fallback stays sharp and contained over blurred extension',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          NvApp(
            appId: 1,
            appName: 'Hades',
            posterUrl: 'https://host/poster.jpg',
          ),
        ),
      );

      final poster = tester.widget<PosterImage>(
        find.byKey(const Key('game-backdrop-poster')),
      );
      expect(poster.fit, BoxFit.contain);
      expect(poster.memCacheWidth, 720);
      expect(
        find.byKey(const Key('game-backdrop-poster-blur')),
        findsOneWidget,
      );
    },
  );
}

Widget _testApp(NvApp app) {
  return MaterialApp(
    home: SizedBox(
      width: 1920,
      height: 1080,
      child: GameBackdropArt(app: app, validateHeroDimensions: false),
    ),
  );
}
