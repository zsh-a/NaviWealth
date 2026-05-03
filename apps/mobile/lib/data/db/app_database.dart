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
/// compatibility migrations for the removed `transactions` and
/// `expense_categories` tables are intentionally gone; a fresh schema is the
/// source of truth.
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
  int get schemaVersion => 1;

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
  id               TEXT PRIMARY KEY,
  session_id       TEXT NOT NULL,
  owner_user_id    TEXT NOT NULL,
  role             TEXT NOT NULL,
  content          TEXT NOT NULL DEFAULT '',
  tool_calls_json  TEXT,
  status           TEXT NOT NULL,
  error_message    TEXT,
  created_at       INTEGER NOT NULL,
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
