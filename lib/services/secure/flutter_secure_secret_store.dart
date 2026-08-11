import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_secret_store.dart';

final class FlutterSecureSecretStore implements SecureSecretStore {
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'jujo_secure_v1',
              resetOnError: false,
              migrateOnAlgorithmChange: true,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
