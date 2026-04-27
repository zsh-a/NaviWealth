import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drift_account_repository.dart';
import '../../domain/repositories/account_repository.dart';
import '../backup/backup_service.dart';
import '../security/db_key_provider.dart';
import '../security/flutter_secure_key_store.dart';
import '../security/secure_key_store.dart';
import 'app_database.dart';

final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return FlutterSecureKeyStore();
});

final dbKeyProviderProvider = Provider<DbKeyProvider>((ref) {
  return DbKeyProvider(ref.watch(secureKeyStoreProvider));
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final keyProvider = ref.watch(dbKeyProviderProvider);
  final key = await keyProvider.getOrCreate();
  final db = AppDatabase(encryptionKey: key);
  ref.onDispose(db.close);
  return db;
});

final accountRepositoryProvider = FutureProvider<AccountRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftAccountRepository(db);
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return BackupService(db);
});
