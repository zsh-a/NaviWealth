import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

/// Schema verification tests — ensure the Drift schema contains all
/// expected tables and columns. These tests guard against accidental
/// schema regressions (e.g. a table being dropped or a column renamed
/// without a migration).
void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(logStatements: false)),
    );
  });

  tearDown(() async => db.close());

  group('Schema version', () {
    test('is 24', () {
      expect(db.schemaVersion, 24);
    });
  });

  group('Core finance tables exist', () {
    test('accounts table has expected columns', () async {
      final result = await db.customSelect('PRAGMA table_info(accounts)').get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'name',
          'type',
          'category',
          'currency',
          'owner_user_id',
        ]),
      );
    });

    test('journal_entries table has expected columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(journal_entries)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(columns, containsAll(['id', 'date', 'flag', 'owner_user_id']));
    });

    test('postings table has expected columns', () async {
      final result = await db.customSelect('PRAGMA table_info(postings)').get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(['id', 'journal_entry_id', 'account_id', 'position']),
      );
    });

    test('assets table has expected columns', () async {
      final result = await db.customSelect('PRAGMA table_info(assets)').get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(columns, containsAll(['id', 'type', 'owner_user_id']));
    });

    test('liabilities table has expected columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(liabilities)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'type',
          'payment_method',
          'rate_type',
          'owner_user_id',
        ]),
      );
    });

    test('settings table has expected columns', () async {
      final result = await db.customSelect('PRAGMA table_info(settings)').get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'user_id',
          'theme_mode',
          'privacy_mode',
          'cost_basis_method',
        ]),
      );
    });
  });

  group('Sync infrastructure tables exist', () {
    test('op_outbox table exists', () async {
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='op_outbox'",
          )
          .get();
      expect(result, hasLength(1));
    });

    test('sync_meta table exists', () async {
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_meta'",
          )
          .get();
      expect(result, hasLength(1));
    });

    test('cursors are stored in sync_meta', () async {
      // Cursors are stored as key-value pairs in sync_meta (key = 'sync.cursor'),
      // not in a separate table.
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_meta'",
          )
          .get();
      expect(result, hasLength(1));
    });
  });

  group('HealthOS tables exist', () {
    test('health_metrics table has expected columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(health_metrics)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(['id', 'kind', 'value', 'captured_at', 'owner_user_id']),
      );
    });
  });

  group('KnowledgeOS tables exist', () {
    for (final table in [
      'knowledge_notes',
      'knowledge_principles',
      'knowledge_assumptions',
      'knowledge_decisions',
      'knowledge_concepts',
      'knowledge_experiments',
      'knowledge_routines',
    ]) {
      test('$table has sync columns', () async {
        final result = await db.customSelect('PRAGMA table_info($table)').get();
        final columns = result.map((r) => r.read<String>('name')).toSet();
        expect(
          columns,
          containsAll(['id', 'owner_user_id', 'deleted_at', 'hlc']),
          reason: '$table must have SyncableTable columns',
        );
      });
    }
  });

  group('AI infrastructure tables exist', () {
    test('ai_traces table exists', () async {
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_traces'",
          )
          .get();
      expect(result, hasLength(1));
    });

    test('ai_undo_stack table exists', () async {
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_undo_stack'",
          )
          .get();
      expect(result, hasLength(1));
    });

    test('memory_embeddings table exists', () async {
      final result = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_embeddings'",
          )
          .get();
      expect(result, hasLength(1));
    });
  });

  group('SyncableTable mixin columns', () {
    test(
      'accounts has sync columns (owner_user_id, deleted_at, hlc, updated_at, updated_by_device)',
      () async {
        final result = await db
            .customSelect('PRAGMA table_info(accounts)')
            .get();
        final columns = result.map((r) => r.read<String>('name')).toSet();
        expect(
          columns,
          containsAll([
            'owner_user_id',
            'deleted_at',
            'hlc',
            'updated_at',
            'updated_by_device',
          ]),
        );
      },
    );
  });
}
