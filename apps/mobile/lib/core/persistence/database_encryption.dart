import 'dart:math';

import '../security/secure_key_store.dart';

const String databaseEncryptionKeyStorageKey =
    'naviwealth.database.master_key.v1';
const int databaseEncryptionKeyBytes = 32;

enum DatabaseEncryptionFailureCode {
  keyMissing,
  invalidKey,
  cipherUnavailable,
  unlockFailed,
  migrationFailed,
}

final class DatabaseEncryptionException implements Exception {
  const DatabaseEncryptionException(this.code, this.message, {this.cause});

  final DatabaseEncryptionFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'DatabaseEncryptionException($code): $message';
}

typedef DatabaseRandomBytes = List<int> Function(int length);

/// Owns the persistent 256-bit key used by the native SQLCipher database.
///
/// A missing key is generated only for a new or known-plaintext database. If
/// encrypted database bytes already exist, generating a replacement would make
/// recovery impossible and is therefore rejected explicitly.
final class DatabaseEncryptionKeyManager {
  DatabaseEncryptionKeyManager(this._store, {DatabaseRandomBytes? randomBytes})
    : _randomBytes = randomBytes ?? _secureRandomBytes;

  final SecureKeyStore _store;
  final DatabaseRandomBytes _randomBytes;

  Future<String> loadOrCreate({required bool encryptedDatabaseExists}) async {
    final stored = await _store.read(databaseEncryptionKeyStorageKey);
    if (stored != null) {
      if (!isValidKey(stored)) {
        throw const DatabaseEncryptionException(
          DatabaseEncryptionFailureCode.invalidKey,
          'The stored database key is malformed.',
        );
      }
      return stored;
    }

    if (encryptedDatabaseExists) {
      throw const DatabaseEncryptionException(
        DatabaseEncryptionFailureCode.keyMissing,
        'Encrypted database bytes exist but the device key is unavailable.',
      );
    }

    final bytes = _randomBytes(databaseEncryptionKeyBytes);
    if (bytes.length != databaseEncryptionKeyBytes ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw StateError('Database key generator returned invalid bytes.');
    }
    final key = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    await _store.write(databaseEncryptionKeyStorageKey, key);
    return key;
  }

  static bool isValidKey(String value) =>
      value.length == databaseEncryptionKeyBytes * 2 &&
      RegExp(r'^[0-9a-f]+$').hasMatch(value);

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
