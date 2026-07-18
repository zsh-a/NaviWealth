import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_key_store.dart';

/// [SecureKeyStore] backed by [FlutterSecureStorage].
///
/// Platform behavior to keep in mind:
/// - iOS: Keychain item is bound to the device by default. Use
///   [IOSOptions.accessibility] = `first_unlock` so iCloud-restored
///   backups can re-derive a fresh DB key on the new device, but the
///   secret never leaves the device.
/// - Android: uses the plugin's RSA-OAEP + AES-GCM default backed by Android
///   Keystore. Crash-safe cipher migration is enabled because this store owns
///   the database master key.
class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
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

  @override
  Future<bool> contains(String key) => _storage.containsKey(key: key);
}
