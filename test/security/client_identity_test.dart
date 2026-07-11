import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/crypto/client_identity.dart';
import 'package:jujostream/services/crypto/identity_generator.dart';

void main() {
  const pem = '''-----BEGIN CERTIFICATE-----
YWJjMTIz
-----END CERTIFICATE-----''';

  test('accepts exact PEM and pairing hex material', () {
    final hexPem = utf8
        .encode(pem)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    expect(
      ClientIdentity.certificateMaterialMatches(
        actualPem: pem,
        actualSha1: '00:11',
        expected: pem,
      ),
      isTrue,
    );
    expect(
      ClientIdentity.certificateMaterialMatches(
        actualPem: pem,
        actualSha1: '00:11',
        expected: hexPem,
      ),
      isTrue,
    );
  });

  test('accepts exact SHA-1 and rejects unknown material', () {
    const sha1 = '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33';

    expect(
      ClientIdentity.certificateMaterialMatches(
        actualPem: pem,
        actualSha1: sha1,
        expected: sha1,
      ),
      isTrue,
    );
    expect(
      ClientIdentity.certificateMaterialMatches(
        actualPem: pem,
        actualSha1: sha1,
        expected: 'different-certificate',
      ),
      isFalse,
    );
  });

  test('accepts the server cloud-agent SHA-256 PEM fingerprint', () {
    final fingerprint = sha256.convert(utf8.encode(pem)).toString();

    expect(
      ClientIdentity.certificateMaterialMatches(
        actualPem: pem,
        actualSha1: const <int>[],
        expected: fingerprint,
      ),
      isTrue,
    );
  });

  test('pins a self-signed HTTPS server using the cloud fingerprint', () async {
    final identity = generateDeviceIdentity();
    final serverContext = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certPem))
      ..usePrivateKeyBytes(utf8.encode(identity.keyPem));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    final subscription = server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"status":true}');
      await request.response.close();
    });

    try {
      final fingerprint = sha256
          .convert(utf8.encode(identity.certPem))
          .toString();
      String? observedPem;
      final probeClient = HttpClient()
        ..badCertificateCallback = (certificate, host, port) {
          observedPem = certificate.pem;
          return true;
        };
      final probeRequest = await probeClient.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/probe'),
      );
      await (await probeRequest.close()).drain<void>();
      probeClient.close(force: true);
      expect(observedPem, isNotNull);
      final client = ClientIdentity.createHttpClient(
        expectedServerCert: fingerprint,
        includeClientIdentity: false,
      );
      final request = await client.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/api/pair/cloud'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      client.close(force: true);

      final rejectedClient = ClientIdentity.createHttpClient(
        expectedServerCert: List.filled(64, '0').join(),
        includeClientIdentity: false,
      );
      await expectLater(
        rejectedClient
            .getUrl(Uri.parse('https://127.0.0.1:${server.port}/'))
            .then((request) => request.close()),
        throwsA(isA<HandshakeException>()),
      );
      rejectedClient.close(force: true);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
