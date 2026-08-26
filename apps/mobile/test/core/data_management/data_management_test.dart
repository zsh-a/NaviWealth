import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:talker/talker.dart';

import '../persistence/test_database.dart';

void main() {
  group('DataManagementService', () {
    test('normalizes PRAGMA integer values from different drivers', () {
      expect(
        DataManagementService.parsePragmaIntValue(4096, pragma: 'page_size'),
        4096,
      );
      expect(
        DataManagementService.parsePragmaIntValue(4096.0, pragma: 'page_size'),
        4096,
      );
      expect(
        DataManagementService.parsePragmaIntValue('4096', pragma: 'page_size'),
        4096,
      );
      expect(
        () => DataManagementService.parsePragmaIntValue(
          '4096.5',
          pragma: 'page_size',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('inspects owner-scoped source, tombstones, and caches', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _createFixtureTables(db);

      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        specs: const <DomainDataManagementSpec>[
          DomainDataManagementSpec(
            scope: DomainScope.knowledge,
            label: 'KnowledgeOS',
            sourceTables: <DataTableSpec>[
              DataTableSpec(
                table: 'dm_source',
                ownerScoped: true,
                hasTombstones: true,
              ),
            ],
            cacheTables: <DataTableSpec>[
              DataTableSpec(table: 'dm_cache', ownerScoped: true),
              DataTableSpec(table: 'dm_global_cache'),
            ],
          ),
        ],
      );

      final snapshot = (await service.inspectAll()).single;
      expect(snapshot.sourceRows, 1);
      expect(snapshot.deletedRows, 1);
      expect(snapshot.cacheRows, 2);
      expect(snapshot.sourceTableCount, 1);
      expect(snapshot.cacheTableCount, 2);
    });

    test('clears only registered caches and preserves source data', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _createFixtureTables(db);

      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        specs: const <DomainDataManagementSpec>[
          DomainDataManagementSpec(
            scope: DomainScope.knowledge,
            label: 'KnowledgeOS',
            sourceTables: <DataTableSpec>[
              DataTableSpec(
                table: 'dm_source',
                ownerScoped: true,
                hasTombstones: true,
              ),
            ],
            cacheTables: <DataTableSpec>[
              DataTableSpec(table: 'dm_cache', ownerScoped: true),
              DataTableSpec(table: 'dm_global_cache'),
            ],
          ),
        ],
      );

      expect(await service.clearCache(DomainScope.knowledge), 2);
      expect(await _count(db, 'dm_source'), 3);
      expect(await _count(db, 'dm_cache'), 1);
      expect(await _count(db, 'dm_global_cache'), 0);
    });

    test('resets source/cache rows and requeues preserved rows', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _createFixtureTables(db);

      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        specs: const <DomainDataManagementSpec>[
          DomainDataManagementSpec(
            scope: DomainScope.knowledge,
            label: 'KnowledgeOS',
            sourceTables: <DataTableSpec>[
              DataTableSpec(table: 'dm_source', ownerScoped: true),
              DataTableSpec(
                table: 'dm_preserved',
                ownerScoped: true,
                preserveOnReset: true,
              ),
            ],
            cacheTables: <DataTableSpec>[
              DataTableSpec(table: 'dm_cache', ownerScoped: true),
              DataTableSpec(table: 'dm_global_cache'),
            ],
          ),
        ],
      );

      await service.resetLocalDomain(
        DomainScope.knowledge,
        requeuePreserved: true,
      );

      expect(await _count(db, 'dm_source'), 1);
      expect(await _count(db, 'dm_cache'), 1);
      expect(await _count(db, 'dm_global_cache'), 0);
      expect(await _count(db, 'dm_preserved'), 2);
      final pointer = await db
          .customSelect(
            'SELECT table_name, row_id FROM op_outbox '
            "WHERE table_name = 'dm_preserved'",
          )
          .getSingle();
      expect(pointer.read<String>('row_id'), 'preserved-a');
    });

    test('rejects unsafe registered table names', () {
      final db = makeTestDatabase();
      addTearDown(db.close);

      expect(
        () => DataManagementService(
          database: db,
          ownerUserId: 'user-a',
          specs: const <DomainDataManagementSpec>[
            DomainDataManagementSpec(
              scope: DomainScope.finance,
              label: 'FinanceOS',
              sourceTables: <DataTableSpec>[
                DataTableSpec(table: 'accounts; DROP TABLE accounts'),
              ],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('logs the exact source table when inspection fails', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final talker = Talker(
        settings: TalkerSettings(useConsoleLogs: false, useHistory: true),
      );
      final logger = AppLogger(environment: AppEnvironment.dev, talker: talker);
      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        logger: logger,
        specs: const <DomainDataManagementSpec>[
          DomainDataManagementSpec(
            scope: DomainScope.finance,
            label: 'FinanceOS',
            sourceTables: <DataTableSpec>[
              DataTableSpec(table: 'missing_source_table', ownerScoped: true),
            ],
          ),
        ],
      );

      await expectLater(service.inspectAll(), throwsA(anything));

      final history = logger.talker.history
          .map((entry) => '${entry.message}\n${entry.error}')
          .join('\n');
      expect(
        history,
        contains(
          'data_management.inspect_domains failed '
          'stage=source_rows domain=finance table=missing_source_table',
        ),
      );
      expect(history, contains('owner_scoped=true'));
      expect(history, isNot(contains('user-a')));
    });

    test('inspects and clears only the current user shared history', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await _insertSharedHistory(db, 'user-a', 'a');
      await _insertSharedHistory(db, 'user-b', 'b');
      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        specs: const <DomainDataManagementSpec>[],
      );

      final before = await service.inspectSharedData();
      expect(before.chatRows, 2);
      expect(before.aiRows, 1);
      expect(before.memoryRows, 2);
      expect(before.agentRows, 1);
      expect(before.historyRows, 6);
      expect(before.databaseBytes, greaterThan(0));

      expect(await service.clearSharedHistory(), 6);
      final after = await service.inspectSharedData();
      expect(after.historyRows, 0);
      expect(await _count(db, 'chat_sessions'), 1);
      expect(await _count(db, 'conversation_checkpoints'), 1);
      expect(await _count(db, 'ai_traces'), 1);
      expect(await _count(db, 'memories'), 1);
      expect(await _count(db, 'memory_candidates'), 1);
      expect(await _count(db, 'agent_runs'), 1);

      final compacted = await service.compactDatabase();
      expect(compacted.databaseBytes, greaterThan(0));
    });
  });

  test('sync source inventory stays derived from the sync registry', () {
    final health = syncDataTablesForPrefix(kHealthDomainPrefix);
    expect(health.map((table) => table.table), contains('health_metrics'));
    expect(health.every((table) => table.hasTombstones), isTrue);
    final finance = syncDataTablesForPrefix(kFinanceDomainPrefix);
    expect(
      finance.singleWhere((table) => table.table == 'fx_rates').hasTombstones,
      isFalse,
    );
  });
}

