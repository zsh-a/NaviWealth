import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_tables.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _tables = [
  'accounts',
  'journal_entries',
  'postings',
  'health_metrics',
  'knowledge_notes',
  'knowledge_decisions',
  'knowledge_relations',
  'execution_plans',
  'execution_actions',
  'execution_progress_entries',
  'memories',
  'memory_embeddings',
  'personal_profile_facts',
  'op_outbox',
  'sync_meta',
];

Future<void> _insert(
  AppDatabase db,
  String table,
  Map<String, Object?> fields, {
  bool synced = true,
}) async {
  final values = {
    ...fields,
    if (synced) ...{
      'owner_user_id': 'user-1',
      'updated_at': 1700000000,
      'updated_by_device': 'device',
      'hlc': const Hlc(
        wallMillis: 1700000000000,
        counter: 2,
        nodeId: 'device',
      ).toString(),
    },
  };
  await db.customStatement(
    'INSERT INTO $table (${values.keys.join(', ')}) '
    'VALUES (${List.filled(values.length, '?').join(', ')})',
    values.values.toList(),
  );
}

Future<void> _seedV95(File file) async {
  // v96 adds one raw SQL table only. Removing it and stamping v95 yields
  // the actual previous shape without copying generated Drift definitions.
  final db = AppDatabase(NativeDatabase(file));
  try {
    for (final account in [('cash', 'asset'), ('salary', 'income')]) {
      await _insert(db, 'accounts', {
        'id': account.$1,
        'type': 'cash',
        'category': account.$2,
        'name': account.$1,
        'currency': 'CNY',
      });
    }
    await _insert(db, 'journal_entries', {
      'id': 'entry',
      'date': 1700000000,
      'narration': 'Salary deposit',
    });
    for (final posting in [
      ('cash', '1250.123456789'),
      ('salary', '-1250.123456789'),
    ]) {
      await _insert(db, 'postings', {
        'id': 'posting-${posting.$1}',
        'journal_entry_id': 'entry',
        'position': posting.$1 == 'cash' ? 0 : 1,
        'account_id': posting.$1,
        'units': posting.$2,
        'unit': 'CNY',
      });
    }
    await _insert(db, 'health_metrics', {
      'id': 'steps',
      'captured_at': 1700000000,
      'kind': 'steps_daily',
      'value': 8500.0,
      'unit': 'count',
      'source_id': 'manual',
    });
    await _insert(db, 'knowledge_notes', {
      'id': 'note',
      'title': 'Cash reserve',
      'body_md': 'Keep twelve months.',
      'created_at': 1700000000,
    });
    await _insert(db, 'knowledge_decisions', {
      'id': 'decision',
      'question': 'Reserve size?',
      'selected_label': '12 months',
      'rationale_md': 'Income variability',
      'decided_at': 1700000000,
    });
    await _insert(db, 'knowledge_relations', {
      'id': 'relation',
      'from_kind': 'note',
      'from_id': 'note',
      'relation': 'supports',
      'to_kind': 'decision',
      'to_id': 'decision',
      'created_at': 1700000000,
    });
    await _insert(db, 'execution_plans', {
      'id': 'plan',
      'title': 'Build reserve',
      'created_at': 1700000000,
      'source_domain': 'knowledge',
      'source_row_id': 'decision',
    });
    await _insert(db, 'execution_actions', {
      'id': 'action',
      'plan_id': 'plan',
      'title': 'Transfer monthly savings',
      'source_domain': 'finance',
      'source_row_id': 'cash',
      'created_at': 1700000000,
    });
    await _insert(db, 'execution_progress_entries', {
      'id': 'progress',
      'plan_id': 'plan',
      'action_id': 'action',
      'note': 'First transfer complete',
      'created_at': 1700000000,
    });
    for (final memory in ['previous', 'current']) {
      await _insert(db, 'memories', {
        'id': memory,
        'owner_user_id': 'user-1',
        'kind': 'semantic',
        'role': 'guidance',
        'authority': 'user_confirmed',
        'provenance_json':
            '{"source":"user_confirmed_ai","proposal_id":"approved"}',
        'supersedes_id': memory == 'current' ? 'previous' : null,
        'title': 'Reserve rule',
        'summary': 'Keep twelve months of expenses.',
        'payload_json': '{"months":12}',
        'entities_json': '["cash"]',
        'valid_until': memory == 'previous' ? 1700000000000 : null,
        'created_at': 1690000000000,
        'updated_at': 1700000000000,
      }, synced: false);
    }
    await db.customStatement(
      "INSERT INTO memory_embeddings VALUES ('current', 'model-v1', 2, X'0000803F00000000')",
    );
    await _insert(db, 'personal_profile_facts', {
      'id': 'profile',
      'owner_user_id': 'user-1',
      'kind': 'rule',
      'fact_key': 'reserve',
      'value_json': '12',
      'summary': '12 month reserve',
      'authority': 'user_confirmed',
      'provenance_json': '{"source":"settings"}',
      'confidence': 1.0,
      'confirmed_at': 1700000000000,
      'valid_from': 1700000000000,
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    }, synced: false);
    for (final pointer in [
      ('accounts', 'cash'),
      ('knowledge_notes', 'note'),
      ('execution_actions', 'action'),
    ]) {
      await DriftOutboxStore(db).enqueue(table: pointer.$1, rowId: pointer.$2);
    }
    await DriftCursorStore(db).writeSeq(123);
    await DriftCursorStore(db).writeLocalHlc(
      const Hlc(wallMillis: 1700000000001, counter: 3, nodeId: 'device'),
    );
    await DriftDomainGenerationStore(
      db,
      ownerUserId: 'user-1',
    ).write('finance', 4);
  } finally {
    await db.close();
  }
  final raw = sqlite3.sqlite3.open(file.path);
  try {
    raw.execute('DROP TABLE sync_row_extras');
    raw.execute('DROP TABLE health_check_ins');
    raw.execute('PRAGMA user_version = 95');
  } finally {
    raw.close();
  }
}

