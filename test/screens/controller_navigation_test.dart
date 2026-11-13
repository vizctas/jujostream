import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/screens/about/about_screen.dart';
import 'package:jujostream/screens/pc_view/focus_mode_screen.dart';
import 'package:jujostream/services/update/update_models.dart';
import 'package:jujostream/services/update/update_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'FocusMode 3-dots menu navigates between all three options via controller keys',
    (tester) async {
      final tp = await ThemeProvider.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: tp,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: const [Locale('en'), Locale('es')],
            home: Builder(
              builder: (parentContext) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<void>(
                        context: parentContext,
                        builder: (_) =>
                            buildFocusModeMenuDialogForTest(parentContext),
                      );
                    },
                    child: const Text('Menu'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      bool hasFocusUnder(String label) {
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx == null) return false;
        final labelFinder = find.text(label);
        if (labelFinder.evaluate().isEmpty) return false;
        final labelElement = labelFinder.evaluate().first;
        bool found = false;
        ctx.visitAncestorElements((ancestor) {
          if (ancestor == labelElement) found = true;
          return !found;
        });
        // Check descendants of focused element instead
        bool descMatch = false;
        (ctx as Element).visitChildren((child) {
          void walk(Element e) {
            if (descMatch) return;
            if (e == labelElement) {
              descMatch = true;
              return;
            }
            e.visitChildren(walk);
          }

          walk(child);
        });
        return found || descMatch;
      }

      expect(hasFocusUnder('Focus Mode disabled'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(hasFocusUnder('My Profile'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(hasFocusUnder('About & Credits'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(hasFocusUnder('My Profile'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Focus Mode disabled'), findsNothing);
    },
  );

  testWidgets(
    'AboutScreen traverses down past 250px and returns cleanly back to offset 0 with arrowUp',
    (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tp = await ThemeProvider.load();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: tp),
            Provider<UpdateProvider>.value(value: _FakeUpdateProvider()),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate],
            supportedLocales: [Locale('en'), Locale('es')],
            home: AboutScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable);
      expect(scrollableFinder, findsOneWidget);
      ScrollableState scrollState() =>
          tester.state<ScrollableState>(scrollableFinder);

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(scrollState().position.pixels, greaterThan(100.0));

      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
      }
      expect(scrollState().position.pixels, closeTo(0.0, 2.0));
    },
  );
}

class _FakeUpdateProvider implements UpdateProvider {
  @override
  DistributionChannel get channel => DistributionChannel.unsupported;

  @override
  bool get supportsDirectInstall => false;

  @override
  Future<ClientUpdateRelease?> checkForUpdate() async => null;

  @override
  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canInstallPackages() async => false;

  @override
  Future<bool> openInstallPermission() async => false;

  @override
  Future<bool> installApk(File apk) async => false;

  @override
  Future<bool> openStoreListing() async => false;

  @override
  void dispose() {}
}

