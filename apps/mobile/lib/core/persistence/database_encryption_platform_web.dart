import '../security/secure_key_store.dart';
import 'connection_web.dart';

Future<String?> resolveDatabaseEncryptionKeyImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) async => null;

Future<void> resetEncryptedDatabaseImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) => resetWebDatabase(dbFileName);
