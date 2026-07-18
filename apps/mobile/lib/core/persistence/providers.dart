import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/flutter_secure_key_store.dart';
import '../../core/security/secure_key_store.dart';
import 'app_database.dart';
import 'database_encryption_platform.dart';

final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return FlutterSecureKeyStore();
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final store = ref.watch(secureKeyStoreProvider);
  final encryptionKey = await resolveDatabaseEncryptionKey(
    store: store,
    dbFileName: defaultDbFileName,
  );
  final db = AppDatabase.open(encryptionKey: encryptionKey);
  try {
    // Force the lazy native connection to verify SQLCipher, unlock, recover a
    // migration if necessary, and run Drift migrations before UI consumers
    // receive a seemingly healthy database handle.
    await db.customSelect('SELECT 1;').getSingle();
  } on Object {
    await db.close();
    rethrow;
  }
  ref.onDispose(db.close);
  return db;
});

final databaseRecoveryControllerProvider = Provider<DatabaseRecoveryController>(
  (ref) => DatabaseRecoveryController(
    resetDatabase: () => resetEncryptedDatabase(
      store: ref.read(secureKeyStoreProvider),
      dbFileName: defaultDbFileName,
    ),
    invalidateDatabase: () => ref.invalidate(appDatabaseProvider),
  ),
);

final class DatabaseRecoveryController {
  const DatabaseRecoveryController({
    required Future<void> Function() resetDatabase,
    required void Function() invalidateDatabase,
  }) : _resetDatabase = resetDatabase,
       _invalidateDatabase = invalidateDatabase;

  final Future<void> Function() _resetDatabase;
  final void Function() _invalidateDatabase;

  Future<void> resetLocalEncryptedData() async {
    await _resetDatabase();
    _invalidateDatabase();
  }
}
