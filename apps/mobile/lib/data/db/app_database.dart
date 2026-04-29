import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/sync/sync_tables.dart';
import '../domain/enums.dart';
import '../domain/hlc.dart';
import 'connection.dart';
import 'converters.dart';
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
    Goals,
    Devices,
    OpLogs,
    MarketQuotes,
    MarketHistoryBars,
    MarketSymbolSearches,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Production constructor: opens an encrypted on-disk SQLCipher database.
  AppDatabase.encrypted({required String encryptionKey, String? dbFileName})
    : super(
        openAppConnection(
          dbFileName: dbFileName ?? defaultDbFileName,
          encryptionKey: encryptionKey,
        ),
      );

  /// Schema history:
  ///  - v2 (FIR-34) — SyncEngine outbox + cursor key/value store.
  ///  - v3 (FIR-47) — Liability gains paymentMethod / rateType /
  ///    statementDay / paymentDueDay so amortization tables can be derived
  ///    and credit-card billing days can drive reminders.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(this);
      await _createSyncTables(this);
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

Future<void> _createSyncTables(AppDatabase db) async {
  for (final stmt in syncTableDdl) {
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
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}
