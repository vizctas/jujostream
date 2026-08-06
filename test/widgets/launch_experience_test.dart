import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/widgets/launch_experience.dart';
import 'package:jujostream/widgets/poster_image.dart';

void main() {
  testWidgets('launch experience uses cached contain poster composition', (
    tester,
  ) async {
    final app = NvApp(
      appId: 7,
      appName: 'TEKKEN 8',
      posterUrl: 'https://host/poster.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LaunchExperience(
          app: app,
          computerName: 'JUJO HOST',
          message: 'Waiting for game',
          accent: Colors.purple,
        ),
      ),
    );

    final poster = tester.widget<PosterImage>(
      find.byKey(const Key('game-backdrop-poster')),
    );
    expect(poster.fit, BoxFit.contain);
    expect(poster.cacheKey, app.artCacheKey('poster'));
    expect(find.text('Waiting for game'), findsOneWidget);
    expect(find.byType(PosterImage), findsNWidgets(2));
  });
}
