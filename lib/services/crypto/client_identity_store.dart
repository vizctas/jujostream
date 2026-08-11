import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../secure/secure_secret_store.dart';

final class StoredClientIdentity {
  const StoredClientIdentity({
    required this.uniqueId,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String uniqueId;
  final String certificatePem;
  final String privateKeyPem;

  bool get isComplete =>
      uniqueId.isNotEmpty &&
      certificatePem.contains('BEGIN CERTIFICATE') &&
      privateKeyPem.contains('PRIVATE KEY');

  String encode() => jsonEncode({
    'schema': 1,
    'uid': uniqueId,
    'cert': certificatePem,
    'key': privateKeyPem,
  });

  static StoredClientIdentity? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final result = StoredClientIdentity(
        uniqueId: value['uid']?.toString() ?? '',
        certificatePem: value['cert']?.toString() ?? '',
        privateKeyPem: value['key']?.toString() ?? '',
      );
      return result.isComplete ? result : null;
    } catch (_) {
      return null;
    }
  }
}

final class ClientIdentityStore {
  ClientIdentityStore(this._secureStore, this._preferences);

  static const secureBundleKey = 'client_identity_bundle_v1';
  static const migrationMarkerKey = '_ci_secure_migration_v1';
  static const legacyBundleKey = '_ci_bundle';
  static const legacyUidKey = '_ci_uid';
  static const legacyCertKey = '_ci_cert';
  static const legacyPrivateKey = '_ci_key';

  final SecureSecretStore _secureStore;
  final SharedPreferences _preferences;

  Future<StoredClientIdentity?> readSecure() async =>
      StoredClientIdentity.decode(await _secureStore.read(secureBundleKey));

  StoredClientIdentity? readLegacy() {
    final bundled = StoredClientIdentity.decode(
      _preferences.getString(legacyBundleKey),
    );
    if (bundled != null) return bundled;
    final result = StoredClientIdentity(
      uniqueId: _preferences.getString(legacyUidKey) ?? '',
      certificatePem: _preferences.getString(legacyCertKey) ?? '',
      privateKeyPem: _preferences.getString(legacyPrivateKey) ?? '',
    );
    return result.isComplete ? result : null;
  }

  Future<void> writeAndVerify(StoredClientIdentity identity) async {
    if (!identity.isComplete) throw const FormatException('Invalid identity');
    final encoded = identity.encode();
    await _secureStore.write(secureBundleKey, encoded);
    if (await _secureStore.read(secureBundleKey) != encoded) {
      throw StateError('Secure identity verification failed');
    }
  }

  Future<void> markMigrated(StoredClientIdentity identity) async {
    await _preferences.setString(legacyUidKey, identity.uniqueId);
    await _preferences.setString(legacyCertKey, identity.certificatePem);
    await _preferences.setBool(migrationMarkerKey, true);
    await _preferences.remove(legacyPrivateKey);
    await _preferences.remove(legacyBundleKey);
  }
}
