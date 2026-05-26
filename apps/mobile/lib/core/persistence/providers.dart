import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/flutter_secure_key_store.dart';
import '../../core/security/secure_key_store.dart';
import 'app_database.dart';

final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return FlutterSecureKeyStore();
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});
