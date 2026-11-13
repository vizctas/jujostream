import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/screens/app_view/watchdog_dialogs.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  Widget wrapApp(Widget home) {
    return MaterialApp(
      home: Scaffold(body: home),
    );
  }

  const sampleStatus = WatchdogStatus(
    supported: true,
    enabled: true,
    sensitivity: 50,
    ready: false,
    rawReady: false,
    cpuPressure: false,
    ramPressure: true,
    cpuUsagePercent: 41,
    maxCpuPercent: 67.5,
    memoryLoadPercent: 89,
    maxMemoryLoadPercent: 83,
    totalRamBytes: 16 * 1024 * 1024 * 1024,
    availRamBytes: 2 * 1024 * 1024 * 1024,
    minAvailRamBytes: 3758096384,
    candidates: [
      WatchdogCandidate(
        id: 'chrome.exe',
        name: 'Google Chrome',
        category: 'browser',
        recommended: true,
        processCount: 7,
        ramBytes: 1500 * 1024 * 1024,
        cpuPercent: 9.2,
      ),
      WatchdogCandidate(
        id: 'custom.exe',
        name: 'Custom Heavy App',
        category: 'other',
        recommended: false,
        processCount: 1,
        ramBytes: 400 * 1024 * 1024,
        cpuPercent: 1.5,
      ),
    ],
  );

  testWidgets(
    'WatchdogPreLaunchDialog pre-selects recommended apps and toggles selection',
    (tester) async {
      WatchdogDialogDecision? result;
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showWatchdogPreLaunchDialog(
                  context: ctx,
                  status: sampleStatus,
                  surface: const Color(0xFF141824),
                  accent: const Color(0xFF00D4AA),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Google Chrome'), findsOneWidget);
      expect(find.text('Custom Heavy App'), findsOneWidget);
      expect(find.text('Close & Launch (1)'), findsOneWidget);

      await tester.tap(find.text('Custom Heavy App'));
      await tester.pumpAndSettle();
      expect(find.text('Close & Launch (2)'), findsOneWidget);

      await tester.tap(find.text('Close & Launch (2)'));
      await tester.pumpAndSettle();

      expect(result?.outcome, WatchdogDialogOutcome.closeAndLaunch);
      expect(result?.selectedIds, containsAll(['chrome.exe', 'custom.exe']));
    },
  );

  testWidgets('WatchdogPreLaunchDialog cancels on gamepad B button', (
    tester,
  ) async {
    WatchdogDialogDecision? result;
    await tester.pumpWidget(
      wrapApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showWatchdogPreLaunchDialog(
                context: ctx,
                status: sampleStatus,
                surface: const Color(0xFF141824),
                accent: const Color(0xFF00D4AA),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();

    expect(result?.outcome, WatchdogDialogOutcome.cancel);
  });

  testWidgets(
    'showGameClosedOnHostDialog confirms new session and cancels cleanly',
    (tester) async {
      bool? confirmed;
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                confirmed = await showGameClosedOnHostDialog(
                  context: ctx,
                  surface: const Color(0xFF141824),
                  accent: const Color(0xFF00D4AA),
                );
              },
              child: const Text('Prompt'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prompt'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The game was closed and the stream cannot resume. Do you want to start a new session?',
        ),
        findsOneWidget,
      );
      expect(
        const AppLocalizations(Locale('es')).sessionClosedOnHostBody,
        'El juego fue cerrado y no puede iniciar el stream. ¿Quieres iniciar una sesión nueva?',
      );

      await tester.tap(find.text('Start new session'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);

      await tester.tap(find.text('Prompt'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    },
  );

  testWidgets('WatchdogPreLaunchDialog handles empty closable candidate list', (
    tester,
  ) async {
    const noCandidateStatus = WatchdogStatus(
      supported: true,
      enabled: true,
      sensitivity: 50,
      ready: false,
      rawReady: false,
      cpuPressure: true,
      ramPressure: false,
      cpuUsagePercent: 92,
      maxCpuPercent: 67.5,
      memoryLoadPercent: 60,
      maxMemoryLoadPercent: 83,
      totalRamBytes: 16 * 1024 * 1024 * 1024,
      availRamBytes: 6 * 1024 * 1024 * 1024,
      minAvailRamBytes: 3758096384,
      candidates: [],
    );

    WatchdogDialogDecision? result;
    await tester.pumpWidget(
      wrapApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showWatchdogPreLaunchDialog(
                context: ctx,
                status: noCandidateStatus,
                surface: const Color(0xFF141824),
                accent: const Color(0xFF00D4AA),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('No safe heavy background apps were found to close.'),
      findsOneWidget,
    );
    expect(find.textContaining('Close & Launch'), findsNothing);

    await tester.tap(find.text('Launch Anyway'));
    await tester.pumpAndSettle();
    expect(result?.outcome, WatchdogDialogOutcome.launchAnyway);
  });
}

