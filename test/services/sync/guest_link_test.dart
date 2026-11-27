import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/services/sync/guest_link.dart';
import 'package:jujostream/services/sync/guest_request_poller.dart';

GuestRequest _req(String id, {String url = 'https://h:1', DateTime? expires}) =>
    GuestRequest(
      id: id,
      serverUrl: url,
      guestEmail: '$id@test.com',
      role: 'coop_pad',
      expiresAt:
          expires ?? DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

void main() {
  group('guest code parsing', () {
    test('normalises case, dashes and spaces', () {
      expect(normalizeGuestCode('abcde-fghjk'), 'ABCDE-FGHJK');
      expect(normalizeGuestCode(' abcde fghjk '), 'ABCDE-FGHJK');
      expect(normalizeGuestCode('ABCDEFGHJK'), 'ABCDE-FGHJK');
      expect(normalizeGuestCode('ABCDE'), isNull);
      expect(normalizeGuestCode('ABCDE-FGHJK-L'), isNull);
      expect(normalizeGuestCode(''), isNull);
    });

    test('reads the code from jujostream://invite links only', () {
      expect(
        guestCodeFromLink('jujostream://invite/abcde-fghjk'),
        'ABCDE-FGHJK',
      );
      expect(
        guestCodeFromLink('jujostream://invite/ABCDEFGHJK'),
        'ABCDE-FGHJK',
      );
      expect(guestCodeFromLink('jujostream://config/ABCDE-FGHJK'), isNull);
      expect(guestCodeFromLink('https://invite/ABCDE-FGHJK'), isNull);
      expect(guestCodeFromLink('jujostream://invite'), isNull);
      expect(guestCodeFromLink('jujostream://invite/short'), isNull);
    });

    test('share text follows the contract', () {
      final text = guestLinkShareText(
        serverName: 'Host Rig',
        code: 'ABCDE-FGHJK',
        expiresAt: DateTime(2026, 11, 27, 21, 5),
      );
      expect(
        text,
        'Únete a mi partida en Host Rig con Jujo.Stream\n'
        'jujostream://invite/ABCDE-FGHJK\n'
        'Código: ABCDE-FGHJK (válido hasta 21:05)',
      );
    });
  });

  group('GuestRedeemResult.fromRpc', () {
    GuestRedeemOutcome outcome(Map<String, dynamic> json) =>
        GuestRedeemResult.fromRpc(json).outcome;

    test('maps statuses and errors', () {
      final active = GuestRedeemResult.fromRpc({
        'success': true,
        'status': 'active',
        'server_url': 'https://h:1',
        'server_name': '',
      });
      expect(active.outcome, GuestRedeemOutcome.active);
      expect(active.serverName, 'https://h:1');

      final requested = GuestRedeemResult.fromRpc({
        'success': true,
        'status': 'requested',
        'id': 'x',
      });
      expect(requested.outcome, GuestRedeemOutcome.requested);
      expect(requested.inviteId, 'x');

      expect(
        outcome({'success': true, 'status': '???'}),
        GuestRedeemOutcome.error,
      );
      expect(
        outcome({'success': false, 'error': 'verify_email'}),
        GuestRedeemOutcome.verifyEmail,
      );
      expect(
        outcome({'success': false, 'error': 'invalid_or_expired'}),
        GuestRedeemOutcome.invalidOrExpired,
      );
      expect(
        outcome({'success': false, 'error': 'already_has_access'}),
        GuestRedeemOutcome.alreadyHasAccess,
      );
    });
  });

  group('guest-managed detection', () {
    test('own server, co-owner with guests/admin, co-owner without', () {
      expect(ComputerDetails(isCloudOwner: true).managesGuests, isTrue);
      expect(ComputerDetails(permissions: ['guests']).managesGuests, isTrue);
      expect(
        ComputerDetails(permissions: ['launch', 'admin']).managesGuests,
        isTrue,
      );
      expect(ComputerDetails(permissions: ['launch']).managesGuests, isFalse);
      expect(ComputerDetails().managesGuests, isFalse);
      expect(ComputerDetails(coopRole: 'coop_pad').managesGuests, isFalse);
    });

    test('json round-trips permissions, owner flag, auto-accept and url', () {
      final restored = ComputerDetails.fromJson(
        ComputerDetails(
          uuid: 'u',
          isCloudOwner: true,
          permissions: ['launch', 'guests'],
          autoAcceptGuests: true,
          cloudServerUrl: 'https://h:1',
        ).toJson(),
      );
      expect(restored.isCloudOwner, isTrue);
      expect(restored.permissions, ['launch', 'guests']);
      expect(restored.autoAcceptGuests, isTrue);
      expect(restored.cloudServerUrl, 'https://h:1');

      final legacy = ComputerDetails.fromJson({'uuid': 'old'});
      expect(legacy.managesGuests, isFalse);
      expect(legacy.autoAcceptGuests, isFalse);
      expect(legacy.toJson().containsKey('permissions'), isFalse);
    });
  });

  group('GuestRequestPoller', () {
    test(
      'keeps only this server, drops expired and answered-elsewhere',
      () async {
        var rows = [
          _req('a'),
          _req('b', url: 'https://other:1'),
          _req(
            'c',
            expires: DateTime.now().toUtc().subtract(
              const Duration(seconds: 1),
            ),
          ),
          _req('d', url: 'HTTPS://H:1/'),
        ];
        var changes = 0;
        final poller = GuestRequestPoller(
          serverUrl: 'https://h:1',
          fetch: () async => rows,
          respond: (_, _) async => true,
          onChanged: () => changes++,
        )..start();

        await poller.poll();
        expect(poller.queue.map((r) => r.id), ['a', 'd']);
        expect(changes, 1);

        await poller.poll();
        expect(changes, 1);

        rows = [_req('d')];
        await poller.poll();
        expect(poller.queue.map((r) => r.id), ['d']);
        poller.stop();
      },
    );

    test(
      'answer calls respond and removes the request only on success',
      () async {
        final calls = <(String, bool)>[];
        var ok = true;
        final poller = GuestRequestPoller(
          serverUrl: 'https://h:1',
          fetch: () async => [_req('a'), _req('b')],
          respond: (id, approve) async {
            calls.add((id, approve));
            return ok;
          },
          onChanged: () {},
        )..start();
        await poller.poll();

        ok = false;
        expect(await poller.answer(poller.queue.first, approve: true), isFalse);
        expect(poller.queue, hasLength(2));

        ok = true;
        expect(await poller.answer(poller.queue.first, approve: false), isTrue);
        expect(poller.queue.map((r) => r.id), ['b']);
        expect(calls, [('a', true), ('a', false)]);
        poller.stop();
      },
    );

    test('does not poll while inactive', () async {
      var fetched = 0;
      final poller = GuestRequestPoller(
        serverUrl: 'https://h:1',
        fetch: () async {
          fetched++;
          return [];
        },
        respond: (_, _) async => true,
        onChanged: () {},
        isActive: () => false,
      );
      await poller.poll();
      expect(fetched, 0);
    });
  });
}
