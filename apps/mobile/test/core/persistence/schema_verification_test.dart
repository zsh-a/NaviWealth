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
    test('is 88', () {
      expect(db.schemaVersion, 88);
    });
  });

  group('Corporate-action candidate cache', () {
    test('keeps normalized candidates local-only', () async {
      final result = await db
          .customSelect('PRAGMA table_info(market_corporate_action_candidates)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'source_key',
          'revision_hash',
          'identity_strength',
          'market',
          'symbol',
          'record_date',
          'ex_date',
          'pay_date',
          'cash_per_share',
          'fetched_at',
        ]),
      );
      expect(
        columns.intersection({
          'owner_user_id',
          'hlc',
          'updated_by_device',
          'deleted_at',
        }),
        isEmpty,
      );
    });

    test('preserves authoritative-empty fetch metadata', () async {
      final result = await db
          .customSelect(
            'PRAGMA table_info(market_corporate_action_fetch_states)',
          )
          .get();
      expect(
        result.map((row) => row.read<String>('name')),
        containsAll([
          'market',
          'symbol',
          'provider',
          'disposition',
          'fetched_at',
        ]),
      );
    });
  });

  group('Watchlist collections', () {
    for (final table in const [
      'watchlist_collections',
      'watchlist_collection_members',
    ]) {
      test('$table has sync columns', () async {
        final result = await db.customSelect('PRAGMA table_info($table)').get();
        final columns = result.map((row) => row.read<String>('name')).toSet();
        expect(
          columns,
          containsAll([
            'id',
            'owner_user_id',
            'hlc',
            'deleted_at',
            'sort_rank',
          ]),
        );
      });
    }

    test('members preserve both sides of the relationship', () async {
      final result = await db
          .customSelect('PRAGMA table_info(watchlist_collection_members)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(columns, containsAll(['collection_id', 'watchlist_item_id']));
    });
  });

  group('Watchlist simulations', () {
    for (final table in const [
      'watchlist_simulations',
      'watchlist_simulation_positions',
      'watchlist_simulation_allocation_versions',
      'watchlist_simulation_holding_versions',
      'watchlist_simulation_action_entries',
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

    test('simulation inputs stay paper-only and decimal-backed', () async {
      final simulationColumns = await db
          .customSelect('PRAGMA table_info(watchlist_simulations)')
          .get();
      final simulationNames = simulationColumns
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        simulationNames,
        containsAll([
          'collection_id',
          'base_currency',
          'starting_capital',
          'cash_weight',
          'calculation_mode',
          'baseline_at',
        ]),
      );
      expect(
        simulationNames.intersection({
          'portfolio_id',
          'account_id',
          'journal_entry_id',
        }),
        isEmpty,
      );

      final positionColumns = await db
          .customSelect('PRAGMA table_info(watchlist_simulation_positions)')
          .get();
      expect(
        positionColumns.map((row) => row.read<String>('name')),
        containsAll(['simulation_id', 'watchlist_item_id', 'target_weight']),
      );
    });

    test('holding versions preserve quote and missing-FX evidence', () async {
      final result = await db
          .customSelect(
            'PRAGMA table_info(watchlist_simulation_holding_versions)',
          )
          .get();
      final columns = {
        for (final row in result)
          row.read<String>('name'): row.read<int>('notnull'),
      };
      expect(
        columns.keys,
        containsAll([
          'allocation_version_id',
          'watchlist_item_id',
          'target_weight',
          'quantity',
          'raw_price',
          'price_currency',
          'price_as_of',
          'price_source',
          'fx_to_base',
          'effective_at',
        ]),
      );
      for (final field in const [
        'quantity',
        'raw_price',
        'price_currency',
        'price_as_of',
        'price_source',
        'fx_to_base',
      ]) {
        expect(columns[field], 0, reason: field);
      }
    });

    test(
      'paper action entries keep unresolved money fields nullable',
      () async {
        final result = await db
            .customSelect(
              'PRAGMA table_info(watchlist_simulation_action_entries)',
            )
            .get();
        final columns = {
          for (final row in result)
            row.read<String>('name'): row.read<int>('notnull'),
        };
        expect(
          columns.keys,
          containsAll([
            'source_key',
            'revision_hash',
            'paper_state',
            'cash_per_share',
            'eligible_quantity',
            'gross_amount',
            'withholding_tax_amount',
            'net_amount',
            'base_currency_amount',
          ]),
        );
        for (final field in const [
          'eligible_quantity',
          'gross_amount',
          'withholding_tax_amount',
          'net_amount',
          'base_currency_amount',
        ]) {
          expect(columns[field], 0, reason: field);
        }
      },
    );

    test('observation history is a local-only derived table', () async {
      final result = await db
          .customSelect('PRAGMA table_info(watchlist_simulation_observations)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'simulation_id',
          'observation_day',
          'observed_at',
          'projected_value',
          'weighted_daily_change',
          'priced_weight',
          'missing_quote_weight',
        ]),
      );
      expect(
        columns.intersection({'hlc', 'updated_by_device', 'deleted_at'}),
        isEmpty,
      );
    });
  });

  group('Health metric source identity', () {
    test('health_metrics carries the v79 source_id column', () async {
      final result = await db
          .customSelect('PRAGMA table_info(health_metrics)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(columns, contains('source_id'));
    });
  });

  group('Developer issue capture', () {
    test('is local-only and keeps bounded diagnostic fields', () async {
      final result = await db
          .customSelect('PRAGMA table_info(developer_issues)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>{
          'id',
          'owner_user_id',
          'description',
          'route',
          'domain',
          'app_version',
          'build_number',
          'commit_sha',
          'trace_id',
          'tool_errors_json',
          'screenshot_path',
          'created_at',
          'exported_at',
        }),
      );
      expect(columns, isNot(contains('hlc')));
    });
  });

  group('Typed event evidence index', () {
    test('contains only the canonical event identity columns', () async {
      final result = await db.customSelect('PRAGMA table_info(events)').get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>{
          'id',
          'domain',
          'kind',
          'occurred_at',
          'observed_at',
          'source_family',
          'source_row_id',
          'source_fingerprint',
          'owner_user_id',
          'title',
          'summary',
          'facts_json',
          'entities_json',
          'importance',
          'confidence',
        }),
      );
      expect(
        columns.intersection(<String>{
          'type',
          'timestamp',
          'source',
          'payload_json',
        }),
        isEmpty,
      );
    });
  });

  group('Conversation context checkpoints', () {
    test('stay local-only and preserve source provenance', () async {
      final result = await db
          .customSelect('PRAGMA table_info(conversation_checkpoints)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'session_id',
          'owner_user_id',
          'summary_through_message_id',
          'summary_through_created_at',
          'source_fingerprint',
          'checkpoint_version',
          'source_message_count',
          'payload_json',
          'created_at',
          'updated_at',
        ]),
      );
      expect(columns, isNot(contains('hlc')));
    });
  });

  group('Long-term memory candidates', () {
    test('are local-only and lifecycle constrained', () async {
      final result = await db
          .customSelect('PRAGMA table_info(memory_candidates)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'proposal_id',
          'owner_user_id',
          'target_type',
          'operation',
          'status',
          'target_record_id',
          'applied_record_id',
          'payload_json',
          'created_at',
          'updated_at',
          'decided_at',
          'error_message',
        ]),
      );
      expect(columns, isNot(contains('hlc')));
    });
  });

  group('Personal profile', () {
    test('stores authoritative temporal facts locally', () async {
      final result = await db
          .customSelect('PRAGMA table_info(personal_profile_facts)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'id',
          'owner_user_id',
          'kind',
          'fact_key',
          'value_json',
          'summary',
          'domain_scope',
          'authority',
          'provenance_json',
          'confirmed_at',
          'valid_from',
          'valid_until',
          'supersedes_fact_id',
        ]),
      );
      final confirmedAt = result.singleWhere(
        (row) => row.read<String>('name') == 'confirmed_at',
      );
      expect(confirmedAt.read<int>('notnull'), 1);
      expect(columns, isNot(contains('hlc')));
    });
  });

  group('Investment portfolio tables exist', () {
    for (final table in const [
      'investment_portfolios',
      'portfolio_strategy_templates',
      'rebalance_universes',
      'portfolio_allocation_targets',
      'portfolio_strategy_configs',
      'portfolio_rebalance_groups',
      'portfolio_capital_assignments',
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

    test('capital assignments retain effective-dated history', () async {
      final columns = await db
          .customSelect('PRAGMA table_info(portfolio_capital_assignments)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')).toSet(),
        containsAll(['assigned_at', 'unassigned_at']),
      );

      final indexes = await db
          .customSelect('PRAGMA index_list(portfolio_capital_assignments)')
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')).toSet(),
        contains('idx_portfolio_capital_assignments_history'),
      );
    });
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
    test('market data keeps market identity and FX fetch metadata', () async {
      final fxColumns =
          (await db.customSelect('PRAGMA table_info(fx_rates)').get())
              .map((row) => row.read<String>('name'))
              .toSet();
      final quoteColumns =
          (await db.customSelect('PRAGMA table_info(market_quotes)').get())
              .map((row) => row.read<String>('name'))
              .toSet();
      final historyColumns =
          (await db
                  .customSelect('PRAGMA table_info(market_history_bars)')
                  .get())
              .map((row) => row.read<String>('name'))
              .toSet();
      final searchColumns =
          (await db
                  .customSelect('PRAGMA table_info(market_symbol_searches)')
                  .get())
              .map((row) => row.read<String>('name'))
              .toSet();

      expect(fxColumns, contains('fetched_at'));
      expect(quoteColumns, contains('market'));
      expect(historyColumns, contains('market'));
      expect(searchColumns, contains('market'));
    });

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
      'knowledge_decisions',
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

    test('notes keep a compact capture schema', () async {
      final result = await db
          .customSelect('PRAGMA table_info(knowledge_notes)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(columns, containsAll(<String>['title', 'body_md', 'tags_json']));
      expect(columns, isNot(contains('promoted_to_kind')));
    });

    test('knowledge decisions persist review conditions', () async {
      final result = await db
          .customSelect('PRAGMA table_info(knowledge_decisions)')
          .get();
      expect(
        result.map((row) => row.read<String>('name')).toSet(),
        contains('revisit_conditions_json'),
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
      'execution_plans',
      'execution_actions',
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
      final progressColumns =
          (await db
                  .customSelect('PRAGMA table_info(execution_progress_entries)')
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();

      expect(actionColumns, contains('plan_id'));
      expect(progressColumns, contains('plan_id'));
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

    test('memories require explicit authority and provenance', () async {
      final result = await db.customSelect('PRAGMA table_info(memories)').get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>{
          'role',
          'authority',
          'provenance_json',
          'supersedes_id',
        }),
      );
      expect(columns, isNot(contains('provenance')));
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

    test('agent feedback preserves causal policy fingerprints', () async {
      final result = await db
          .customSelect('PRAGMA table_info(agent_feedback)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll(<String>[
          'artifact_id',
          'kind',
          'life_context_fingerprint',
          'finding_fingerprint',
          'attention_decision_id',
          'created_at',
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
        containsAll(['owner_user_id', 'agent_id', 'enabled', 'updated_at']),
      );
      expect(columns, isNot(contains('notifications_enabled')));
    });
  });

  group('SyncableTable mixin columns', () {
    test('income strategy plans persist composition and guardrails', () async {
      final result = await db
          .customSelect('PRAGMA table_info(income_strategy_plans)')
          .get();
      final columns = result.map((row) => row.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'asset_id',
          'symbol',
          'market',
          'currency',
          'sleeve_intents_json',
          'capital_budget',
          'annual_income_target',
          'max_position_weight',
          'owner_user_id',
          'deleted_at',
          'hlc',
        ]),
      );
    });

    test('LEAPS overlay positions are synced and retain risk inputs', () async {
      final result = await db
          .customSelect('PRAGMA table_info(options_leaps_call_positions)')
          .get();
      final columns = result.map((r) => r.read<String>('name')).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'underlying_asset_id',
          'symbol',
          'option_symbol',
          'expiration_at',
          'entry_debit',
          'current_mark',
          'current_delta',
          'brokerage_account_id',
          'cash_account_id',
          'underlying_market',
          'owner_user_id',
          'deleted_at',
          'hlc',
        ]),
      );
    });

    test('accounts has sync columns (owner_user_id, deleted_at, hlc, updated_at, updated_by_device)', () async {
      final result = await db.customSelect('PRAGMA table_info(accounts)').get();
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
    });
  });
}
