import 'package:drift/drift.dart';

import 'connection.dart';
import 'migrations.dart';
import 'tables.dart';

part 'app_database.g.dart';

const String defaultDbFileName = 'naviwealth.db';

@DriftDatabase(tables: [Accounts, Assets, Txns, FxRates, AppMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase({required String encryptionKey, String? dbFileName})
    : super(
        openAppConnection(
          dbFileName: dbFileName ?? defaultDbFileName,
          encryptionKey: encryptionKey,
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => SchemaVersions.current;

  @override
  MigrationStrategy get migration => buildMigrationStrategy(this);
}
