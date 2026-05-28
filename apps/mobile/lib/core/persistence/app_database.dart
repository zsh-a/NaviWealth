import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../core/sync/sync_tables.dart';
import 'connection.dart';
import 'converters.dart';
import 'event_log_tables.dart';
import 'health_tables.dart';
import 'knowledge_tables.dart';
import 'local_only_tables.dart';
import 'tables.dart';

part 'app_database.g.dart';

const String defaultDbFileName = 'naviwealth.db';

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
    // KnowledgeOS (`docs/knowledgeos-domain.md` §9): six typed tables —
    // Memory itself reuses the cross-domain `memories` table per §3.
    KnowledgeNotes,
    KnowledgePrinciples,
    KnowledgeAssumptions,
    KnowledgeDecisions,
    KnowledgeConcepts,
    KnowledgeExperiments,
    KnowledgeRoutines,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({String? dbFileName})
    : super(openAppConnection(dbFileName: dbFileName ?? defaultDbFileName));

  @override
  int get schemaVersion => 22;

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
      await _createMemoryRuntime(this);
      await _createKnowledgeInboxTriage(this);
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
      // prefix (Wave 39). Side table > new column on entity tables —
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
      // cloud Vision path actually has a blob to stage.
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
      // the scanner; see docs/options-income.md §6.2.
      if (from < 11) {
        await m.createTable(optionsStrategyProfileTable);
        await m.createTable(approvedUnderlyings);
        await _createOptionsIncomeIndexes(this);
      }
      // v11 -> v12: Options Income Planner P1 — local-only opportunity
      // cache table populated by the scanner (`docs/options-income.md`
      // §6.2). Never enters the sync OpLog.
      if (from < 12) {
        await _createOptionsOpportunityCache(this);
      }
      // v12 -> v13: Options Income Planner P3 — synced trade journal.
      if (from < 13) {
        await m.createTable(optionsTradeJournal);
        await _createOptionsTradeJournalIndexes(this);
      }
      // v13 → v14: sync v2 cleanup. Drop the dead `sync_errors` table and
      // rebuild `op_outbox` as a pure dirty-pointer log (`docs/sync-v2.md`
      // §7.1). SyncBackfill (version bumped) re-enqueues every local row,
      // so dropping the old outbox loses no pending change.
      if (from < 14) {
        await customStatement('DROP TABLE IF EXISTS sync_errors');
        await customStatement('DROP TABLE IF EXISTS op_outbox');
        await customStatement(createOpOutbox);
        await customStatement(createOpOutboxIndex);
      }
      // v14 → v15: monthly category budgets (`roadmap-next.md` §3.2). One
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
      // (`docs/lifeos-shell.md` §6, D-1.7). Local-only — derived from
      // domain rows, re-indexable, never enters sync.
      if (from < 16) {
        await _createMemoryDocuments(this);
      }
      // v16 → v17: Memory Runtime split (`docs/lifeos-shell.md` §6,
      // D-1.7b). memory_documents → memories (typed) + memory_embeddings
      // (vectors keyed by memory_id) + events (cross-domain event log).
      // The v16 table held derived data only, so dropping it is safe —
      // indexers re-populate from source-of-truth tables at next boot.
      if (from < 17) {
        await customStatement('DROP TABLE IF EXISTS memory_documents');
        await _createMemoryRuntime(this);
      }
      // v17 → v18: HealthOS domain skeleton (`docs/healthos-domain.md`
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
      // (`docs/knowledgeos-domain.md` §9). Six typed tables — Memory
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
          await customStatement(stmt);
        }
      }
      // v19 → v20: KnowledgeOS inbox triage side-table
      // (`docs/knowledgeos-domain.md` §7 + §5 异步 triage flow).
      // Local-only, never-sync — InboxTriageAgent uses it to skip
      // already-proposed notes and the Review tab reads pending
      // envelopes from it.
      if (from < 20) {
        await _createKnowledgeInboxTriage(this);
      }
      // v20 → v21: KnowledgeOS routines (`docs/knowledgeos-domain.md`
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
      // v21 → v22: KnowledgeOS dedupe pointer (`docs/knowledgeos-domain.md`
      // §15.3). `merged_into_id` on Notes + Concepts records where a
      // soft-deleted duplicate's content went after `propose_merge`.
      // Additive nullable columns — no rewrite of existing rows.
      if (from < 22) {
        await customStatement(
          'ALTER TABLE knowledge_notes ADD COLUMN merged_into_id TEXT',
        );
        await customStatement(
          'ALTER TABLE knowledge_concepts ADD COLUMN merged_into_id TEXT',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<void> _createChatTables(AppDatabase db) async {
  const stmts = <String>[
    '''
CREATE TABLE IF NOT EXISTS chat_sessions (
  id              TEXT PRIMARY KEY,
  owner_user_id   TEXT NOT NULL,
  title           TEXT NOT NULL,
  model           TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  last_message_at INTEGER
)
''',
    '''
CREATE TABLE IF NOT EXISTS chat_messages (
  id                  TEXT PRIMARY KEY,
  session_id          TEXT NOT NULL,
  owner_user_id       TEXT NOT NULL,
  role                TEXT NOT NULL,
  content             TEXT NOT NULL DEFAULT '',
  tool_calls_json     TEXT,
  text_segments_json  TEXT,
  reasoning_text      TEXT,
  usage_json          TEXT,
  status              TEXT NOT NULL,
  error_message       TEXT,
  stop_reason         TEXT,
  created_at          INTEGER NOT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
)
''',
    'CREATE INDEX IF NOT EXISTS idx_chat_sessions_owner_last '
        'ON chat_sessions(owner_user_id, last_message_at)',
    'CREATE INDEX IF NOT EXISTS idx_chat_messages_session_created '
        'ON chat_messages(session_id, created_at)',
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createSyncTables(AppDatabase db) async {
  for (final stmt in syncTableDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createDomainEventLog(AppDatabase db) async {
  for (final stmt in domainEventLogDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createIndexes(AppDatabase db) async {
  const stmts = <String>[
    'CREATE INDEX IF NOT EXISTS idx_accounts_owner_hlc '
        'ON accounts(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_assets_owner_hlc '
        'ON assets(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_liabilities_owner_hlc '
        'ON liabilities(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_amort_owner_hlc '
        'ON amortization_entries(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_tags_owner_hlc '
        'ON tags(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_tag_links_owner_hlc '
        'ON tag_links(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_categories_owner_hlc '
        'ON categories(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_goals_owner_hlc '
        'ON goals(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_budgets_owner_hlc '
        'ON budgets(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_budgets_category_period '
        'ON budgets(category_id, period_month)',
    'CREATE INDEX IF NOT EXISTS idx_devices_owner_hlc '
        'ON devices(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_amort_liability_period '
        'ON amortization_entries(liability_id, period_index)',
    'CREATE INDEX IF NOT EXISTS idx_fx_rates_pair_as_of '
        'ON fx_rates(base_currency, quote_currency, as_of)',
    'CREATE INDEX IF NOT EXISTS idx_tag_links_entity '
        'ON tag_links(entity_table, entity_id)',
    'CREATE INDEX IF NOT EXISTS idx_op_logs_unsynced '
        'ON op_logs(synced_at, hlc) WHERE synced_at IS NULL',
    'CREATE INDEX IF NOT EXISTS idx_op_logs_owner_hlc '
        'ON op_logs(owner_user_id, hlc)',
    // HealthOS (D-2.1): typical reads are "give me the last N rows
    // of <kind> for this user" plus the standard owner+hlc sync scan.
    'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_kind_captured '
        'ON health_metrics(owner_user_id, kind, captured_at)',
    'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_hlc '
        'ON health_metrics(owner_user_id, hlc)',
    ..._securitiesAssetIndexStmts,
    ..._journalEntryIndexStmts,
    ...knowledgeIndexStmts,
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _journalEntryIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_journal_entries_owner_hlc '
      'ON journal_entries(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_journal_entries_owner_date '
      'ON journal_entries(owner_user_id, date)',
  'CREATE INDEX IF NOT EXISTS idx_postings_je '
      'ON postings(journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_account_je '
      'ON postings(account_id, journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_unit_je '
      'ON postings(unit, journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_owner_hlc '
      'ON postings(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_prices_unit_quote_date '
      'ON prices(unit, quote_currency, observed_on)',
  'CREATE INDEX IF NOT EXISTS idx_prices_owner_hlc '
      'ON prices(owner_user_id, hlc)',
  ..._watchlistIndexStmts,
  ..._recurringTransactionIndexStmts,
  ..._optionsIncomeIndexStmts,
  ..._optionsTradeJournalIndexStmts,
];

const List<String> _securitiesAssetIndexStmts = [
  'CREATE UNIQUE INDEX IF NOT EXISTS uq_assets_market_symbol_live '
      'ON assets(market, symbol) '
      'WHERE market IS NOT NULL AND deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_assets_market_symbol '
      'ON assets(market, symbol) WHERE market IS NOT NULL',
];

const List<String> _recurringTransactionIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_recurring_transactions_owner_hlc '
      'ON recurring_transactions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_recurring_transactions_due '
      'ON recurring_transactions(owner_user_id, enabled, next_due_at) '
      'WHERE deleted_at IS NULL',
];

const List<String> _watchlistIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_watchlist_items_owner_hlc '
      'ON watchlist_items(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_items_owner_added '
      'ON watchlist_items(owner_user_id, added_at) '
      'WHERE deleted_at IS NULL',
];

Future<void> _createRecurringTransactionIndexes(AppDatabase db) async {
  for (final stmt in _recurringTransactionIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createWatchlistIndexes(AppDatabase db) async {
  for (final stmt in _watchlistIndexStmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _optionsIncomeIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_options_strategy_profile_owner_hlc '
      'ON options_strategy_profile(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_approved_underlyings_owner_hlc '
      'ON approved_underlyings(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_approved_underlyings_owner_symbol '
      'ON approved_underlyings(owner_user_id, symbol) '
      'WHERE deleted_at IS NULL',
];

const List<String> _optionsTradeJournalIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_options_trade_journal_owner_hlc '
      'ON options_trade_journal(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_options_trade_journal_owner_opened '
      'ON options_trade_journal(owner_user_id, opened_at DESC) '
      'WHERE deleted_at IS NULL',
];

Future<void> _createOptionsIncomeIndexes(AppDatabase db) async {
  for (final stmt in _optionsIncomeIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createOptionsTradeJournalIndexes(AppDatabase db) async {
  for (final stmt in _optionsTradeJournalIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createOptionsOpportunityCache(AppDatabase db) async {
  for (final stmt in optionsOpportunityCacheDdl) {
    await db.customStatement(stmt);
  }
}

/// Legacy v16 DDL — kept only so the `if (from < 16)` step in
/// [migration] still applies cleanly when a user jumps v15 → v17.
/// v17 immediately drops the table, so this is effectively a no-op
/// migration path in practice.
Future<void> _createMemoryDocuments(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS memory_documents ('
    '  id TEXT PRIMARY KEY, source TEXT, source_id TEXT, owner_user_id TEXT,'
    '  title TEXT, body TEXT, fingerprint TEXT, dimension INTEGER,'
    '  vector_bytes BLOB, updated_at INTEGER)',
  );
}

Future<void> _createMemoryRuntime(AppDatabase db) async {
  for (final stmt in memoryRuntimeDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createKnowledgeInboxTriage(AppDatabase db) async {
  for (final stmt in knowledgeInboxTriageDdl) {
    await db.customStatement(stmt);
  }
}

const List<String> _securitiesCatalogFtsStmts = [
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS securities_catalog_fts USING fts5(
  symbol,
  name_en,
  name_cn,
  pinyin,
  pinyin_initials,
  aliases,
  content='',
  tokenize='unicode61 remove_diacritics 2'
)
''',
];

Future<void> _createSecuritiesCatalogFts(AppDatabase db) async {
  for (final stmt in _securitiesCatalogFtsStmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _securitiesCatalogIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_symbol '
      'ON securities_catalog(symbol)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_name_en '
      'ON securities_catalog(name_en)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_name_cn '
      'ON securities_catalog(name_cn)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_pinyin '
      'ON securities_catalog(pinyin)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_pinyin_initials '
      'ON securities_catalog(pinyin_initials)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_market '
      'ON securities_catalog(market)',
];

Future<void> _createSecuritiesCatalogIndexes(AppDatabase db) async {
  for (final stmt in _securitiesCatalogIndexStmts) {
    await db.customStatement(stmt);
  }
}

// ---------------------------------------------------------------------------
// AI surfaces (Waves 23 / 24) — local-only audit + undo stack.
// Both tables stay device-local (never sync). Per-user partitioning is the
// caller's responsibility; we store the owner alongside each row so a
// multi-user install can scope queries.
// ---------------------------------------------------------------------------

Future<void> _createAiTraceTable(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_traces ('
    '  request_id     TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  started_at_iso TEXT NOT NULL,'
    '  payload_json   TEXT NOT NULL'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_traces_started_at '
    'ON ai_traces(started_at_iso DESC)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_traces_owner '
    'ON ai_traces(owner_user_id, started_at_iso DESC)',
  );
}

Future<void> _createAiUndoStackTable(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_undo_stack ('
    '  token          TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  created_at_iso TEXT NOT NULL,'
    '  expires_at_iso TEXT,'
    '  kind           TEXT NOT NULL,'
    '  payload_json   TEXT NOT NULL'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_undo_owner '
    'ON ai_undo_stack(owner_user_id, created_at_iso DESC)',
  );
}

Future<void> _createAiTouchedEntitiesTable(AppDatabase db) async {
  // Wave 39 — records "this entity was last touched by an AI
  // proposal apply at <touched_at>". Detail pages query this side
  // table to render `AiSourceMark` next to recently AI-modified
  // entities; storing the touch out-of-band keeps the underlying
  // entity schemas (journal_entries / accounts / liabilities /
  // assets) unaware of the AI write path.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_touched_entities ('
    '  owner_user_id TEXT NOT NULL,'
    '  entity_type   TEXT NOT NULL,'
    '  entity_id     TEXT NOT NULL,'
    '  touched_at    TEXT NOT NULL,'
    '  kind_label    TEXT,' // 'expense' / 'trade' / 'memo_edit' / ...
    '  trace_id      TEXT,' // AiTrace.requestId for jump-to-trace
    '  PRIMARY KEY (owner_user_id, entity_type, entity_id)'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_touched_owner '
    'ON ai_touched_entities(owner_user_id, touched_at DESC)',
  );
}

Future<void> _createIngestTables(AppDatabase db) async {
  // §5.10.10 / S5a — Layer 4 record-entry pipeline staging.
  //
  // `ingest_drafts` holds parsed-but-unconfirmed transactions. It is
  // deliberately a raw-SQL side table (same pattern as ai_undo_stack /
  // ai_touched_entities) and is **never added to the sync OpLog**: a
  // draft only becomes durable ledger truth after the user confirms it,
  // at which point it is written through the normal repository path.
  // This keeps "Raw Write-side Truth · AI 永远不能直接访问" intact and
  // makes §4.2's draft gate hold by construction rather than by policy.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ingest_drafts ('
    '  draft_id              TEXT PRIMARY KEY,'
    '  owner_user_id         TEXT NOT NULL,'
    '  created_at_iso        TEXT NOT NULL,'
    '  source_kind           TEXT NOT NULL,' // csv / pasteText / ...
    '  origin_label          TEXT,' //          filename or "粘贴文本"
    '  parsed_json           TEXT NOT NULL,' // ParsedTransaction payload
    '  confidence            REAL NOT NULL,'
    '  dedup_verdict         TEXT NOT NULL,' // newTxn/likelyDuplicate/duplicate
    '  dedup_target_entry_id TEXT,' //          matched journal_entries.id
    '  trace_id              TEXT,' //          AiTrace.requestId
    '  status                TEXT NOT NULL,' // pending/confirmed/dismissed
    '  expires_at_iso        TEXT'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ingest_drafts_owner '
    'ON ingest_drafts(owner_user_id, status, created_at_iso DESC)',
  );
  // Forward-compat: the original capture artefact (receipt image / PDF)
  // for the S5b/S5c cloud-Vision path. Encrypted at rest by SQLCipher
  // like the rest of the DB; purged on confirm or after expiry. Unused
  // in S5a (text/CSV has no binary blob) but created here so S5b does
  // not need a second schema bump.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ingest_attachments ('
    '  draft_id       TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  mime           TEXT NOT NULL,'
    '  blob           BLOB NOT NULL,'
    '  expires_at_iso TEXT'
    ')',
  );
}
