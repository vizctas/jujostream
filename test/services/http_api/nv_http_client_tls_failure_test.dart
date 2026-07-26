import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/services/http_api/nv_http_client.dart';

class _HandshakeFailureClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw const HandshakeException('certificate verify failed');
  }
}

void main() {
  test(
    'classifies a pinned TLS handshake failure as changed server identity',
    () async {
      final client = NvHttpClient(
        httpsClientFactory: (_) => _HandshakeFailureClient(),
      );

      expect(
        await client.getAppList(
          '192.168.3.6',
          expectedServerCert: 'stale-server-fingerprint',
        ),
        isEmpty,
      );
      expect(client.lastAppListFailure, AppListFailure.serverIdentityRejected);
    },
  );
}
