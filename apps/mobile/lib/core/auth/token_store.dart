import '../security/secure_key_store.dart';
import 'auth_session.dart';

/// Persistent home for the active [AuthSession].
///
/// Backed by [SecureKeyStore]:
///   - iOS: Keychain (`first_unlock` accessibility) — survives app reinstalls.
///   - Android: EncryptedSharedPreferences over the Keystore.
///   - Web: `flutter_secure_storage`'s WebCrypto + IndexedDB fallback.
///
/// FIR-30's original spec called for `HttpOnly` cookies on web, but the
/// backend (FIR-29) returns the access token in the JSON body for every
/// platform and does not issue `Set-Cookie`. Until that contract changes
/// we keep one storage mechanism so login / refresh flow is identical
/// across platforms — see `docs/auth.md` (added in this commit) for the
/// trade-off and the path to migrate if a follow-up moves web to cookies.
class TokenStore {
  TokenStore(this._store);

  /// Single key — we only ever hold one session at a time. Namespaced
  /// alongside the DB master key so it's discoverable in the Keychain UI.
  static const String storageKey = 'naviwealth.auth_session';

  final SecureKeyStore _store;

  Future<AuthSession?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthSession.decode(raw);
    } on FormatException {
      // Corrupt entry — drop it so the caller falls back to /login.
      await _store.delete(storageKey);
      return null;
    }
  }

  Future<void> write(AuthSession session) =>
      _store.write(storageKey, session.encode());

  Future<void> clear() => _store.delete(storageKey);
}
