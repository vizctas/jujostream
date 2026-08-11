import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/crypto/client_identity_store.dart';
import 'package:jujostream/services/secure/secure_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _MemorySecretStore implements SecureSecretStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('secure store unavailable');
    values[key] = value;
  }
}

void main() {
  const identity = StoredClientIdentity(
    uniqueId: '0123456789ABCDEF',
    certificatePem:
        '-----BEGIN CERTIFICATE-----\nCERT\n-----END CERTIFICATE-----',
    privateKeyPem:
        '-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('secure write verifies exact encoded identity', () async {
    final secrets = _MemorySecretStore();
    final store = ClientIdentityStore(
      secrets,
      await SharedPreferences.getInstance(),
    );

    await store.writeAndVerify(identity);

    expect(await store.readSecure(), isNotNull);
    expect((await store.readSecure())!.encode(), identity.encode());
  });

  test('failed secure write preserves complete legacy identity', () async {
    SharedPreferences.setMockInitialValues({
      ClientIdentityStore.legacyBundleKey: identity.encode(),
    });
    final secrets = _MemorySecretStore()..failWrites = true;
    final prefs = await SharedPreferences.getInstance();
    final store = ClientIdentityStore(secrets, prefs);

    await expectLater(store.writeAndVerify(identity), throwsStateError);

    expect(store.readLegacy()!.encode(), identity.encode());
    expect(prefs.getString(ClientIdentityStore.legacyBundleKey), isNotNull);
  });

  test('migration marker removes plaintext private material only', () async {
    SharedPreferences.setMockInitialValues({
      ClientIdentityStore.legacyBundleKey: identity.encode(),
      ClientIdentityStore.legacyPrivateKey: identity.privateKeyPem,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = ClientIdentityStore(_MemorySecretStore(), prefs);

    await store.markMigrated(identity);

    expect(prefs.getBool(ClientIdentityStore.migrationMarkerKey), isTrue);
    expect(prefs.getString(ClientIdentityStore.legacyPrivateKey), isNull);
    expect(prefs.getString(ClientIdentityStore.legacyBundleKey), isNull);
    expect(
      prefs.getString(ClientIdentityStore.legacyUidKey),
      identity.uniqueId,
    );
    expect(
      prefs.getString(ClientIdentityStore.legacyCertKey),
      identity.certificatePem,
    );
  });

  test('decoder rejects partial and malformed bundles', () {
    expect(StoredClientIdentity.decode('{broken'), isNull);
    expect(StoredClientIdentity.decode(jsonEncode({'uid': 'only'})), isNull);
  });
}
