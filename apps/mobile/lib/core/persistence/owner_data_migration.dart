import 'package:drift/drift.dart';

import '../sync/drift_sync_storage.dart';
import 'app_database.dart';

/// Ownership changes are a data lifecycle operation, independent of whether a
/// table is synced or backed up. Source rows, confirmed personal data and
/// readable history move together; resumable effects are invalidated because
/// their embedded permissions and confirmations belong to the old identity.
enum OwnerDataMigrationPolicy { transfer, invalidate }

class OwnerDataTable {
  const OwnerDataTable(
    this.table, {
    this.policy = OwnerDataMigrationPolicy.transfer,
    this.identityColumn,
  });

  final String table;
  final OwnerDataMigrationPolicy policy;

  /// A singleton whose primary key is the owner itself, rather than a stable
  /// entity id. Dirty pointers and opaque sync fields move to the new key too.
  final String? identityColumn;
}

/// Explicit lifecycle inventory. The schema coverage test fails whenever a new
/// owner-bearing table has no policy here. Do not derive this from SyncBackfill:
/// confirmed Memory/Profile, recurring records and chat are local-only truth.
const kOwnerDataTables = <OwnerDataTable>[
  OwnerDataTable('accounts'),
  OwnerDataTable('amortization_entries'),
  OwnerDataTable('assets'),
  OwnerDataTable('budgets'),
  OwnerDataTable('categories'),
  OwnerDataTable('corporate_actions'),
  OwnerDataTable('dca_plans'),
  OwnerDataTable('devices'),
  OwnerDataTable('execution_actions'),
  OwnerDataTable('execution_plans'),
  OwnerDataTable('execution_progress_entries'),
  OwnerDataTable('financial_decisions'),
  OwnerDataTable('financial_monthly_closes'),
  OwnerDataTable('financial_reconciliations'),
  OwnerDataTable('financial_signals'),
  OwnerDataTable('fire_plans', identityColumn: 'user_id'),
  OwnerDataTable('goals'),
  OwnerDataTable('health_check_ins'),
  OwnerDataTable('health_meals'),
  OwnerDataTable('health_meal_photos'),
  OwnerDataTable('health_metrics'),
  OwnerDataTable('income_strategy_plans'),
  OwnerDataTable('investment_portfolios'),
  OwnerDataTable('journal_entries'),
  OwnerDataTable('knowledge_decisions'),
  OwnerDataTable('knowledge_notes'),
  OwnerDataTable('knowledge_relations'),
  OwnerDataTable('liabilities'),
  OwnerDataTable('options_leaps_call_positions'),
  OwnerDataTable('options_strategy_profile', identityColumn: 'user_id'),
  OwnerDataTable('options_trade_journal'),
  OwnerDataTable('portfolio_allocation_targets'),
  OwnerDataTable('portfolio_capital_assignments'),
  OwnerDataTable('portfolio_rebalance_groups'),
  OwnerDataTable('portfolio_strategy_configs'),
  OwnerDataTable('portfolio_strategy_templates'),
  OwnerDataTable('postings'),
  OwnerDataTable('prices'),
  OwnerDataTable('rebalance_universes'),
  OwnerDataTable('recurring_transactions'),
  OwnerDataTable('settings', identityColumn: 'user_id'),
  OwnerDataTable('tag_links'),
  OwnerDataTable('tags'),
  OwnerDataTable('users'),
  OwnerDataTable('watchlist_collection_members'),
  OwnerDataTable('watchlist_collections'),
  OwnerDataTable('watchlist_items'),
  OwnerDataTable('watchlist_simulation_action_entries'),
  OwnerDataTable('watchlist_simulation_allocation_heads'),
  OwnerDataTable('watchlist_simulation_allocation_versions'),
  OwnerDataTable('watchlist_simulation_holding_versions'),
  OwnerDataTable('watchlist_simulations'),

  // User-confirmed local data and historical evidence preserve ids and links.
  OwnerDataTable('personal_profile_facts'),
  OwnerDataTable('memories'),
  OwnerDataTable('events'),
  OwnerDataTable('chat_sessions'),
  OwnerDataTable('chat_messages'),
  OwnerDataTable('agent_artifacts'),
  OwnerDataTable('agent_feedback'),
  OwnerDataTable('agent_findings'),
  OwnerDataTable('agent_preferences'),
  OwnerDataTable('agent_runs'),
  OwnerDataTable('attention_decisions'),
  OwnerDataTable('scheduled_agent_tasks'),
  OwnerDataTable('ai_touched_entities'),
  OwnerDataTable('ai_traces'),
  OwnerDataTable('data_maintenance_runs'),
  OwnerDataTable('developer_issues'),
  OwnerDataTable('op_logs'),
  OwnerDataTable('dividend_forecast_snapshots'),
  OwnerDataTable('runway_forecast_snapshots'),
  OwnerDataTable('recurring_pattern_observations'),
  OwnerDataTable('watchlist_simulation_observations'),
  OwnerDataTable('sync_row_extras'),

  // These caches either embed the old identity or can resume a business effect.
  OwnerDataTable('agent_runtime_chat_snapshots', policy: _invalidate),
  OwnerDataTable('agent_runtime_checkpoints', policy: _invalidate),
  OwnerDataTable('ai_undo_stack', policy: _invalidate),
  OwnerDataTable('conversation_checkpoints', policy: _invalidate),
  OwnerDataTable('memory_candidates', policy: _invalidate),
  OwnerDataTable('ingest_attachments', policy: _invalidate),
  OwnerDataTable('ingest_drafts', policy: _invalidate),
  OwnerDataTable('rebalance_execution_items', policy: _invalidate),
  OwnerDataTable('rebalance_execution_sessions', policy: _invalidate),
  OwnerDataTable('options_opportunity_cache', policy: _invalidate),
];

