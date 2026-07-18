import '../security/secure_key_store.dart';

Future<String?> resolveDatabaseEncryptionKeyImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) async => null;

Future<void> resetEncryptedDatabaseImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) async {
  throw UnsupportedError('Native database encryption is unavailable.');
}
