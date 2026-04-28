import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/db_key_provider.dart';
import '../../core/security/flutter_secure_key_store.dart';
import '../../core/security/secure_key_store.dart';
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
  final db = AppDatabase.encrypted(encryptionKey: key);
  ref.onDispose(db.close);
  return db;
});
