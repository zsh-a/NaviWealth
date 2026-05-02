import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/sync/sync_tables.dart';
import '../../domain/values/asset_market.dart';
import '../domain/asset.dart';
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
/// Schema versioning policy:
///  - Bump [schemaVersion] for every shipped change.
///  - In [migration.onUpgrade], handle each `from -> to` step explicitly.
///    Don't rely on "from < N" ranges — a user upgrading from v3 to v6 will
///    run every step in order, so each step must be valid against the prior
///    one.
///  - When a column changes meaning (e.g. enum value renamed), the
///    migration must rewrite affected rows or it will silently desynchronize
///    the in-memory enum from the DB string.
@DriftDatabase(
  tables: [
    Users,
    SettingsTable,
    Accounts,
    Assets,
    Transactions,
    Liabilities,
    AmortizationEntries,
    Currencies,
    FxRates,
    Tags,
    TagLinks,
    Categories,
    ExpenseCategories,
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

  /// Production constructor: opens an on-disk SQLite database.
  AppDatabase.open({String? dbFileName})
    : super(openAppConnection(dbFileName: dbFileName ?? defaultDbFileName));

  /// Schema history:
  ///  - v2 (FIR-34) — SyncEngine outbox + cursor key/value store.
  ///  - v3 (FIR-47) — Liability gains paymentMethod / rateType /
  ///    statementDay / paymentDueDay so amortization tables can be derived
  ///    and credit-card billing days can drive reminders.
  ///  - v4 (FIR-68) — Expense schema: `transactions.expense_metadata_json`
  ///    (per-row expense payload) plus a dedicated `expense_categories`
  ///    table. The `expense` value was appended to TransactionType so
  ///    existing rows stay valid.
  ///  - v5 (FIR-60) — Local AI chat history (chat_sessions + chat_messages).
  ///    Local-only, never synced — chat transcripts are private to the
  ///    device. Tables are created with raw DDL so the chat feature can
  ///    evolve its row shape without tugging the main Drift codegen.
  ///  - v6 (FIR-75) — Securities asset catalog. Adds a partial unique index
  ///    on `assets(market, symbol)` for non-deleted, market-scoped rows,
  ///    and backfills `assets` rows from any historical
  ///    `transactions.asset_id` that was previously stored as a bare symbol
  ///    (synthesized in-memory by the trade entry form). The migration
  ///    rewrites `transactions.asset_id` to the canonical `<market>:<symbol>`
  ///    form so holdings replay continues to join cleanly.
  ///  - v7 (FIR-76) — Local securities seed catalog + FTS5 index. Adds
  ///    `securities_catalog`, `securities_catalog_meta` and a contentless
  ///    `securities_catalog_fts` virtual table. The catalog is populated
  ///    on first launch from a versioned asset bundle (see
  ///    `SecuritiesCatalogLoader`); it is local-only and does not
  ///    participate in OpLog sync.
  ///  - v8 (FIR-125) — Local-only `domain_event_log` audit ledger.
  ///    Append-only; never deleted by sync. Repositories pair every row
  ///    write with an event-log entry inside the same Drift transaction
  ///    so before/after snapshots survive after the OpLog row is acked
  ///    and removed. Strategy (a) per the issue: not synced; each
  ///    device retains its own "what I did" view.
  ///  - v9 (FIR-126) — Adds `accounts.category` (asset / liability /
  ///    income / expense / equity), the accounting classification that
  ///    P2-A's double-entry posting model leans on. Existing rows are
  ///    back-filled from `accounts.type`: `liability` carriers map to
  ///    [AccountCategory.liability] and everything else to
  ///    [AccountCategory.asset] — see [backfillAccountCategory]. The
  ///    income / expense / equity virtual *system accounts* are seeded at
  ///    repository level (see `AccountRepository.seedSystemAccounts`)
  ///    rather than in the migration so the seed shares the outbox /
  ///    HLC plumbing every other repo write goes through.
  @override
  int get schemaVersion => 9;

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
    onUpgrade: (m, from, to) async {
      for (var v = from + 1; v <= to; v++) {
        switch (v) {
          case 2:
            await _createSyncTables(this);
          case 3:
            await m.addColumn(liabilities, liabilities.paymentMethod);
            await m.addColumn(liabilities, liabilities.rateType);
            await m.addColumn(liabilities, liabilities.statementDay);
            await m.addColumn(liabilities, liabilities.paymentDueDay);
          case 4:
            await m.addColumn(transactions, transactions.expenseMetadataJson);
            await m.createTable(expenseCategories);
            await _createExpenseCategoriesIndexes(this);
          case 5:
            await _createChatTables(this);
          case 6:
            await _createSecuritiesAssetIndexes(this);
            await backfillSecuritiesAssetsFromTransactions(this);
          case 7:
            await m.createTable(securitiesCatalog);
            await m.createTable(securitiesCatalogMeta);
            await _createSecuritiesCatalogFts(this);
            await _createSecuritiesCatalogIndexes(this);
          case 8:
            await _createDomainEventLog(this);
          case 9:
            await m.addColumn(accounts, accounts.category);
            await backfillAccountCategory(this);
          default:
            throw StateError(
              'No migration registered for schema upgrade to v$v.',
            );
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// AI chat history (FIR-60). Two raw tables, both local-only:
///
///  - `chat_sessions` — one row per conversation, ordered by
///    `last_message_at DESC` for the sidebar.
///  - `chat_messages` — one row per turn (user / assistant / system /
///    error). The assistant turn carries the visible text *and* a
///    `tool_calls_json` blob so the UI can replay the tool-use timeline
///    without re-querying the model.
///
/// `IF NOT EXISTS` makes the helper idempotent so onCreate (fresh install)
/// and the v5 onUpgrade step (existing install) can both call it.
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

/// FIR-125 — append-only audit ledger. See `event_log_tables.dart` for
/// the rationale; the helper mirrors `_createSyncTables` so the same
/// statements run on a fresh install and on a v7→v8 upgrade.
Future<void> _createDomainEventLog(AppDatabase db) async {
  for (final stmt in domainEventLogDdl) {
    await db.customStatement(stmt);
  }
}

/// v4 migration helper: indexes for the new `expense_categories` table.
/// Pulled out so the upgrade path stays declarative and matches the same
/// statements [_createIndexes] uses on a fresh install.
Future<void> _createExpenseCategoriesIndexes(AppDatabase db) async {
  const stmts = <String>[
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_owner_hlc '
        'ON expense_categories(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_parent '
        'ON expense_categories(parent_id)',
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

/// Indexes that aren't expressible inline on Drift `Table` getters.
///
/// We create them as raw `CREATE INDEX IF NOT EXISTS` statements so the same
/// SQL works on the upgrade path: any future migration that introduces a new
/// table can call this without re-running ones that already exist.
Future<void> _createIndexes(AppDatabase db) async {
  const stmts = <String>[
    // Sync diff queries: "give me everything in this user's partition newer
    // than the last HLC I shipped." Wall+counter together approximate HLC
    // ordering well enough for SQL filtering; final ordering happens in Dart.
    'CREATE INDEX IF NOT EXISTS idx_accounts_owner_hlc '
        'ON accounts(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_assets_owner_hlc '
        'ON assets(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_transactions_owner_hlc '
        'ON transactions(owner_user_id, hlc)',
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
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_owner_hlc '
        'ON expense_categories(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_parent '
        'ON expense_categories(parent_id)',
    'CREATE INDEX IF NOT EXISTS idx_goals_owner_hlc '
        'ON goals(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_devices_owner_hlc '
        'ON devices(owner_user_id, hlc)',
    // Hot path for reports — "show me transactions in account X between
    // these dates" must not table-scan.
    'CREATE INDEX IF NOT EXISTS idx_transactions_account_trade_date '
        'ON transactions(account_id, trade_date)',
    'CREATE INDEX IF NOT EXISTS idx_transactions_asset_trade_date '
        'ON transactions(asset_id, trade_date)',
    // Amortization rows are always read by liability + period order.
    'CREATE INDEX IF NOT EXISTS idx_amort_liability_period '
        'ON amortization_entries(liability_id, period_index)',
    // FX rate lookup: nearest rate by (base, quote) at or before a given
    // date. The composite index covers the typical `WHERE base=? AND quote=?
    // ORDER BY as_of DESC LIMIT 1` query.
    'CREATE INDEX IF NOT EXISTS idx_fx_rates_pair_as_of '
        'ON fx_rates(base_currency, quote_currency, as_of)',
    // Tag links join from the entity side ("what tags are on this asset?")
    // far more often than from the tag side.
    'CREATE INDEX IF NOT EXISTS idx_tag_links_entity '
        'ON tag_links(entity_table, entity_id)',
    // OpLog sync: "ops I haven't pushed yet" and "ops past this HLC."
    'CREATE INDEX IF NOT EXISTS idx_op_logs_unsynced '
        'ON op_logs(synced_at, hlc) WHERE synced_at IS NULL',
    'CREATE INDEX IF NOT EXISTS idx_op_logs_owner_hlc '
        'ON op_logs(owner_user_id, hlc)',
    ..._securitiesAssetIndexStmts,
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

/// Indexes that anchor the FIR-75 securities catalog. Kept as a separate
/// constant so the v6 onUpgrade step can re-use the same DDL the
/// onCreate path runs for fresh installs.
///
/// The unique index is *partial*: it only covers rows with both `market`
/// and `symbol` set and a NULL `deleted_at`. Manual-valuation assets
/// (cash / deposits / wealth products) leave `market` NULL so they are
/// excluded; soft-deleted rows are excluded so a tombstone can sit
/// alongside a re-created live row without conflicting.
const List<String> _securitiesAssetIndexStmts = [
  'CREATE UNIQUE INDEX IF NOT EXISTS uq_assets_market_symbol_live '
      'ON assets(market, symbol) '
      'WHERE market IS NOT NULL AND deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_assets_market_symbol '
      'ON assets(market, symbol) WHERE market IS NOT NULL',
];

Future<void> _createSecuritiesAssetIndexes(AppDatabase db) async {
  for (final stmt in _securitiesAssetIndexStmts) {
    await db.customStatement(stmt);
  }
}

/// FIR-75 v6 backfill: every distinct `(asset_id, currency)` pair recorded
/// on a non-deleted `transactions` row is materialised into the `assets`
/// table, and `transactions.asset_id` is rewritten to the new canonical
/// `<market>:<symbol>` form so downstream replays (HoldingService etc.)
/// keep joining cleanly.
///
/// Public so the migration test can invoke it on a hand-rolled fixture
/// without having to wire a full schema-version-bump rehearsal.
///
/// Runs inside a single Drift transaction: if any statement fails the
/// whole rewrite rolls back and the database stays at v5 semantics. A
/// caller wanting to inspect the impact without committing should pass
/// `dryRun: true` — the function then walks the rows and returns a
/// [SecuritiesBackfillReport] without touching either table.
Future<SecuritiesBackfillReport> backfillSecuritiesAssetsFromTransactions(
  AppDatabase db, {
  bool dryRun = false,
}) async {
  Future<SecuritiesBackfillReport> run() async {
    // Pull the distinct (asset_id, currency) pairs we need to materialise,
    // along with the canonical owner / device / hlc / updated_at to seed
    // the new asset row from. Picking the *latest* transaction per asset
    // matches the LWW intuition — if a user has been trading AAPL since
    // 2019, we anchor the asset row to their most recent trade.
    final rows = await db.customSelect('''
          SELECT
            t.asset_id      AS asset_id,
            t.currency      AS currency,
            t.owner_user_id AS owner_user_id,
            t.updated_by_device AS updated_by_device,
            t.hlc           AS hlc,
            t.updated_at    AS updated_at
          FROM transactions AS t
          INNER JOIN (
            SELECT
              asset_id,
              currency,
              MAX(updated_at) AS max_updated_at
            FROM transactions
            WHERE asset_id IS NOT NULL
              AND deleted_at IS NULL
            GROUP BY asset_id, currency
          ) AS latest
            ON latest.asset_id = t.asset_id
            AND latest.currency = t.currency
            AND latest.max_updated_at = t.updated_at
          WHERE t.asset_id IS NOT NULL
            AND t.deleted_at IS NULL
          GROUP BY t.asset_id, t.currency
          ''').get();

    final report = SecuritiesBackfillReport();
    for (final row in rows) {
      final oldId = row.read<String>('asset_id');
      final currency = row.read<String>('currency');
      final ownerUserId = row.read<String>('owner_user_id');
      final updatedByDevice = row.read<String>('updated_by_device');
      final hlc = row.read<String>('hlc');
      final updatedAt = row.read<DateTime>('updated_at');

      // Skip ids that were already minted by the new scheme (e.g. produced
      // by an in-flight upsertSecurity call before the migration ran). The
      // only safe way to detect that is the `<market_wire>:<symbol>` shape
      // — we do NOT want to re-prefix `cn_a:600519` and end up with
      // `unknown:cn_a:600519`.
      if (_looksLikeCanonicalAssetId(oldId)) {
        report.skipped.add(oldId);
        continue;
      }

      final market = inferAssetMarket(oldId);
      final newId = Asset.idFor(market, oldId);
      report.entries.add(
        SecuritiesBackfillEntry(
          oldAssetId: oldId,
          newAssetId: newId,
          market: market,
          currency: currency,
        ),
      );
      if (market == AssetMarket.unknown) {
        report.unknownSymbols.add(oldId);
      }

      if (dryRun) continue;

      // Insert the asset row only if it isn't there already. Existing
      // installs may have a manual-valuation row keyed by something else;
      // this guard keeps us from clobbering it.
      //
      // Drift's default DateTime mapping stores seconds-since-epoch as an
      // INTEGER, so we hand the SQL layer the same shape rather than an
      // ISO-8601 string (which would round-trip but break the
      // `int.parse` reader on the way back out).
      await db.customStatement(
        '''
        INSERT INTO assets (
          id, type, symbol, currency, name, market,
          owner_user_id, updated_at, updated_by_device, hlc
        )
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (SELECT 1 FROM assets WHERE id = ?)
        ''',
        [
          newId,
          _assetTypeForMarket(market).name,
          oldId,
          currency,
          oldId, // best-effort: name = symbol until the user edits it
          market.wire,
          ownerUserId,
          updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
          updatedByDevice,
          hlc,
          newId,
        ],
      );

      // Rewrite transaction.asset_id everywhere it referenced the legacy
      // bare symbol. Filter on the legacy id alone — a single asset_id can
      // appear in multiple currencies in pathological data; the asset row
      // we created carries the *latest* currency, but the transactions
      // themselves keep their own currency intact, so we still rewrite all
      // of them onto the same new id.
      await db.customStatement(
        'UPDATE transactions SET asset_id = ? WHERE asset_id = ?',
        [newId, oldId],
      );
    }
    return report;
  }

  if (dryRun) {
    return run();
  }
  return db.transaction(run);
}

bool _looksLikeCanonicalAssetId(String id) {
  final colon = id.indexOf(':');
  if (colon <= 0) return false;
  final prefix = id.substring(0, colon);
  return assetMarketFromWire(prefix) != null;
}

/// FIR-126 v8 backfill: rewrites every existing `accounts.category` value
/// from the prior `accounts.type` carrier shape, mirroring the rules
/// documented on the issue. Public so the migration test can invoke it
/// directly against a hand-rolled fixture without rehearsing the full
/// schema-version-bump dance.
///
/// The column was added with a column-level default of `'asset'`, so this
/// step is mostly explicit-about-its-intent: we only have to overwrite
/// rows whose carrier is [AccountType.liability]. Doing so as a single
/// `UPDATE` keeps the migration cheap on installs with many accounts and
/// avoids opening a transaction we don't otherwise need.
Future<void> backfillAccountCategory(AppDatabase db) async {
  await db.customStatement('UPDATE accounts SET category = ? WHERE type = ?', [
    AccountCategory.liability.name,
    AccountType.liability.name,
  ]);
}

/// FIR-76 — contentless FTS5 index over the seed catalog. We use
/// `content=''` (a.k.a. "contentless table") so the FTS rows hold only
/// the inverted index, never the source columns; the loader keeps the
/// FTS rowids in lock-step with [SecuritiesCatalog] rowids so a
/// `SELECT ... JOIN securities_catalog ON ...` brings the original
/// fields back. Two reasons we picked contentless over external content:
///
///   - We rebuild the catalog atomically from the asset bundle, so an
///     external `content='securities_catalog'` table (which delegates
///     `SELECT *` back to the source table by rowid) buys us nothing
///     beyond the same join we'd write anyway.
///   - We sidestep FTS5 triggers entirely. Trigger-driven sync is fragile
///     under bulk inserts (the dump/reload path would fire 10k×3
///     triggers); the loader inserts both tables explicitly inside a
///     single transaction and stays predictable.
///
/// Tokenizer: `unicode61 remove_diacritics 2` — folds case, strips most
/// diacritics, and treats CJK runs as letters so a Chinese name still
/// indexes as a single token. Chinese sub-string matching (e.g. typing
/// `茅台` against `贵州茅台`) is handled at search time by the
/// `aliases` column rather than by an exotic CJK tokenizer.
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
  // Catalog reads are dominated by exact and prefix lookups on the four
  // canonical columns. Prefix `LIKE 'q%'` queries on a TEXT column can
  // use a regular index when the collation matches the search casing —
  // the loader writes lower-cased values into these columns, so the
  // default BINARY collation is sufficient.
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

/// Conservative default: A-shares / HK / US all map to plain stock; the
/// crypto market maps to crypto. Manual editing in the UI can refine this
/// once FIR-77 lands.
AssetType _assetTypeForMarket(AssetMarket market) {
  switch (market) {
    case AssetMarket.crypto:
      return AssetType.crypto;
    case AssetMarket.cnA:
    case AssetMarket.hkStock:
    case AssetMarket.usStock:
      return AssetType.stock;
    case AssetMarket.fx:
    case AssetMarket.unknown:
      return AssetType.custom;
  }
}

/// One backfill output row.
class SecuritiesBackfillEntry {
  const SecuritiesBackfillEntry({
    required this.oldAssetId,
    required this.newAssetId,
    required this.market,
    required this.currency,
  });

  final String oldAssetId;
  final String newAssetId;
  final AssetMarket market;
  final String currency;

  @override
  String toString() =>
      'SecuritiesBackfillEntry($oldAssetId -> $newAssetId, '
      'market=${market.wire}, currency=$currency)';
}

/// Aggregate result of a backfill pass — what *would* happen (dry-run) or
/// what *did* happen (committed run). Caller can log [unknownSymbols] to
/// flag rows that fell into the [AssetMarket.unknown] bucket and may
/// warrant manual cleanup.
class SecuritiesBackfillReport {
  SecuritiesBackfillReport();

  final List<SecuritiesBackfillEntry> entries = [];
  final List<String> unknownSymbols = [];
  final List<String> skipped = [];

  int get rewritten => entries.length;
}
