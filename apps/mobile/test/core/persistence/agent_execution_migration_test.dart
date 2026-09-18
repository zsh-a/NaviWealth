import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/local_only_tables.dart';

void main() {
  for (final hasProjection in [false, true]) {
    test(
      'v93 execution projection upgrade preserves history (column=$hasProjection)',
      () async {
        final db = AppDatabase(
          DatabaseConnection(
            NativeDatabase.memory(
              setup: (sqlite) {
                sqlite.execute(
                  hasProjection
                      ? createAgentRuns
                      : createAgentRuns.replaceFirst(
                          ',\n  execution_json TEXT',
                          '',
                        ),
                );
                sqlite.execute(
                  "INSERT INTO agent_runs (id, owner_user_id, agent_id, agent_name, status, trigger, started_at, summary) VALUES ('old', 'alice', 'task', 'Task', 'ready', 'manual', 1, 'Previous report')",
                );
                sqlite.execute('PRAGMA user_version = 93');
              },
            ),
          ),
        );
        addTearDown(db.close);
        final row = await db
            .customSelect('SELECT summary, execution_json FROM agent_runs')
            .getSingle();
        expect(row.read<String>('summary'), 'Previous report');
        expect(row.readNullable<String>('execution_json'), null);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          94,
        );
      },
    );
  }
}
