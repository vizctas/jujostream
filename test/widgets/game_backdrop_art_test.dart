import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/widgets/game_backdrop_art.dart';
import 'package:jujostream/ui/motion_policy.dart';
import 'package:jujostream/ui/motion_scope.dart';
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
          heroBuilder: (_, _, hero) => Stack(
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

  testWidgets('poster is never promoted to a full-screen backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1920,
          height: 1080,
          child: GameBackdropArt(
            app: NvApp(
              appId: 1,
              appName: 'Hades',
              posterUrl: 'https://host/poster.jpg',
            ),
            enableKenBurns: true,
            validateHeroDimensions: false,
            heroBuilder: (_, _, background) => Stack(
              children: [
                background,
                const SizedBox(key: Key('background-motion-layer')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PosterImage), findsNothing);
    expect(find.byKey(const Key('game-backdrop-premium')), findsOneWidget);
    expect(find.byKey(const Key('background-motion-layer')), findsNothing);
    expect(find.byKey(const Key('game-backdrop-ken-burns')), findsNothing);
  });

  testWidgets('eligible landscape hero receives Ken Burns on premium only', (
    tester,
  ) async {
    Widget scoped(MotionTier tier) => MotionScope(
      policy: MotionPolicy(
        reduceMotion: false,
        performanceMode: false,
        resolvedTier: tier,
      ),
      child: MaterialApp(
        home: GameBackdropArt(
          app: NvApp(
            appId: 1,
            appName: 'Hades',
            heroImageUrl: 'https://host/hero.jpg',
          ),
          enableKenBurns: true,
          validateHeroDimensions: false,
        ),
      ),
    );

    await tester.pumpWidget(scoped(MotionTier.premium));
    expect(find.byKey(const Key('game-backdrop-hero')), findsOneWidget);
    expect(find.byKey(const Key('game-backdrop-ken-burns')), findsOneWidget);

    // TV tier (FireTV / Chromecast): the full-screen loop held the launcher
    // at 50 ms per frame while idle, so it must not run there.
    await tester.pumpWidget(scoped(MotionTier.standard));
    expect(find.byKey(const Key('game-backdrop-hero')), findsOneWidget);
    expect(find.byKey(const Key('game-backdrop-ken-burns')), findsNothing);
  });

  testWidgets('moving to an app without a hero drops the previous hero', (
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
    expect(find.byKey(const Key('game-backdrop-hero')), findsOneWidget);

    await tester.pumpWidget(
      _testApp(
        NvApp(
          appId: 2,
          appName: 'Dead as Disco',
          posterUrl: 'https://host/poster2.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('game-backdrop-hero')), findsNothing);
    expect(find.byKey(const Key('game-backdrop-premium')), findsOneWidget);
  });
}

Widget _testApp(NvApp app) {
  // The test view is 800x600; a plain SizedBox would be squeezed to that and
  // the 16:9 hero would be treated as a wide banner. OverflowBox lets the
  // backdrop lay out at a real TV viewport.
  return MaterialApp(
    home: OverflowBox(
      minWidth: 1920,
      maxWidth: 1920,
      minHeight: 1080,
      maxHeight: 1080,
      alignment: Alignment.topLeft,
      child: GameBackdropArt(app: app, validateHeroDimensions: false),
    ),
  );
}
