import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/services/pairing/pairing_service.dart';

void main() {
  group('Pairing endpoint selection', () {
    test('builds address candidates with cached port and 47989 fallback', () {
      final computer = ComputerDetails(
        activeAddress: 'julytower.local',
        manualAddress: '192.168.1.43',
        localAddress: '192.168.1.43',
        remoteAddress: '203.0.113.10',
        externalPort: 63440,
      );

      expect(PairingService.pairingBaseUrlCandidatesForTest(computer), [
        'http://julytower.local:63440',
        'http://julytower.local:47989',
        'http://192.168.1.43:63440',
        'http://192.168.1.43:47989',
        'http://203.0.113.10:63440',
        'http://203.0.113.10:47989',
      ]);
    });

    test('redacts sensitive pairing data from URLs and client errors', () {
      const raw =
          'ClientException: failed, uri=http://julytower.local:47989/pair'
          '?uniqueid=real-device-id'
          '&phrase=getservercert'
          '&salt=abc123'
          '&clientcert=abcdef'
          '&serverchallengeresp=feedface';

      final sanitized = PairingService.sanitizePairingLogMessage(raw);

      expect(sanitized, contains('phrase=getservercert'));
      expect(sanitized, contains('uniqueid=redacted'));
      expect(sanitized, contains('salt=redacted'));
      expect(sanitized, contains('clientcert=redacted'));
      expect(sanitized, contains('serverchallengeresp=redacted'));
      expect(sanitized, isNot(contains('real-device-id')));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('abcdef')));
      expect(sanitized, isNot(contains('feedface')));
    });

    test('builds HTTPS verification URL from selected HTTP endpoint host', () {
      final computer = ComputerDetails(
        activeAddress: 'julytower.local',
        localAddress: '192.168.1.43',
        httpsPort: 47984,
      );

      expect(
        PairingService.pairingHttpsBaseUrlForTest(
          computer,
          'http://192.168.1.43:47989',
        ),
        'https://192.168.1.43:47984',
      );
    });

    test('classifies remote hostnames resolving to loopback as unsafe', () {
      expect(
        PairingService.isUnsafeLoopbackPairingResolutionForTest(
          'julytower.local',
          [InternetAddress('127.0.0.1')],
        ),
        true,
      );
      expect(
        PairingService.isUnsafeLoopbackPairingResolutionForTest('localhost', [
          InternetAddress('127.0.0.1'),
        ]),
        false,
      );
      expect(
        PairingService.isUnsafeLoopbackPairingResolutionForTest(
          '192.168.1.43',
          [InternetAddress('192.168.1.43')],
        ),
        false,
      );
    });

    test('expands hostname candidates with usable mDNS addresses', () {
      final computer = ComputerDetails(
        activeAddress: 'julytower.local',
        externalPort: 47989,
      );

      expect(
        PairingService.pairingBaseUrlCandidatesWithResolvedAddressesForTest(
          computer,
          {
            'julytower.local': [
              InternetAddress('127.0.0.1'),
              InternetAddress('192.168.1.43'),
              InternetAddress('fe80::1234'),
            ],
          },
        ),
        ['http://192.168.1.43:47989'],
      );
    });
  });
}
