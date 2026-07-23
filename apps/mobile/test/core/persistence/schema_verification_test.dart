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
    test('is 53', () {
      expect(db.schemaVersion, 53);
    });
  });

  group('Investment portfolio tables exist', () {
    for (final table in const [
      'investment_portfolios',
      'portfolio_lot_memberships',
    ]) {
      test('$table has sync columns', () async {
        final result = await db.customSelect('PRAGMA table_info($table)').get();
        final columns = result.map((row) => row.read<String>('name')).toSet();
        expect(
          columns,
          containsAll(['id', 'owner_user_id', 'hlc', 'deleted_at']),
        );
      });
    }
  });

  group('Finance planning tables exist', () {
    for (final table in const [
      'financial_decisions',
      'dca_plans',
      'financial_signals',
      'financial_monthly_closes',
      'financial_reconciliations',
    ]) {
      test('$table has sync columns', () async {
        final result = await db.customSelect('PRAGMA table_info($table)').get();
        final columns = result.map((row) => row.read<String>('name')).toSet();
        expect(
          columns,
          containsAll(['id', 'owner_user_id', 'hlc', 'deleted_at']),
        );
      });
    }

    test('runway forecast snapshots stay local-only', () async {
      final result = await db
          .customSelect('PRAGMA table_info(runway_forecast_snapshots)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'predicted_balance',
          'actual_balance',
          'data_completeness',
          'evaluated_at',
        ]),
      );
      expect(columns, isNot(contains('hlc')));
    });

    test('dividend forecast snapshots stay local-only', () async {
      final result = await db
          .customSelect('PRAGMA table_info(dividend_forecast_snapshots)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'window_start',
          'target_at',
          'predicted_net',
          'actual_net',
          'strategy',
          'evaluated_at',
        ]),
      );
      expect(columns, isNot(contains('hlc')));
    });

    test('financial signals persist linked action revalidation', () async {
      final result = await db
          .customSelect('PRAGMA table_info(financial_signals)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'action_id',
          'revalidation_status',
          'revalidated_at',
          'action_completed_at',
        ]),
      );
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
      'knowledge_relations',
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

    test('promoted notes retain typed-object provenance', () async {
      final result = await db
          .customSelect('PRAGMA table_info(knowledge_notes)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'promoted_to_kind',
          'promoted_to_id',
          'promoted_at',
        ]),
      );
    });

    test('knowledge relations persist typed endpoints', () async {
      final result = await db
          .customSelect('PRAGMA table_info(knowledge_relations)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'from_kind',
          'from_id',
          'relation',
          'to_kind',
          'to_id',
        ]),
      );
    });

    test('financial close tables use evidence-driven columns', () async {
      final closeColumns =
          (await db
                  .customSelect('PRAGMA table_info(financial_monthly_closes)')
                  .get())
              .map((row) => row.read<String>('name'))
              .toSet();
      expect(
        closeColumns,
        containsAll(<String>[
          'evidence_json',
          'snapshot_json',
          'override_reason',
          'closed_at',
        ]),
      );
      expect(closeColumns, isNot(contains('completed_steps_json')));

      final reconciliationColumns =
          (await db
                  .customSelect('PRAGMA table_info(financial_reconciliations)')
                  .get())
              .map((row) => row.read<String>('name'))
              .toSet();
      expect(
        reconciliationColumns,
        containsAll(<String>[
          'period_month',
          'account_id',
          'unit',
          'statement_balance',
          'ledger_balance',
          'difference',
          'status',
          'verified_at',
        ]),
      );
    });
  });

  group('ExecutionOS tables exist', () {
    for (final table in [
      'execution_projects',
      'execution_actions',
      'execution_commitments',
      'execution_progress_entries',
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

    test('execution roll-up columns are present', () async {
      final actionColumns =
          (await db.customSelect('PRAGMA table_info(execution_actions)').get())
              .map((r) => r.read<String>('name'))
              .toSet();
      final commitmentColumns =
          (await db
                  .customSelect('PRAGMA table_info(execution_commitments)')
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      final progressColumns =
          (await db
                  .customSelect('PRAGMA table_info(execution_progress_entries)')
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();

      expect(actionColumns, contains('project_id'));
      expect(commitmentColumns, contains('project_id'));
      expect(progressColumns, contains('project_id'));
    });
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

    test('recurring_pattern_observations table has expected columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(recurring_pattern_observations)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'owner_user_id',
          'merchant_key',
          'cadence',
          'currency',
          'median_amount_minor',
          'last_seen_at',
          'observed_at',
        ]),
      );
    });

    test('chat_messages table has AI progress columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(chat_messages)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'tool_calls_json',
          'text_segments_json',
          'reasoning_text',
          'usage_json',
          'progress_json',
        ]),
      );
    });

    test('agent_runs table has lifecycle columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_runs)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'owner_user_id',
          'agent_id',
          'agent_name',
          'status',
          'trigger',
          'started_at',
          'finished_at',
          'summary',
          'error',
          'memory_id',
          'artifact_id',
          'trace_id',
        ]),
      );
    });

    test('agent_runtime_checkpoints table has journal columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_runtime_checkpoints)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'owner_user_id',
          'run_id',
          'agent_id',
          'request_fingerprint',
          'snapshot_version',
          'revision',
          'status',
          'snapshot_json',
          'resume_context_json',
          'effect_kind',
          'effect_id',
          'effect_payload_json',
          'created_at',
          'updated_at',
          'expires_at',
        ]),
      );
    });

    test('agent_runtime_chat_snapshots table has recovery columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_runtime_chat_snapshots)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'owner_user_id',
          'turn_id',
          'snapshot_version',
          'revision',
          'status',
          'snapshot_json',
          'created_at',
          'updated_at',
          'expires_at',
        ]),
      );
    });

    test('agent_artifacts table has result columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_artifacts)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'owner_user_id',
          'agent_id',
          'domain',
          'kind',
          'severity',
          'title',
          'summary',
          'presentation_json',
          'insights_json',
          'evidence_json',
          'actions_json',
          'memory_id',
          'trace_id',
          'created_at',
          'expires_at',
          'dismissed_at',
          'snoozed_until',
        ]),
      );
    });

    test('agent_preferences table has preference columns', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_preferences)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'owner_user_id',
          'agent_id',
          'enabled',
          'notifications_enabled',
          'updated_at',
        ]),
      );
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
