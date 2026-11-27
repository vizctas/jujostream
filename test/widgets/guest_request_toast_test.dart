import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/services/sync/guest_link.dart';
import 'package:jujostream/widgets/guest_request_toast.dart';

void main() {
  testWidgets('shows who wants to join and fires accept / decline', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('es')],
        home: Scaffold(
          body: GuestRequestToast(
            request: const GuestRequest(
              id: 'r1',
              serverUrl: 'https://h:1',
              guestEmail: 'amigo@test.com',
              role: 'coop_pad',
            ),
            queued: 2,
            onAccept: () => calls.add('accept'),
            onDecline: () => calls.add('decline'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('amigo@test.com quiere unirse · Mando'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.tap(find.text('Rechazar'));
    expect(calls, ['accept', 'decline']);
  });
}
