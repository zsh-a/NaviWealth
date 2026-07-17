import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/sync/sync_tables.dart';
import 'connection.dart';
import 'converters.dart';
import 'domain_enums.dart';
import 'event_log_tables.dart';
import 'execution_tables.dart';
import 'health_tables.dart';
import 'knowledge_tables.dart';
import 'local_only_tables.dart';
import 'tables.dart';

part 'app_database_schema_helpers.dart';
part 'app_database.g.dart';

const String defaultDbFileName = 'naviwealth.db';

enum AppDatabaseTransactionScopeErrorCode { inactive, databaseMismatch }

final class AppDatabaseTransactionScopeError implements Exception {
  const AppDatabaseTransactionScopeError(this.code, this.message);

  final AppDatabaseTransactionScopeErrorCode code;
  final String message;

  @override
  String toString() => 'AppDatabaseTransactionScopeError($code): $message';
}

/// Capability proving that code is running inside one active DB transaction.
///
/// Only [AppDatabase.transactionWithScope] can construct this value. It is
/// invalidated as soon as that transaction callback completes.
final class AppDatabaseTransactionScope {
  AppDatabaseTransactionScope._(this._database);

  final AppDatabase _database;
  bool _active = true;

  AppDatabase requireDatabase(AppDatabase database) {
    if (!_active) {
      throw const AppDatabaseTransactionScopeError(
        AppDatabaseTransactionScopeErrorCode.inactive,
        'Transaction scope is no longer active.',
      );
    }
    if (!identical(_database, database)) {
      throw const AppDatabaseTransactionScopeError(
        AppDatabaseTransactionScopeErrorCode.databaseMismatch,
        'Transaction scope belongs to a different AppDatabase.',
      );
    }
    return database;
  }

  void _deactivate() => _active = false;
}