Future<void> _createFixtureTables(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE dm_source ('
    'id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL, deleted_at INTEGER)',
  );
  await db.customStatement(
    'CREATE TABLE dm_cache ('
    'id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL)',
  );
  await db.customStatement(
    'CREATE TABLE dm_global_cache (id TEXT PRIMARY KEY)',
  );
  await db.customStatement(
    'CREATE TABLE dm_preserved ('
    'id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO dm_source VALUES '
    "('live-a', 'user-a', NULL), "
    "('deleted-a', 'user-a', 1), "
    "('live-b', 'user-b', NULL)",
  );
  await db.customStatement(
    'INSERT INTO dm_cache VALUES '
    "('cache-a', 'user-a'), ('cache-b', 'user-b')",
  );
  await db.customStatement("INSERT INTO dm_global_cache VALUES ('global')");
  await db.customStatement(
    'INSERT INTO dm_preserved VALUES '
    "('preserved-a', 'user-a'), ('preserved-b', 'user-b')",
  );
}

Future<int> _count(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

Future<void> _insertSharedHistory(
  AppDatabase db,
  String owner,
  String suffix,
) async {
  await db.customStatement(
    'INSERT INTO chat_sessions '
    '(id, owner_user_id, title, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?)',
    <Object?>['chat-$suffix', owner, 'Chat', 1, 1],
  );
  await db.customStatement(
    'INSERT INTO conversation_checkpoints ('
    'session_id, owner_user_id, summary_through_message_id, '
    'summary_through_created_at, source_fingerprint, checkpoint_version, '
    'source_message_count, payload_json, created_at, updated_at'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      'chat-$suffix',
      owner,
      'message-$suffix',
      1,
      'sha256:$suffix',
      1,
      1,
      '{}',
      1,
      1,
    ],
  );
  await db.customStatement(
    'INSERT INTO ai_traces '
    '(request_id, owner_user_id, started_at_iso, payload_json) '
    'VALUES (?, ?, ?, ?)',
    <Object?>['trace-$suffix', owner, '2026-01-01T00:00:00Z', '{}'],
  );
  await db.customStatement(
    'INSERT INTO memories '
    '(id, kind, role, authority, provenance_json, scope, owner_user_id, '
    'title, summary, payload_json, entities_json, importance, confidence, '
    'created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      'memory-$suffix',
      'semantic',
      'legacy',
      'legacy_unknown',
      '{}',
      '*',
      owner,
      'Memory',
      'Summary',
      '{}',
      '[]',
      0.5,
      0.8,
      1,
      1,
    ],
  );
  await db.customStatement(
    'INSERT INTO memory_candidates ('
    'id, proposal_id, owner_user_id, target_type, operation, status, payload_json, '
    'created_at, updated_at'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      'candidate-$suffix',
      'proposal-$suffix',
      owner,
      'memory',
      'create',
      'pending',
      '{}',
      1,
      1,
    ],
  );
  await db.customStatement(
    'INSERT INTO agent_runs '
    '(id, owner_user_id, agent_id, agent_name, status, trigger, started_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      'run-$suffix',
      owner,
      'agent-$suffix',
      'Agent',
      'ready',
      'manual',
      1,
    ],
  );
}
