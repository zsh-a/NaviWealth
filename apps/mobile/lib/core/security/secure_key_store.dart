/// Persistent storage for cryptographic secrets that must outlive a single
/// app launch (DB master key, refresh tokens, etc.).
///
/// On iOS this is the Keychain, on Android the EncryptedSharedPreferences
/// backed by the Keystore. Implementations must keep secrets out of plain
/// app sandbox storage.
abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> contains(String key);
}
