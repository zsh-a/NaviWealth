import 'dart:math';
import 'dart:typed_data';

import 'hex_codec.dart';
import 'secure_key_store.dart';

/// Provisions and persists the SQLCipher master key.
///
/// First launch: generate a 256-bit random key, hex-encode it, write it
/// to the [SecureKeyStore]. Subsequent launches: read it back. The key
/// never leaves the device — backups carry data, not the device key
/// (the user-supplied passphrase keys the backup separately).
class DbKeyProvider {
  DbKeyProvider(this._store, {Random? random})
    : _random = random ?? Random.secure();

  static const String storageKey = 'naviwealth.db_master_key';
  static const int keyLengthBytes = 32;

  final SecureKeyStore _store;
  final Random _random;

  Future<String> getOrCreate() async {
    final existing = await _store.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      _assertValidHexKey(existing);
      return existing;
    }
    final key = _generateKey();
    await _store.write(storageKey, key);
    return key;
  }

  /// Replaces the persisted key. Caller must re-key or re-create the
  /// database; this method only swaps the stored value.
  Future<void> overwrite(String hexKey) async {
    _assertValidHexKey(hexKey);
    await _store.write(storageKey, hexKey);
  }

  Future<void> erase() => _store.delete(storageKey);

  String _generateKey() {
    final bytes = Uint8List(keyLengthBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return hexEncode(bytes);
  }

  static void _assertValidHexKey(String value) {
    if (value.length != keyLengthBytes * 2) {
      throw FormatException(
        'Expected ${keyLengthBytes * 2}-char hex DB key, '
        'got length ${value.length}',
      );
    }
    if (!_hexPattern.hasMatch(value)) {
      throw const FormatException('DB key contains non-hex characters');
    }
  }

  static final RegExp _hexPattern = RegExp(r'^[0-9a-f]+$');
}