const _invalidate = OwnerDataMigrationPolicy.invalidate;

class OwnerDataMigration {
  const OwnerDataMigration(this._db);

  final AppDatabase _db;
  static const _commitMarkerKey = 'auth.owner_transfer.committed';

  /// Only a random transfer id enters SQLite; credential snapshots stay secure.
  Future<bool> didCommit(String transferId) async {
    final row = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [const Variable(_commitMarkerKey)],
        )
        .getSingleOrNull();
    return row?.read<String>('value') == transferId;
  }

  Future<void> clearCommitMarker(String transferId) => _db.customStatement(
    'DELETE FROM sync_meta WHERE key = ? AND value = ?',
    [_commitMarkerKey, transferId],
  );

  /// Caller must quiesce Sync before entering. SQLite uniqueness constraints
  /// deliberately reject conflicting destination data and roll back every
  /// transferred row, invalidation and dirty-pointer change together.
  Future<int> transfer({
    required String from,
    required String to,
    String? transferId,
    Future<void> Function()? commitIdentity,
  }) async {
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('Owner ids must be non-empty');
    }
    if (from == to) return 0;
    return _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      var transferred = 0;
      for (final entry in kOwnerDataTables) {
        if (entry.policy == OwnerDataMigrationPolicy.invalidate) {
          await _db.customStatement(
            'DELETE FROM ${entry.table} WHERE owner_user_id = ?',
            [from],
          );
          continue;
        }
        final identityColumn = entry.identityColumn;
        if (identityColumn != null) {
          await _db.customStatement(
            'UPDATE op_outbox SET row_id = ? WHERE table_name = ? '
            'AND row_id IN (SELECT $identityColumn FROM ${entry.table} '
            'WHERE owner_user_id = ?)',
            [to, entry.table, from],
          );
          await _db.customStatement(
            'UPDATE sync_row_extras SET row_id = ? '
            'WHERE owner_user_id = ? AND table_name = ?',
            [to, from, entry.table],
          );
        }
        transferred += await _db.customUpdate(
          'UPDATE ${entry.table} SET owner_user_id = ?'
          '${identityColumn == null ? '' : ', $identityColumn = ?'} '
          'WHERE owner_user_id = ?',
          variables: <Variable<Object>>[
            Variable.withString(to),
            if (identityColumn != null) Variable.withString(to),
            Variable.withString(from),
          ],
          updates: _db.allTables
              .where((table) => table.actualTableName == entry.table)
              .toSet(),
        );
      }
      // Vectors reference stable memory ids and follow the transferred owner
      // through their parent; audit actors keep their historical identity.
      await clearOwnerSyncProgress(_db, from);
      await clearOwnerSyncProgress(_db, to);
      await _clearBackfillMarkers(from);
      await _clearBackfillMarkers(to);
      if (transferId != null) {
        await _db.customStatement(
          'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [_commitMarkerKey, transferId],
        );
      }
      await commitIdentity?.call();
      return transferred;
    });
  }

  Future<void> _clearBackfillMarkers(String owner) => _db.customStatement(
    'DELETE FROM sync_meta WHERE key IN ('
    'SELECT key FROM sync_meta WHERE key LIKE ? ESCAPE \'\\\')',
    ['sync.backfill.%.${_escapeLike(owner)}.%'],
  );
}

String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