/// Local NaviWealth database.
///
/// The app is now forward-only on the Beancount-style ledger. Historical
/// compatibility migrations for retired pre-ledger tables are intentionally
/// gone; a fresh schema is the source of truth.
@DriftDatabase(
  tables: [
    Users,
    SettingsTable,
    Accounts,
    Assets,
    JournalEntries,
    Postings,
    Prices,
    CorporateActions,
    WatchlistItems,
    OptionsStrategyProfileTable,
    OptionsTradeJournal,
    ApprovedUnderlyings,
    RecurringTransactions,
    Liabilities,
    AmortizationEntries,
    Currencies,
    FxRates,
    Tags,
    TagLinks,
    Categories,
    Budgets,
    Goals,
    Devices,
    OpLogs,
    MarketQuotes,
    MarketHistoryBars,
    MarketSymbolSearches,
    SecuritiesCatalog,
    SecuritiesCatalogMeta,
    // HealthOS (D-2.1): single wide-flat table keyed by `kind`.
    HealthMetrics,
    // KnowledgeOS (`docs/domains/knowledgeos-domain.md` §9): six typed tables —
    // Memory itself reuses the cross-domain `memories` table per §3.
    KnowledgeNotes,
    KnowledgePrinciples,
    KnowledgeAssumptions,
    KnowledgeDecisions,
    KnowledgeConcepts,
    KnowledgeExperiments,
    KnowledgeRoutines,
    // ExecutionOS Action Kernel: projects, personal todos, commitments,
    // progress.
    ExecutionProjects,
    ExecutionActions,
    ExecutionCommitments,
    ExecutionProgressEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({String? dbFileName})
    : super(openAppConnection(dbFileName: dbFileName ?? defaultDbFileName));

  Future<T> transactionWithScope<T>(
    Future<T> Function(AppDatabaseTransactionScope scope) action,
  ) {
    return transaction(() async {
      final scope = AppDatabaseTransactionScope._(this);
      try {
        return await action(scope);
      } finally {
        scope._deactivate();
      }
    });
  }

  @override
  int get schemaVersion => 41;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(this);
      await _createSyncTables(this);
      await _createChatTables(this);
      await _createSecuritiesCatalogFts(this);
      await _createSecuritiesCatalogIndexes(this);
      await _createDomainEventLog(this);
      await _createAiTraceTable(this);
      await _createAiUndoStackTable(this);
      await _createAiTouchedEntitiesTable(this);
      await _createIngestTables(this);
      await _createOptionsOpportunityCache(this);
      await _createRecurringPatternObservations(this);
      await _createMemoryRuntime(this);
      await _createKnowledgeInboxTriage(this);
      await _createAgentRuns(this);
      await _createAgentRuntimeCheckpoints(this);
      await _createAgentArtifacts(this);
      await _createDataMaintenanceRuns(this);
      await _createAgentPreferences(this);
      await _createRebalanceExecutionTables(this);
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2: capture the AI stream's `stop_reason` on chat messages
      // so the timeline can render a "reply was truncated" footer that
      // survives a refresh / app restart instead of flashing for a
      // single frame.
      if (from < 2) {
        await customStatement(
          'ALTER TABLE chat_messages ADD COLUMN stop_reason TEXT',
        );
      }
      // v2 → v3: persist the interleaved text-vs-tool order of the
      // assistant turn. Pre-v3 rows kept text in a single flat string
      // and tool cards in a separate list, which forced the bubble to
      // render "all tools, then all text" — wrong whenever the model
      // narrated between tool calls. Old rows leave this column NULL
      // and fall back to the legacy layout via [displaySegments].
      if (from < 3) {
        await customStatement(
          'ALTER TABLE chat_messages ADD COLUMN text_segments_json TEXT',
        );
      }
      // v3 → v4: reshape the account taxonomy from carrier shape +
      // accounting category into wealth-container category +
      // auto-derived accounting side. The `type` column keeps its name
      // but its enum string values change (brokerage→broker,
      // cryptoWallet→crypto, realEstate/vehicle/other→asset). The
      // `category` column likewise keeps its name but switches from the
      // old user-facing accounting enum (asset/liability/income/expense
      // /equity, all five values) to the auto-derived AccountSide
      // (asset / liability for user containers; income / expense /
      // equity remain only on the seeded system accounts that already
      // store those exact strings, so they pass through unchanged).
      if (from < 4) {
        await customStatement(
          "UPDATE accounts SET type = 'broker' WHERE type = 'brokerage'",
        );
        await customStatement(
          "UPDATE accounts SET type = 'crypto' WHERE type = 'cryptoWallet'",
        );
        await customStatement(
          "UPDATE accounts SET type = 'asset' "
          "WHERE type IN ('realEstate', 'vehicle', 'other')",
        );
        // Other legacy values (cash, bank, liability) keep the same
        // enum string under the new AccountCategory and need no
        // rewrite. The category column requires no rewrite for system
        // accounts (income/expense/equity) and for user accounts whose
        // legacy value (asset/liability) maps 1:1 to AccountSide.
      }
      // v4 → v5: persist AI transparency traces + ai_chat undo stack.
      // Both surfaces previously lived only in process memory; survival
      // across restarts is needed for: (a) the AI transparency audit
      // page (recentAiTraces), (b) the undo stack so toolings the user
      // confirmed minutes ago still rollback after a reload.
      if (from < 5) {
        await _createAiTraceTable(this);
        await _createAiUndoStackTable(this);
      }
      // v5 → v6: side-table that records "this entity was touched by
      // an AI proposal" so detail pages can surface a subtle sparkle
      // prefix. Side table > new column on entity tables —
      // domain models stay clean and the migration is additive only.
      if (from < 6) {
        await _createAiTouchedEntitiesTable(this);
      }
      // v6 → v7: persist v2 AI SSE side channels. Reasoning text stays
      // separate from assistant-visible content, and usage is stored as
      // compact JSON for debug surfaces.
      if (from < 7) {
        await customStatement(
          'ALTER TABLE chat_messages ADD COLUMN reasoning_text TEXT',
        );
        await customStatement(
          'ALTER TABLE chat_messages ADD COLUMN usage_json TEXT',
        );
      }
      // v7 → v8: Layer 4 ingest pipeline (§5.10.10 / S5a). Parsed-but-
      // unconfirmed transactions live in `ingest_drafts` — a local-only,
      // never-synced staging table. Drafts do NOT enter journal_entries
      // / OpLog until the user confirms; this is what makes §4.2's
      // "draft gate" hold by construction. `ingest_attachments` is
      // created now (schema-ready) but only wired by S5b/S5c when the
      // Vision path actually has a blob to stage.
      if (from < 8) {
        await _createIngestTables(this);
      }
      // v8 -> v9: synced recurring transaction templates. Forecasted
      // occurrences stay ephemeral; only the user-authored recurrence
      // definition joins the sync protocol.
      if (from < 9) {
        await m.createTable(recurringTransactions);
        await _createRecurringTransactionIndexes(this);
      }
      // v9 -> v10: synced investment watchlist with local price alerts.
      if (from < 10) {
        await m.createTable(watchlistItems);
        await _createWatchlistIndexes(this);
      }
      // v10 -> v11: Options Income Planner P0 — synced user-stance tables.
      // The opportunity cache stays local-only and is created on demand by
      // the scanner; see docs/domains/options-income.md §6.2.
      if (from < 11) {
        await m.createTable(optionsStrategyProfileTable);
        await m.createTable(approvedUnderlyings);
        await _createOptionsIncomeIndexes(this);
      }
      // v11 -> v12: Options Income Planner P1 — local-only opportunity
      // cache table populated by the scanner (`docs/domains/options-income.md`
      // §6.2). Never enters the sync OpLog.
      if (from < 12) {
        await _createOptionsOpportunityCache(this);
      }
      // v12 -> v13: Options Income Planner P3 — synced trade journal.
      if (from < 13) {
        await m.createTable(optionsTradeJournal);
        await _createOptionsTradeJournalIndexes(this);
      }
      // v13 → v14: rebuild `op_outbox` as a pure dirty-pointer log.
      // SyncBackfill (version bumped) re-enqueues every local row,
      // so dropping the old outbox loses no pending change.
      if (from < 14) {
        await customStatement('DROP TABLE IF EXISTS sync_errors');
        await customStatement('DROP TABLE IF EXISTS op_outbox');
        await customStatement(createOpOutbox);
        await customStatement(createOpOutboxIndex);
      }
      // v14 → v15: monthly category budgets. One
      // row per (categoryId, periodMonth). Sync rides on the row-state
      // protocol like every other SyncableTable — no special wiring.
      if (from < 15) {
        await m.createTable(budgets);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_budgets_owner_hlc '
          'ON budgets(owner_user_id, hlc)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_budgets_category_period '
          'ON budgets(category_id, period_month)',
        );
      }
      // v15 → v16: Memory Layer persistent vector store
      // (`docs/architecture/lifeos-shell.md` §6, D-1.7). Local-only — derived from
      // domain rows, re-indexable, never enters sync.
      if (from < 16) {
        await _createMemoryDocuments(this);
      }
      // v16 → v17: Memory Runtime split (`docs/architecture/lifeos-shell.md` §6,
      // D-1.7b). memory_documents → memories (typed) + memory_embeddings
      // (vectors keyed by memory_id) + events (cross-domain event log).
      // The v16 table held derived data only, so dropping it is safe —
      // indexers re-populate from source-of-truth tables at next boot.
      if (from < 17) {
        await customStatement('DROP TABLE IF EXISTS memory_documents');
        await _createMemoryRuntime(this);
      }
      // v17 → v18: HealthOS domain skeleton (`docs/domains/healthos-domain.md`
      // §3, D-2.1). Single flat `health_metrics` table keyed by `kind`.
      // No data yet — adapters land in D-2.2; the table is just the
      // sync target and AI tool read surface.
      if (from < 18) {
        await m.createTable(healthMetrics);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_kind_captured '
          'ON health_metrics(owner_user_id, kind, captured_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_hlc '
          'ON health_metrics(owner_user_id, hlc)',
        );
      }
      // v18 → v19: KnowledgeOS domain skeleton
      // (`docs/domains/knowledgeos-domain.md` §9). Six typed tables — Memory
      // itself reuses the cross-domain `memories` table per §3, so no
      // new Memory schema. Gated at runtime by the Knowledge opt-in;
      // creating the tables unconditionally is fine because they stay
      // empty until the first write.
      if (from < 19) {
        await m.createTable(knowledgeNotes);
        await m.createTable(knowledgePrinciples);
        await m.createTable(knowledgeAssumptions);
        await m.createTable(knowledgeDecisions);
        await m.createTable(knowledgeConcepts);
        await m.createTable(knowledgeExperiments);
        for (final stmt in knowledgeIndexStmts) {
          if (stmt.contains('knowledge_routines')) continue;
          await customStatement(stmt);
        }
      }
      // v19 → v20: KnowledgeOS inbox triage side-table
      // (`docs/domains/knowledgeos-domain.md` §7 + §5 异步 triage flow).
      // Local-only, never-sync — InboxTriageAgent uses it to skip
      // already-proposed notes and the Review tab reads pending
      // envelopes from it.
      if (from < 20) {
        await _createKnowledgeInboxTriage(this);
      }
      // v20 → v21: KnowledgeOS routines (`docs/domains/knowledgeos-domain.md`
      // §3 + §9). Recurring user-defined reminders ("港卡每 6 个月做一次
      //活跃交易") — a typed row that records cadence + last-done state
      // so RoutineDueAgent can advance `next_due_at` reliably.
      if (from < 21) {
        await m.createTable(knowledgeRoutines);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_knowledge_routines_owner_hlc '
          'ON knowledge_routines(owner_user_id, hlc)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_knowledge_routines_due '
          'ON knowledge_routines(owner_user_id, status, next_due_at) '
          'WHERE deleted_at IS NULL',
        );
      }
      // v21 → v22: KnowledgeOS dedupe pointer (`docs/domains/knowledgeos-domain.md`
      // §15.3). `merged_into_id` on Notes + Concepts records where a
      // soft-deleted duplicate's content went after `propose_merge`.
      // Additive nullable columns — no rewrite of existing rows.
      if (from < 22) {
        await _addColumnIfMissing(
          this,
          table: 'knowledge_notes',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'knowledge_concepts',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
      }
      // v22 → v23: extend the dedupe pointer to the remaining merge-able
      // KnowledgeOS types (§15.3 P1). Principle / Assumption / Decision merges
      // also re-point inbound references; Experiment merges only tombstone.
      // Additive nullable columns — no rewrite of existing rows.
      if (from < 23) {
        await _addColumnIfMissing(
          this,
          table: 'knowledge_principles',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'knowledge_assumptions',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'knowledge_decisions',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'knowledge_experiments',
          column: 'merged_into_id',
          definition: 'TEXT',
        );
      }
      // v23 -> v24: Income Planner journal rows can optionally carry the
      // minimal accounting context needed to mirror option events into the
      // forward ledger. Old rows keep these fields NULL and remain
      // review-only.
      if (from < 24) {
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'brokerage_account_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'cash_account_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'underlying_market',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'strike_price',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'contract_size',
          definition: 'INTEGER',
        );
      }
      // v24 -> v25: local analytical observation log for recurring
      // pattern detector output. This is derived device state, so it is
      // intentionally local-only; `subscription_changes` reads it to compare
      // old vs new stable subscription prices across app sessions.
      if (from < 25) {
        await _createRecurringPatternObservations(this);
      }
      // v25 -> v26: persist the current long-running AI task descriptor
      // on the streaming assistant message. This lets chat surfaces
      // survive a rebuild/reload while still clearing the descriptor when
      // the turn completes.
      if (from < 26) {
        await customStatement(
          'ALTER TABLE chat_messages ADD COLUMN progress_json TEXT',
        );
      }
      // v26 -> v27: persisted FinanceOS corporate actions. Ledger rows are
      // the accounting materialisation; this table keeps the business event
      // queryable for forecasts, timelines, sync, and backup.
      if (from < 27) {
        await m.createTable(corporateActions);
        await _createCorporateActionIndexes(this);
      }
      // v27 -> v28: ExecutionOS Action Kernel. These three tables form the
      // reusable personal todo / commitment / progress layer; Project and
      // Milestone can later attach without changing the first-order action
      // model.
      if (from < 28) {
        await m.createTable(executionProjects);
        await m.createTable(executionActions);
        await m.createTable(executionCommitments);
        await m.createTable(executionProgressEntries);
        await _createExecutionIndexes(this);
      }
      // v28 -> v29: lightweight projects for ExecutionOS. Actions,
      // commitments, and progress entries keep their first-order shape and
      // gain an optional `project_id` roll-up rather than forking into a
      // separate project-task model.
      if (from >= 28 && from < 29) {
        await m.createTable(executionProjects);
        await _addColumnIfMissing(
          this,
          table: 'execution_actions',
          column: 'project_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'execution_commitments',
          column: 'project_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'execution_progress_entries',
          column: 'project_id',
          definition: 'TEXT',
        );
        await _createExecutionIndexes(this);
      }
      // v29 -> v30: local-only lifecycle state for scheduled LifeOS agents.
      // Agent state belongs to the Dart agent framework, not the native
      // runtime; this table lets schedule gates survive app restarts without
      // syncing derived device state.
      if (from < 30) {
        await _createAgentRuns(this);
      }
      // v30 -> v31: local-only user-visible outputs for the unified agent
      // experience. These are derived briefing/review/alert artifacts, not
      // synced source-of-truth rows.
      if (from < 31) {
        await _addColumnIfMissing(
          this,
          table: 'agent_runs',
          column: 'artifact_id',
          definition: 'TEXT',
        );
        await _createAgentArtifacts(this);
      }
      // v31 -> v32: local per-user agent preferences. These control
      // scheduling/notification behavior but remain local product state.
      if (from < 32) {
        await _createAgentPreferences(this);
      }
      // v32 -> v33: retain the runtime transparency trace associated with a
      // product-level agent run. Artifacts already have `trace_id`; this keeps
      // lifecycle/history surfaces linked to the same local trace.
      if (from < 33) {
        await _addColumnIfMissing(
          this,
          table: 'agent_runs',
          column: 'trace_id',
          definition: 'TEXT',
        );
      }
      // v33 -> v34: local visibility state for unified agent artifacts.
      // Dismiss/snooze hides the current result without deleting history.
      if (from < 34) {
        await _addColumnIfMissing(
          this,
          table: 'agent_artifacts',
          column: 'dismissed_at',
          definition: 'INTEGER',
        );
        await _addColumnIfMissing(
          this,
          table: 'agent_artifacts',
          column: 'snoozed_until',
          definition: 'INTEGER',
        );
      }
      // v34 -> v35: persist ingest recovery after a ledger write succeeds but
      // its draft lifecycle update cannot be finalized. The review page can
      // reconstruct a finalize-only action after navigation or restart,
      // preventing the same draft from being applied twice.
      if (from < 35) {
        // Some early/partial fixtures can report a post-v8 user_version
        // without the local-only side table. Recreate it idempotently before
        // adding columns so every supported upgrade path remains bootable.
        await _createIngestTables(this);
        await _addColumnIfMissing(
          this,
          table: 'ingest_drafts',
          column: 'recovery_kind',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'ingest_drafts',
          column: 'recovery_apply_state_json',
          definition: 'TEXT',
        );
      }
      // v35 -> v36: local-only durable rebalance execution sessions. The
      // lease/state rows coordinate resumable apply and Undo work on this
      // device; ledger truth continues to sync through its normal tables.
      if (from < 36) {
        await _createRebalanceExecutionTables(this);
      }
      // v36 -> v37: persist classified execution failures separately from
      // bounded developer diagnostics so retry/edit policy survives restart.
      if (from < 37) {
        await _addColumnIfMissing(
          this,
          table: 'rebalance_execution_items',
          column: 'failure_code',
          definition: 'TEXT',
        );
        await customStatement(
          'UPDATE rebalance_execution_items '
          'SET failure_code = CASE state '
          "  WHEN 'applyFailed' THEN 'legacyApplyFailure' "
          "  WHEN 'undoFailed' THEN 'legacyUndoFailure' "
          "  WHEN 'recoveryBlocked' THEN 'recoveryCorrupt' "
          '  ELSE NULL END, '
          "error = CASE WHEN state IN ('applyFailed', 'undoFailed', "
          "  'recoveryBlocked') THEN substr(error, 1, 512) ELSE NULL END",
        );
        await _createRebalanceExecutionIssueTriggers(this);
      }
      // v37 -> v38: owner-scoped optimistic lifecycle writes and a durable
      // pre-invocation reservation for ingest confirmation. A confirming row
      // whose invocation started is deliberately never reclaimed.
      if (from < 38) {
        await _createIngestTables(this);
        await _addColumnIfMissing(
          this,
          table: 'ingest_drafts',
          column: 'revision',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
        await _addColumnIfMissing(
          this,
          table: 'ingest_drafts',
          column: 'operation_token',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'ingest_drafts',
          column: 'invocation_started',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
      }
      // v38 -> v39: app-owned durable checkpoints for the embedded Rust
      // agent-runtime loop. Snapshot and effect-journal rows are local-only;
      // product run history remains in `agent_runs`.
      if (from < 39) {
        await _createAgentRuntimeCheckpoints(this);
      }
      // v39 -> v40: local data-maintenance audit records and automatic
      // retention bookkeeping.
      if (from < 40) {
        await _createDataMaintenanceRuns(this);
      }
      // v40 -> v41: typed metrics and methodology for user-facing agent
      // results. Agent artifacts are local and regenerable, so the new
      // presentation envelope starts empty for existing rows.
      if (from < 41) {
        await _createAgentArtifacts(this);
        await _addColumnIfMissing(
          this,
          table: 'agent_artifacts',
          column: 'presentation_json',
          definition: "TEXT NOT NULL DEFAULT '{}'",
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
