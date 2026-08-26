import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/widgets/launch_experience.dart';

void main() {
  testWidgets('launch experience never promotes a portrait poster', (
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

    expect(find.byKey(const Key('game-backdrop-premium')), findsOneWidget);
    expect(find.text('Waiting for game'), findsOneWidget);
  });
}
