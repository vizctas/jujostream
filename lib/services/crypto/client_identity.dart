import 'dart:convert';
import 'dart:io' as io;

import 'package:shared_preferences/shared_preferences.dart';

import 'identity_generator.dart';

// Per-device client identity: uniqueId + RSA cert/key.
// Generated on first launch, persisted in SharedPreferences.
// Solves: "pairing one device pairs all" (was using shared hardcoded identity).

class ClientIdentity {
  ClientIdentity._();

  static const _kUid = '_ci_uid';
  static const _kCert = '_ci_cert';
  static const _kKey = '_ci_key';

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
    final stored = prefs.getString(_kUid);
    if (stored != null &&
        stored.isNotEmpty &&
        prefs.getString(_kCert) != null &&
        prefs.getString(_kKey) != null) {
      _uid = stored;
      _cert = prefs.getString(_kCert)!;
      _key = prefs.getString(_kKey)!;
      _ready = true;
      return;
    }
    // First launch: generate per-device identity
    final id = generateDeviceIdentity();
    await prefs.setString(_kUid, id.uniqueId);
    await prefs.setString(_kCert, id.certPem);
    await prefs.setString(_kKey, id.keyPem);
    _uid = id.uniqueId;
    _cert = id.certPem;
    _key = id.keyPem;
    _ready = true;
  }

  static io.SecurityContext buildSecurityContext({
    bool withTrustedRoots = false,
  }) {
    final ctx = io.SecurityContext(withTrustedRoots: withTrustedRoots);
    try {
      ctx.useCertificateChainBytes(certBytes);
      ctx.usePrivateKeyBytes(keyBytes);
    } catch (_) {}
    return ctx;
  }

  static io.HttpClient createHttpClient() {
    final ctx = buildSecurityContext();
    return io.HttpClient(context: ctx)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}
