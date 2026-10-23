import '../security/secure_key_store.dart';
import 'database_encryption_platform_stub.dart'
    if (dart.library.io) 'database_encryption_platform_native.dart'
    if (dart.library.js_interop) 'database_encryption_platform_web.dart';

Future<String?> resolveDatabaseEncryptionKey({
  required SecureKeyStore store,
  required String dbFileName,
}) => resolveDatabaseEncryptionKeyImpl(store: store, dbFileName: dbFileName);

Future<void> resetLocalDatabase({
  required SecureKeyStore store,
  required String dbFileName,
}) => resetEncryptedDatabaseImpl(store: store, dbFileName: dbFileName);
