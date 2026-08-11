import 'dart:io';

import 'client_identity_store.dart';

final class ClientIdentityMigrator {
  const ClientIdentityMigrator(this._store);

  final ClientIdentityStore _store;

  Future<StoredClientIdentity?> loadOrMigrate() async {
    final secure = await _store.readSecure();
    if (secure != null) return secure;

    final legacy = _store.readLegacy();
    if (legacy == null) return null;
    validate(legacy);
    await _store.writeAndVerify(legacy);
    final verified = await _store.readSecure();
    if (verified == null || verified.encode() != legacy.encode()) {
      throw StateError('Secure identity migration did not verify');
    }
    await _store.markMigrated(verified);
    return verified;
  }

  static void validate(StoredClientIdentity identity) {
    if (!identity.isComplete) throw const FormatException('Invalid identity');
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(identity.certificatePem.codeUnits);
    context.usePrivateKeyBytes(identity.privateKeyPem.codeUnits);
  }
}
