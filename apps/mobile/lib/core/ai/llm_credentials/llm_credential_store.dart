/// Persistent home for the user's [LlmCredentials].
///
/// Backed by [SecureKeyStore] — the *same* store as the auth session
/// and the SQLCipher DB key (iOS Keychain / Android Keystore-backed
/// EncryptedSharedPreferences). The key therefore never lands in the
/// ordinary app preferences, the sync outbox, or a plaintext backup.
///
/// Mirrors [TokenStore]: one namespaced slot, JSON value, corrupt
/// entries are dropped so callers fall back to "no device LLM".
library;

import '../../security/secure_key_store.dart';
import 'llm_credentials.dart';

class LlmCredentialStore {
  LlmCredentialStore(this._store);

  /// Single document containing named profiles and their active id. Namespaced
  /// alongside `naviwealth.auth_session` so it's discoverable in the
  /// Keychain UI and obviously security-sensitive.
  static const String storageKey = 'naviwealth.llm_credentials';

  final SecureKeyStore _store;

  Future<LlmCredentials?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return LlmCredentials.decode(raw);
    } on FormatException {
      // Corrupt entry — drop it so the caller behaves as "no key".
      await _store.delete(storageKey);
      return null;
    }
  }

  Future<void> write(LlmCredentials credentials) =>
      _store.write(storageKey, credentials.encode());

  Future<void> clear() => _store.delete(storageKey);
}
