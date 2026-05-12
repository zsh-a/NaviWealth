import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/sync/sync_tables.dart';
import '../domain/enums.dart';
import '../domain/hlc.dart';
import 'connection.dart';
import 'converters.dart';
import 'event_log_tables.dart';
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
    Liabilities,
    AmortizationEntries,
    Currencies,
    FxRates,
    Tags,
    TagLinks,
    Categories,
    Goals,
    Devices,
    OpLogs,
    MarketQuotes,
    MarketHistoryBars,
    MarketSymbolSearches,
    SecuritiesCatalog,
    SecuritiesCatalogMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({String? dbFileName})
    : super(openAppConnection(dbFileName: dbFileName ?? defaultDbFileName));

  @override
  int get schemaVersion => 6;

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
    ..._securitiesAssetIndexStmts,
    ..._journalEntryIndexStmts,
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
];

const List<String> _securitiesAssetIndexStmts = [
  'CREATE UNIQUE INDEX IF NOT EXISTS uq_assets_market_symbol_live '
      'ON assets(market, symbol) '
      'WHERE market IS NOT NULL AND deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_assets_market_symbol '
      'ON assets(market, symbol) WHERE market IS NOT NULL',
];

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
    '  kind_label    TEXT,'           // 'expense' / 'trade' / 'memo_edit' / ...
    '  trace_id      TEXT,'           // AiTrace.requestId for jump-to-trace
    '  PRIMARY KEY (owner_user_id, entity_type, entity_id)'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_touched_owner '
    'ON ai_touched_entities(owner_user_id, touched_at DESC)',
  );
}
