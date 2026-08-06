import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/services/http_api/nv_http_client.dart';

/// Stands in for the real server's self-signed certificate: any HTTPS request
/// made without a pinned cert fails verification, every time.
class _SelfSignedRejectingClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    throw const HandshakeException(
      'CERTIFICATE_VERIFY_FAILED: self signed certificate',
    );
  }
}

class _PlainHttpClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(
      Stream.value(
        '<root><hostname>desktop</hostname><uniqueid>u-1</uniqueid>'
                '<PairStatus>0</PairStatus></root>'
            .codeUnits,
      ),
      200,
    );
  }
}

void main() {
  test('skips the doomed HTTPS attempt when no certificate is pinned', () async {
    final https = _SelfSignedRejectingClient();
    final plain = _PlainHttpClient();
    final client = NvHttpClient(
      httpClient: plain,
      httpsClientFactory: (_) => https,
    );

    final result = await client.fetchServerInfo('192.168.3.30');

    expect(https.calls, 0, reason: 'unpaired HTTPS can never succeed');
    expect(plain.calls, 1);
    expect(result.info?.name, 'desktop');
    expect(result.certRejected, isFalse);
  });

  test('still probes HTTPS when a certificate is pinned', () async {
    final https = _SelfSignedRejectingClient();
    final plain = _PlainHttpClient();
    final client = NvHttpClient(
      httpClient: plain,
      httpsClientFactory: (_) => https,
    );

    final result = await client.fetchServerInfo(
      '192.168.3.30',
      expectedServerCert: 'pinned-fingerprint',
    );

    expect(https.calls, 1);
    // A pinned cert that no longer matches is the signal the pairing is gone.
    expect(result.certRejected, isTrue);
  });
}
