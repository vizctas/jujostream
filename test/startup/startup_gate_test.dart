import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/main.dart';
import 'package:jujostream/screens/cinematic_intro/cinematic_intro_screen.dart';
import 'package:jujostream/services/startup/startup_animation_preferences.dart';
import 'package:jujostream/services/startup/startup_animation_registry.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('off enters the launcher without rendering the cinematic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StartupAnimationPreferences.storageKey: StartupAnimationRegistry.offId,
      'focus_mode_enabled': false,
    });
    final preferences = await StartupAnimationPreferences.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: preferences,
        child: MaterialApp(
          home: StartupGate(
            launcherBuilder: (focusModeEnabled) =>
                Text(focusModeEnabled ? 'focus launcher' : 'pc launcher'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('pc launcher'), findsOneWidget);
    expect(find.byType(CinematicIntroScreen), findsNothing);
  });

  testWidgets('cinematic returns for each new root gate', (tester) async {
    SharedPreferences.setMockInitialValues({'focus_mode_enabled': false});
    final preferences = await StartupAnimationPreferences.load();
    final themeProvider = await ThemeProvider.load();

    Widget app() => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: preferences),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: MaterialApp(
        home: StartupGate(launcherBuilder: (_) => const Text('launcher')),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(CinematicIntroScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(CinematicIntroScreen), findsOneWidget);
  });
}
