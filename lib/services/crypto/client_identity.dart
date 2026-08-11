import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../secure/flutter_secure_secret_store.dart';
import 'client_identity_migrator.dart';
import 'client_identity_store.dart';
import 'identity_generator.dart';

// Per-device client identity: uniqueId + RSA cert/key.
// Generated on first launch, persisted in SharedPreferences.
// Solves: "pairing one device pairs all" (was using shared hardcoded identity).

class ClientIdentity {
  ClientIdentity._();

  /// All three parts in one value, written in a single operation.
  ///
  /// The identity used to be three separate setString calls. A process kill
  /// between them (routine on Android/Fire TV) left the trio inconsistent, and
  /// the next init() treated that as "no identity" and generated a fresh one —
  /// silently invalidating every server this device had ever paired with. One
  /// key cannot be torn.
  // Fallback identity (legacy — used only before init() completes)
  static const _fallbackUid = '0123456789ABCDEF';

  static String _uid = _fallbackUid;
  static String _cert = '';
  static String _key = '';
  static bool _ready = false;

  static String get uniqueId => _uid;
  static String get certPem => _cert;
  static String get keyPem => _key;

  static List<int> get certBytes => utf8.encode(_cert);
  static List<int> get keyBytes => utf8.encode(_key);

  /// Must be called once at startup (before any networking).
  static Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final store = ClientIdentityStore(FlutterSecureSecretStore(), prefs);
    final migrated = await ClientIdentityMigrator(store).loadOrMigrate();
    if (migrated != null) {
      _adopt(migrated);
      _ready = true;
      return;
    }

    // First launch: generate per-device identity.
    final id = generateDeviceIdentity();
    _uid = id.uniqueId;
    _cert = id.certPem;
    _key = id.keyPem;
    final identity = StoredClientIdentity(
      uniqueId: _uid,
      certificatePem: _cert,
      privateKeyPem: _key,
    );
    ClientIdentityMigrator.validate(identity);
    await store.writeAndVerify(identity);
    await store.markMigrated(identity);
    _ready = true;
  }

  static void _adopt(StoredClientIdentity identity) {
    _uid = identity.uniqueId;
    _cert = identity.certificatePem;
    _key = identity.privateKeyPem;
  }

  static io.SecurityContext buildSecurityContext({
    bool withTrustedRoots = true,
    bool includeClientIdentity = true,
  }) {
    final ctx = io.SecurityContext(withTrustedRoots: withTrustedRoots);
    if (includeClientIdentity) {
      try {
        ctx.useCertificateChainBytes(certBytes);
        ctx.usePrivateKeyBytes(keyBytes);
      } catch (_) {}
    }
    return ctx;
  }

  static io.HttpClient createHttpClient({
    String? expectedServerCert,
    bool allowUntrustedForPairing = false,
    bool includeClientIdentity = true,
  }) {
    final hasPinnedCertificate = expectedServerCert?.trim().isNotEmpty ?? false;
    final ctx = buildSecurityContext(
      withTrustedRoots: !hasPinnedCertificate && !allowUntrustedForPairing,
      includeClientIdentity: includeClientIdentity,
    );
    final client = io.HttpClient(context: ctx);
    if (hasPinnedCertificate) {
      client.badCertificateCallback = (cert, host, port) {
        return certificateMatches(cert, expectedServerCert!);
      };
    } else if (allowUntrustedForPairing) {
      // Pairing authenticates the exchanged certificate through its PIN-based
      // challenge. Trust-all is deliberately scoped to that short-lived flow.
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }

  static bool certificateMatches(
    io.X509Certificate certificate,
    String expected,
  ) {
    return certificateMaterialMatches(
      actualPem: certificate.pem,
      actualSha1: certificate.sha1,
      expected: expected,
    );
  }

  static bool certificateMaterialMatches({
    required String actualPem,
    required Object actualSha1,
    required String expected,
  }) {
    final normalizedExpected = _normalizeCertificate(expected);
    if (normalizedExpected.isEmpty) return false;

    final normalizedPem = _normalizeCertificate(actualPem);
    if (normalizedExpected == normalizedPem) return true;

    final expectedFingerprint = _normalizeFingerprint(expected);
    final actualFingerprint = _normalizeFingerprint(actualSha1);
    if (expectedFingerprint.length == 40 &&
        expectedFingerprint == actualFingerprint) {
      return true;
    }

    if (expectedFingerprint.length == 64) {
      final actualDer = _certificateDerBytes(actualPem);
      if (actualDer != null) {
        final derDigest = sha256.convert(actualDer).toString();
        if (derDigest == expectedFingerprint) return true;
      }

      // Compatibility for cloud profiles published by older servers, which
      // hashed the certificate file's PEM bytes instead of canonical DER.
      for (final pemVariant in _pemHashVariants(actualPem)) {
        final digest = sha256.convert(utf8.encode(pemVariant)).toString();
        if (digest == expectedFingerprint) return true;
      }
    }
    return false;
  }

  static List<int>? _certificateDerBytes(String value) {
    final body = value
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s+'), '');
    if (body.isEmpty) return null;
    try {
      return base64.decode(body);
    } on FormatException {
      return null;
    }
  }

  static String _normalizeCertificate(String value) {
    var decoded = value.trim();
    final compact = decoded.replaceAll(RegExp(r'\s+'), '');
    if (compact.length.isEven &&
        compact.isNotEmpty &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
      try {
        decoded = utf8.decode([
          for (var i = 0; i < compact.length; i += 2)
            int.parse(compact.substring(i, i + 2), radix: 16),
        ]);
      } catch (_) {
        decoded = value;
      }
    }
    return decoded
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  static Iterable<String> _pemHashVariants(String value) sync* {
    final lf = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final withoutTrailing = lf.replaceFirst(RegExp(r'\n+$'), '');
    yield value;
    yield lf;
    yield withoutTrailing;
    yield '$withoutTrailing\n';
    yield withoutTrailing.replaceAll('\n', '\r\n');
    yield '${withoutTrailing.replaceAll('\n', '\r\n')}\r\n';
  }

  static String _normalizeFingerprint(Object value) {
    if (value is List<int>) {
      return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    }
    return value
        .toString()
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .toLowerCase();
  }
}
