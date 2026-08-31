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
    OptionsLeapsCallPositions,
    IncomeStrategyPlans,
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
    InvestmentPortfolios,
    PortfolioStrategyTemplates,
    RebalanceUniverses,
    PortfolioAllocationTargets,
    PortfolioStrategyConfigs,
    PortfolioRebalanceGroups,
    PortfolioCapitalAssignments,
    FirePlans,
    FinancialDecisions,
    DcaPlans,
    FinancialSignals,
    FinancialMonthlyCloses,
    FinancialReconciliations,
    Devices,
    OpLogs,
    MarketQuotes,
    MarketHistoryBars,
    MarketSymbolSearches,
    MarketCorporateActionCandidates,
    MarketCorporateActionFetchStates,
    SecuritiesCatalog,
    SecuritiesCatalogMeta,
    // HealthOS (D-2.1): single wide-flat table keyed by `kind`.
    HealthMetrics,
    // KnowledgeOS: notes, decisions, and explicit relations.
    KnowledgeNotes,
    KnowledgeDecisions,
    KnowledgeRelations,
    // ExecutionOS Action Kernel: plans, personal actions, and updates.
    ExecutionPlans,
    ExecutionActions,
    ExecutionProgressEntries,
    WatchlistCollections,
    WatchlistCollectionMembers,
    WatchlistSimulations,
    WatchlistSimulationPositions,
    WatchlistSimulationAllocationVersions,
    WatchlistSimulationHoldingVersions,
    WatchlistSimulationActionEntries,
    WatchlistSimulationObservations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({String? dbFileName, String? encryptionKey})
    : super(
        openAppConnection(
          dbFileName: dbFileName ?? defaultDbFileName,
          encryptionKey: encryptionKey,
        ),
      );

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
  int get schemaVersion => 88;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(this);
      await _createMarketCorporateActionIndexes(this);
      await _createPortfolioIndexes(this);
      await _createSyncTables(this);
      await _createChatTables(this);
      await _createConversationCheckpoints(this);
      await _createMemoryCandidates(this);
      await _createPersonalProfile(this);
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
      await _createAgentRuns(this);
      await _createAgentRuntimeCheckpoints(this);
      await _createAgentRuntimeChatSnapshots(this);
      await _createAgentArtifacts(this);
      await _createAgentFindings(this);
      await _createAgentFeedback(this);
      await _createAttentionDecisions(this);
      await _createDeveloperIssues(this);
      await _createDataMaintenanceRuns(this);
      await _createAgentPreferences(this);
      await _createRebalanceExecutionTables(this);
      await _createFinancePlanningIndexes(this);
      await _createForecastSnapshots(this);
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
      // v27 -> v28: ExecutionOS action kernel with plans, actions, and
      // progress as first-order rows.
      if (from < 28) {
        await m.createTable(executionPlans);
        await m.createTable(executionActions);
        await m.createTable(executionProgressEntries);
        await _createExecutionIndexes(this);
      }
      // v28 -> v29: add the plan roll-up to actions and progress entries.
      if (from >= 28 && from < 29) {
        await m.createTable(executionPlans);
        await _addColumnIfMissing(
          this,
          table: 'execution_actions',
          column: 'plan_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'execution_progress_entries',
          column: 'plan_id',
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
      // v41 -> v42: durable chat-turn snapshots and tool dispatch journals
      // allow Android process recovery without replaying uncertain writes.
      if (from < 42) {
        await _createAgentRuntimeChatSnapshots(this);
      }
      // v42 -> v43: chat session pin/archive flags for history management.
      if (from < 43) {
        // Partial legacy fixtures and damaged-but-recoverable installs may not
        // have chat tables yet. Recreate the idempotent base before altering
        // columns so an unrelated optional subsystem cannot block DB startup.
        await _createChatSessionsTable(this);
        await _addColumnIfMissing(
          this,
          table: 'chat_sessions',
          column: 'pinned',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
        await _addColumnIfMissing(
          this,
          table: 'chat_sessions',
          column: 'archived',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 44) {
        await m.createTable(financialDecisions);
        await m.createTable(financialSignals);
        await m.createTable(financialMonthlyCloses);
        await _createForecastSnapshots(this);
      }
      if (from < 45) {
        // Financial Close 2.0 intentionally replaces the manual checklist
        // shape with evidence-derived state. The old rows contain no
        // authoritative financial facts, so there is nothing to migrate.
        await m.deleteTable('financial_monthly_closes');
        await m.createTable(financialMonthlyCloses);
        await m.createTable(financialReconciliations);
        await _addColumnIfMissing(
          this,
          table: 'financial_decisions',
          column: 'review_evidence_json',
          definition: 'TEXT',
        );
        await _createFinancePlanningIndexes(this);
      }
      if (from < 46) {
        await _addColumnIfMissing(
          this,
          table: 'financial_signals',
          column: 'action_id',
          definition: 'TEXT',
        );
      }
      if (from < 47) {
        await _addColumnIfMissing(
          this,
          table: 'financial_signals',
          column: 'revalidation_status',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'financial_signals',
          column: 'revalidated_at',
          definition: 'INTEGER',
        );
        await _addColumnIfMissing(
          this,
          table: 'financial_signals',
          column: 'action_completed_at',
          definition: 'INTEGER',
        );
      }
      if (from < 48) {
        await _createForecastSnapshots(this);
      }
      if (from < 49) {
        // Portfolio architecture is created by the forward-only v66 reset.
      }
      if (from < 52) {
        await m.createTable(dcaPlans);
        await _addColumnIfMissing(
          this,
          table: 'financial_decisions',
          column: 'action_id',
          definition: 'TEXT',
        );
        await _createFinancePlanningIndexes(this);
      }
      // v52 -> v53: categories become the FinanceOS expense-category SSOT.
      // This intentionally discards the retired account-id-backed budget
      // representation. Fresh category rows are seeded after startup.
      if (from < 53) {
        await m.deleteTable('budgets');
        await m.deleteTable('categories');
        await m.createTable(categories);
        await m.createTable(budgets);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_budgets_category_period '
          'ON budgets(category_id, period_month)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_categories_owner_active '
          'ON categories(owner_user_id, archived, sort_order)',
        );
      }
      // v53 -> v54: local, structured checkpoints preserve the omitted
      // prefix of long conversations without turning summaries into synced
      // memory or polluting the persisted chat transcript.
      if (from < 54) {
        await _createConversationCheckpoints(this);
      }
      // v54 -> v55: models may stage a long-term-memory change, but only a
      // user-confirmed candidate is allowed to materialize in `memories`.
      if (from < 55) {
        await _createMemoryCandidates(this);
      }
      // v55 -> v56: durable chat turns may pause on a provider-neutral
      // interaction envelope without retaining pending tool dispatches.
      if (from < 56) {
        await _upgradeAgentRuntimeChatSnapshotsForInteractions(this);
      }
      if (from < 58) {
        await _createAgentFindings(this);
      }
      // v58 -> v59: make options journal rows sufficient for lifecycle and
      // net-return review. Quantity is distinct from the contract multiplier;
      // expiration drives due-state UI; fees keep reported P&L honest.
      if (from < 59) {
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'expiration_at',
          definition: 'INTEGER',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'fees',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_trade_journal',
          column: 'contract_quantity',
          definition: 'INTEGER NOT NULL DEFAULT 1',
        );
      }
      // v59 -> v60: independent long-dated call overlay for Wheel portfolios.
      if (from < 60) {
        await m.createTable(optionsLeapsCallPositions);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_options_leaps_owner_opened '
          'ON options_leaps_call_positions(owner_user_id, opened_at DESC) '
          'WHERE deleted_at IS NULL',
        );
      }
      // v60 -> v61: composable per-asset income strategy intent.
      if (from < 61) {
        await _addColumnIfMissing(
          this,
          table: 'options_leaps_call_positions',
          column: 'cash_account_id',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          this,
          table: 'options_leaps_call_positions',
          column: 'underlying_market',
          definition: 'TEXT',
        );
        await m.createTable(incomeStrategyPlans);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_income_strategy_plans_owner '
          'ON income_strategy_plans(owner_user_id, symbol) '
          'WHERE deleted_at IS NULL',
        );
      }
      // v61 -> v62: replace the closed three-sleeve plan shape with an open
      // module-intent document. Plans are derived user configuration and the
      // product explicitly drops compatibility with the v61 experiment.
      if (from < 62) {
        await m.deleteTable('income_strategy_plans');
        await m.createTable(incomeStrategyPlans);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_income_strategy_plans_owner '
          'ON income_strategy_plans(owner_user_id, symbol) '
          'WHERE deleted_at IS NULL',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_income_strategy_plans_asset '
          'ON income_strategy_plans(owner_user_id, asset_id) '
          'WHERE deleted_at IS NULL',
        );
      }
      // v62 -> v63: approved-underlying intent now lives inside the Wheel
      // module section of income_strategy_plans. The global profile now keeps
      // only scanner behavior; per-underlying exposure belongs to that Wheel
      // intent. Both experimental tables are intentionally rebuilt.
      if (from < 63) {
        await m.deleteTable('approved_underlyings');
        await m.deleteTable('options_strategy_profile');
        await m.createTable(optionsStrategyProfileTable);
        await m.deleteTable('options_trade_journal');
        await m.createTable(optionsTradeJournal);
        await _createOptionsTradeJournalIndexes(this);
        await m.deleteTable('options_leaps_call_positions');
        await m.createTable(optionsLeapsCallPositions);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_options_leaps_owner_opened '
          'ON options_leaps_call_positions(owner_user_id, opened_at DESC) '
          'WHERE deleted_at IS NULL',
        );
      }
      // v63 -> v64: strategy groups — plans may join a cross-underlying
      // group (e.g. TQQQ wheel funding a QQQ LEAPS call). Nullable columns;
      // ungrouped plans keep their implicit per-asset behaviour. Skipped
      // when the v62 step already recreated the table with the current
      // schema (from < 62), which would make addColumn a duplicate.
      if (from >= 62 && from < 64) {
        await m.addColumn(incomeStrategyPlans, incomeStrategyPlans.groupId);
        await m.addColumn(incomeStrategyPlans, incomeStrategyPlans.groupLabel);
      }
      // v64 -> v65: buy-side LEAPS scan lane. Profile gains LEAPS window /
      // delta / liquidity thresholds (defaults = balanced preset; skipped
      // when the v63 step already recreated the table with them). The
      // opportunity cache is derived data — drop and let the local-only
      // DDL recreate it with the leaps_metrics_json column.
      if (from >= 63 && from < 65) {
        final t = optionsStrategyProfileTable;
        await m.addColumn(t, t.leapsMinDte);
        await m.addColumn(t, t.leapsMaxDte);
        await m.addColumn(t, t.leapsDeltaMin);
        await m.addColumn(t, t.leapsDeltaMax);
        await m.addColumn(t, t.leapsMaxSpreadPct);
        await m.addColumn(t, t.leapsMinOpenInterest);
      }
      if (from < 65) {
        await customStatement('DROP TABLE IF EXISTS options_opportunity_cache');
        await _createOptionsOpportunityCache(this);
      }
      // v65 -> v66: replace the closed portfolio strategy fields and
      // lot-only membership with open strategy modules, capital-owning
      // rebalance groups, and typed lot/cash capital assignments. This is an
      // intentional forward-only reset of the experimental portfolio model.
      if (from < 66) {
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_capital_assignments',
        );
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_strategy_configs',
        );
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_rebalance_groups',
        );
        await customStatement('DROP TABLE IF EXISTS portfolio_lot_memberships');
        await customStatement('DROP TABLE IF EXISTS investment_portfolios');
        await m.createTable(investmentPortfolios);
        await m.createTable(portfolioStrategyConfigs);
        await m.createTable(portfolioRebalanceGroups);
        await m.createTable(portfolioCapitalAssignments);
      }
      // v66 -> v67: unified strategy catalog and three-level capital tree.
      // Portfolio planning is intentionally reset instead of carrying a
      // compatibility layer for the short-lived v66 model.
      if (from < 67) {
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_capital_assignments',
        );
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_strategy_configs',
        );
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_rebalance_groups',
        );
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_allocation_targets',
        );
        await customStatement('DROP TABLE IF EXISTS rebalance_universes');
        await customStatement(
          'DROP TABLE IF EXISTS portfolio_strategy_templates',
        );
        await customStatement('DROP TABLE IF EXISTS investment_portfolios');
        await m.createTable(investmentPortfolios);
        await m.createTable(portfolioStrategyTemplates);
        await m.createTable(rebalanceUniverses);
        await m.createTable(portfolioAllocationTargets);
        await m.createTable(portfolioStrategyConfigs);
        await m.createTable(portfolioRebalanceGroups);
        await m.createTable(portfolioCapitalAssignments);
        await _createPortfolioIndexes(this);
      }
      // v67 -> v68: strategy kinds are templates, not instance identities.
      // Rebuild the two tables whose uniqueness constraints previously made
      // tombstoned rows block repeated strategy and assignment instances.
      if (from >= 67 && from < 68) {
        await m.alterTable(TableMigration(portfolioStrategyConfigs));
        await m.alterTable(TableMigration(portfolioCapitalAssignments));
      }
      // v68 -> v69: capital ownership is an effective-dated interval.
      // Closing and transferring assignments now preserves historical
      // portfolio membership instead of rewriting the past.
      if (from >= 68 && from < 69) {
        await m.addColumn(
          portfolioCapitalAssignments,
          portfolioCapitalAssignments.unassignedAt,
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_portfolio_capital_assignments_history '
          'ON portfolio_capital_assignments('
          'owner_user_id, portfolio_id, assigned_at, unassigned_at'
          ') WHERE deleted_at IS NULL',
        );
      }
      // v69 -> v70: FIRE assumptions become a recoverable, synced singleton
      // instead of two unrelated SharedPreferences payloads. Compatibility
      // migration is intentionally omitted; the new row is the only source
      // of truth.
      if (from < 70) {
        await m.createTable(firePlans);
      }
      // v71 -> v72: Memory records gain explicit evidence authority,
      // provenance, retrieval role, and supersede lineage.
      if (from < 72) {
        // Some development/test databases predate the local Memory Runtime
        // table while carrying a later user_version. Materialize the current
        // base table before adding columns or indexes.
        await customStatement(createMemories);
        await _addColumnIfMissing(
          this,
          table: 'memories',
          column: 'role',
          definition: "TEXT NOT NULL DEFAULT 'legacy'",
        );
        await _addColumnIfMissing(
          this,
          table: 'memories',
          column: 'authority',
          definition: "TEXT NOT NULL DEFAULT 'legacy_unknown'",
        );
        await _addColumnIfMissing(
          this,
          table: 'memories',
          column: 'provenance_json',
          definition: "TEXT NOT NULL DEFAULT '{}'",
        );
        await _addColumnIfMissing(
          this,
          table: 'memories',
          column: 'supersedes_id',
          definition: 'TEXT',
        );
        await _createMemoryStorage(this);
        await _createPersonalProfile(this);
        // Pending AI candidates are disposable staging state. Rebuild the
        // table around the generic memory/profile target contract.
        await customStatement('DROP TABLE IF EXISTS memory_candidates');
        await _createMemoryCandidates(this);
      }
      // v72 -> v73: replace the derived event index with the typed,
      // evidence-anchored contract. Source-domain indexers rebuild its rows.
      if (from < 73) {
        await customStatement('DROP TABLE IF EXISTS events');
        await _createMemoryRuntime(this);
      }
      if (from < 74) {
        await _createAttentionDecisions(this);
      }
      if (from < 75) {
        await _createAgentFeedback(this);
      }
      if (from < 76) {
        await _createDeveloperIssues(this);
      }
      // Per-agent notification switches were removed. AttentionArbiter owns
      // proactive policy behind the one global notification preference.
      // Preferences are local/re-creatable, so intentionally drop the old
      // shape instead of carrying a compatibility column.
      if (from < 77) {
        await customStatement('DROP TABLE IF EXISTS agent_preferences');
        await _createAgentPreferences(this);
      }
      // v77 -> v78: separate market identity from symbol identity in the
      // local quote/history/search caches, and preserve the distinction
      // between an FX observation day and the time it was fetched.
      if (from < 78) {
        await _migrateFxRates(this);
        await _migrateMarketDataCaches(this, m);
        await _createMarketDataCacheIndexes(this);
      }
      // v78 → v79: dedicated `source_id` on health_metrics. Source
      // identity used to live only in row-id prefixes (`garmin:`, `hk:`,
      // `hc:`, `manual:`) plus the free-text `source_device`; the column
      // persists the same attribution so SQL-level per-source queries no
      // longer parse ids. Nullable: legacy rows keep deriving their
      // source from the prefix and are never rewritten in place.
      if (from < 79) {
        await _addColumnIfMissing(
          this,
          table: 'health_metrics',
          column: 'source_id',
          definition: 'TEXT',
        );
      }
      // v79 -> v80: reset ExecutionOS to its canonical three-table model.
      // Plan is the only grouping primitive and actions/progress expose one
      // `plan_id` relation.
      if (from < 80) {
        await customStatement(
          'DROP TABLE IF EXISTS execution_progress_entries',
        );
        await customStatement('DROP TABLE IF EXISTS execution_actions');
        await customStatement('DROP TABLE IF EXISTS execution_commitments');
        await customStatement('DROP TABLE IF EXISTS execution_projects');
        await customStatement('DROP TABLE IF EXISTS execution_plans');
        await m.createTable(executionPlans);
        await m.createTable(executionActions);
        await m.createTable(executionProgressEntries);
        await _createExecutionIndexes(this);
      }
      // v80 -> v81: reset KnowledgeOS to Notes, Decisions, and Relations.
      // The removed taxonomy and triage projections are intentionally not
      // migrated.
      if (from < 81) {
        await customStatement('DROP TABLE IF EXISTS knowledge_inbox_triage');
        await customStatement('DROP TABLE IF EXISTS knowledge_attachments');
        await customStatement('DROP TABLE IF EXISTS knowledge_relations');
        await customStatement('DROP TABLE IF EXISTS knowledge_routines');
        await customStatement('DROP TABLE IF EXISTS knowledge_experiments');
        await customStatement('DROP TABLE IF EXISTS knowledge_concepts');
        await customStatement('DROP TABLE IF EXISTS knowledge_decisions');
        await customStatement('DROP TABLE IF EXISTS knowledge_assumptions');
        await customStatement('DROP TABLE IF EXISTS knowledge_principles');
        await customStatement('DROP TABLE IF EXISTS knowledge_notes');
        await m.createTable(knowledgeNotes);
        await m.createTable(knowledgeDecisions);
        await m.createTable(knowledgeRelations);
        for (final statement in knowledgeIndexStmts) {
          await customStatement(statement);
        }
      }
      // v81 -> v82: synced organizational collections for the canonical
      // watchlist. Existing items require no backfill and appear in the
      // virtual All / Ungrouped views until the user assigns them.
      if (from < 82) {
        await m.createTable(watchlistCollections);
        await m.createTable(watchlistCollectionMembers);
        await _createWatchlistIndexes(this);
      }
      // v82 -> v83: synchronized manual ordering for collections and for
      // members inside each collection. Zero preserves the legacy timestamp
      // order until the user explicitly reorders a complete sibling set.
      if (from < 83) {
        await _addColumnIfMissing(
          this,
          table: 'watchlist_collections',
          column: 'sort_rank',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
        await _addColumnIfMissing(
          this,
          table: 'watchlist_collection_members',
          column: 'sort_rank',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        );
        await _createWatchlistIndexes(this);
      }
      // v83 -> v84: paper-only watchlist simulations. These tables have no
      // foreign keys or write paths into real portfolio/ledger aggregates.
      if (from < 84) {
        await m.createTable(watchlistSimulations);
        await m.createTable(watchlistSimulationPositions);
        await _createWatchlistIndexes(this);
      }
      // v84 -> v85: device-local daily observations for paper simulations.
      // The simulation inputs continue to sync; this derived curve does not.
      if (from < 85) {
        await m.createTable(watchlistSimulationObservations);
        await _createWatchlistIndexes(this);
      }
      // v85 -> v86: normalized, local-only corporate-action candidate cache.
      // Public provider rows remain rebuildable reference data and never join
      // FinanceOS sync or real investment ledger tables.
      if (from < 86) {
        await m.createTable(marketCorporateActionCandidates);
        await m.createTable(marketCorporateActionFetchStates);
        await _createMarketCorporateActionIndexes(this);
      }
      // v86 -> v87: synced paper-only action references for simulations.
      // Values remain per-share references until a future holdings-based model
      // can establish eligible quantity; they never write the real ledger.
      if (from < 87) {
        await m.createTable(watchlistSimulationActionEntries);
        await _createWatchlistIndexes(this);
      }
      // v87 -> v88: explicit holdings-based entitlement mode. Existing paper
      // simulations remain weightedDailyChangeV1; only new simulations with a
      // captured allocation version opt into holdingsTotalReturnV2.
      if (from < 88) {
        await _addColumnIfMissing(
          this,
          table: 'watchlist_simulations',
          column: 'calculation_mode',
          definition: "TEXT NOT NULL DEFAULT 'weightedDailyChangeV1'",
        );
        await m.createTable(watchlistSimulationAllocationVersions);
        await m.createTable(watchlistSimulationHoldingVersions);
        await _createWatchlistIndexes(this);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<void> _createPortfolioIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_investment_portfolios_owner_hlc '
    'ON investment_portfolios(owner_user_id, hlc)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_strategy_templates_owner '
    'ON portfolio_strategy_templates(owner_user_id, created_at) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_rebalance_universes_owner '
    'ON rebalance_universes(owner_user_id, created_at) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_allocation_targets_universe '
    'ON portfolio_allocation_targets(owner_user_id, universe_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_strategy_configs_owner '
    'ON portfolio_strategy_configs(owner_user_id, portfolio_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_rebalance_groups_owner '
    'ON portfolio_rebalance_groups(owner_user_id, portfolio_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_capital_assignments_group '
    'ON portfolio_capital_assignments(owner_user_id, rebalance_group_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_capital_assignments_history '
    'ON portfolio_capital_assignments('
    'owner_user_id, portfolio_id, assigned_at, unassigned_at'
    ') WHERE deleted_at IS NULL',
  );
}