Map<String, Object?> _snapshot(File file) {
  final raw = sqlite3.sqlite3.open(file.path);
  try {
    return {
      for (final table in _tables)
        table: raw
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
    };
  } finally {
    raw.close();
  }
}

class _FailAfterDdl extends QueryInterceptor {
  bool injected = false;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_InterceptOpening(user, this));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement == createSyncRowExtras) {
      injected = true;
      throw StateError('Injected failure after compatibility DDL');
    }
  }
}

class _InterceptOpening extends QueryExecutorUser {
  _InterceptOpening(this.user, this.interceptor);
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
      fail
          ? 'failed v95 upgrade rolls DDL back and retries without losing user data'
          : 'v95 upgrade preserves all domains, confirmed memory, profile and dirty rows',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'naviwealth-sync-v96-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/lifeos.db');
        await _seedV95(file);
        final before = _snapshot(file);
        if (fail) {
          final fault = _FailAfterDdl();
          final broken = AppDatabase(NativeDatabase(file).interceptWith(fault));
          try {
            await expectLater(
              broken.customSelect('SELECT 1').get(),
              throwsStateError,
            );
            expect(fault.injected, isTrue);
          } finally {
            await broken.close();
          }
          final raw = sqlite3.sqlite3.open(file.path);
          try {
            expect(
              raw.select('PRAGMA user_version').single['user_version'],
              95,
            );
            expect(
              raw.select(
                "SELECT name FROM sqlite_master WHERE name = 'sync_row_extras'",
              ),
              isEmpty,
            );
          } finally {
            raw.close();
          }
          expect(_snapshot(file), before);
        }
        for (var open = 0; open < 2; open++) {
          final migrated = AppDatabase(NativeDatabase(file));
          try {
            expect(
              (await migrated.customSelect('PRAGMA user_version').getSingle())
                  .read<int>('user_version'),
              migrated.schemaVersion,
            );
            expect(
              await migrated
                  .customSelect('SELECT * FROM sync_row_extras')
                  .get(),
              isEmpty,
            );
            expect(await DriftOutboxStore(migrated).depth(), 3);
            expect(await DriftCursorStore(migrated).readSeq(), 123);
            expect(
              await DriftCursorStore(migrated).readLocalHlc(),
              const Hlc(
                wallMillis: 1700000000001,
                counter: 3,
                nodeId: 'device',
              ),
            );
            expect(
              await DriftDomainGenerationStore(
                migrated,
                ownerUserId: 'user-1',
              ).readAll(),
              {'finance': 4},
            );
          } finally {
            await migrated.close();
          }
          expect(_snapshot(file), before);
        }
      },
    );
  }
}
