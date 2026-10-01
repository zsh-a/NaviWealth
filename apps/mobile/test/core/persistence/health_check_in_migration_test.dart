import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _FailAfterCreate extends QueryInterceptor {
  bool injected = false;
  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_Opening(user, this));
  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement.startsWith('CREATE TABLE') &&
        statement.contains('health_check_ins')) {
      injected = true;
      throw StateError('Injected interruption');
    }
  }
}

class _Opening extends QueryExecutorUser {
  _Opening(this.user, this.interceptor);
  final QueryExecutorUser user;
  final QueryInterceptor interceptor;
  @override
  int get schemaVersion => user.schemaVersion;
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      user.beforeOpen(executor.interceptWith(interceptor), details);
}

void main() {
  for (final fail in [false, true]) {
    test(
      'v96 health check-in upgrade preserves data (interrupted: $fail)',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'naviwealth-health-v97-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/health.db');
        final seed = AppDatabase(NativeDatabase(file));
        await seed.customStatement(
          "INSERT INTO health_metrics (id,captured_at,kind,value,unit,owner_user_id,updated_at,updated_by_device,hlc) VALUES ('hk:hrv',1700000000,'hrv_daily',50,'ms','user',1700000000,'device','1700000000000.0000-device')",
        );
        await DriftOutboxStore(seed)
            .enqueue(table: 'health_metrics', rowId: 'hk:hrv');
        await DriftCursorStore(seed).writeSeq(123);
        final before =
            (await seed.customSelect('SELECT * FROM health_metrics').get())
                .single
                .data;
        await seed.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('DROP TABLE health_check_ins');
        raw.execute('PRAGMA user_version = 96');
        raw.close();
        if (fail) {
          final fault = _FailAfterCreate();
          final broken = AppDatabase(NativeDatabase(file).interceptWith(fault));
          await expectLater(
            broken.customSelect('SELECT 1').get(),
            throwsStateError,
          );
          expect(fault.injected, true);
          await broken.close();
          final check = sqlite.sqlite3.open(file.path);
          expect(
            check.select('PRAGMA user_version').single['user_version'],
            96,
          );
          expect(
            check.select(
              "SELECT name FROM sqlite_master WHERE name = 'health_check_ins'",
            ),
            isEmpty,
          );
          check.close();
        }
        for (var open = 0; open < 2; open++) {
          final migrated = AppDatabase(NativeDatabase(file));
          expect(
            (await migrated.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            97,
          );
          expect(
            (await migrated.customSelect('SELECT * FROM health_metrics').get())
                .single
                .data,
            before,
          );
          expect(await migrated.select(migrated.healthCheckIns).get(), isEmpty);
          expect(await DriftOutboxStore(migrated).depth(), 1);
          expect(await DriftCursorStore(migrated).readSeq(), 123);
          await migrated.close();
        }
      },
    );
  }
}
