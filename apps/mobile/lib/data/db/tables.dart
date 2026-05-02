import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'converters.dart';

/// Mixin for sync metadata columns shared by every replicable table.
///
/// Drift table mixins must declare each column the same way a table would
/// (`Column<X> get foo => ...`). Tables that mix this in inherit five
/// extra columns and a [syncIndex] convention that callers compose into
/// their own [Table.indexes] (Drift doesn't currently support index merging
/// across mixins, so each table re-references the indexes they need).
mixin SyncableTable on Table {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  TextColumn get ownerUserId => text()();

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  DateTimeColumn get updatedAt => dateTime()();

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  TextColumn get updatedByDevice => text()();

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  TextColumn get hlc => text().map(const HlcConverter())();

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@DataClassName('UserRow')
class Users extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingsRow')
class SettingsTable extends Table with SyncableTable {
  TextColumn get userId => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8)();
  TextColumn get themeMode =>
      text().map(const EnumStringConverter(AppThemeMode.values))();
  TextColumn get privacyMode =>
      text().map(const EnumStringConverter(PrivacyMode.values))();
  TextColumn get costBasisMethod =>
      text().map(const EnumStringConverter(CostBasisMethod.values))();

  @override
  String? get tableName => 'settings';

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DataClassName('AccountRow')
class Accounts extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(AccountType.values))();
  TextColumn get name => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get institution => text().nullable()();
  TextColumn get accountNumber => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// FIR-126 — accounting classification (asset / liability / income /
  /// expense / equity). See [AccountCategory] for the why and the
  /// migration in `app_database.dart` (v8) for the back-fill rules.
  ///
  /// Defaulting to `asset` at the column level lets us add the column
  /// non-null in the v8 ALTER TABLE without a separate UPDATE step on
  /// users who only ever held positive balances; the migration still
  /// rewrites the seven non-`liability` AccountTypes explicitly so the
  /// fact stays expressed in code rather than relying on the SQL default.
  TextColumn get category => text()
      .map(const EnumStringConverter(AccountCategory.values))
      .withDefault(Constant(AccountCategory.asset.name))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetRow')
class Assets extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(AssetType.values))();
  TextColumn get symbol => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get name => text().nullable()();
  TextColumn get market => text().nullable()();
  TextColumn get industry => text().nullable()();
  TextColumn get region => text().nullable()();
  TextColumn get isin => text().nullable()();
  TextColumn get lastPrice => text().map(const DecimalConverter()).nullable()();
  DateTimeColumn get lastPriceAt => dateTime().nullable()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get metadataJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TransactionRow')
class Transactions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get assetId => text().nullable()();
  TextColumn get type =>
      text().map(const EnumStringConverter(TransactionType.values))();
  TextColumn get quantity => text().map(const DecimalConverter())();
  TextColumn get price => text().map(const DecimalConverter())();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  DateTimeColumn get tradeDate => dateTime()();
  DateTimeColumn get settleDate => dateTime().nullable()();
  TextColumn get fee => text().map(const DecimalConverter()).nullable()();
  TextColumn get tax => text().map(const DecimalConverter()).nullable()();
  TextColumn get counterAccountId => text().nullable()();
  TextColumn get lotId => text().nullable()();
  TextColumn get note => text().nullable()();

  /// FIR-68: expense-specific payload (category id, tags, ...) when
  /// `type = expense`. NULL for every other transaction kind. Kept as a
  /// JSON blob for the same reason `assets.metadata_json` is — adding
  /// expense-only columns would bloat the row for the 95% of transactions
  /// that aren't expenses.
  TextColumn get expenseMetadataJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LiabilityRow')
class Liabilities extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(LiabilityType.values))();
  TextColumn get name => text()();
  TextColumn get principal => text().map(const DecimalConverter())();
  TextColumn get interestRate => text().map(const DecimalConverter())();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get paymentMethod => text()
      .map(const EnumStringConverter(RepaymentMethod.values))
      .withDefault(Constant(RepaymentMethod.equalInstallment.name))();
  TextColumn get rateType => text()
      .map(const EnumStringConverter(LiabilityRateType.values))
      .withDefault(Constant(LiabilityRateType.fixed.name))();
  TextColumn get accountId => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get termMonths => integer().nullable()();
  TextColumn get monthlyPayment =>
      text().map(const DecimalConverter()).nullable()();
  IntColumn get statementDay => integer().nullable()();
  IntColumn get paymentDueDay => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AmortizationEntryRow')
class AmortizationEntries extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get liabilityId => text()();
  IntColumn get periodIndex => integer()();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get principalPayment => text().map(const DecimalConverter())();
  TextColumn get interestPayment => text().map(const DecimalConverter())();
  TextColumn get remainingBalance => text().map(const DecimalConverter())();
  DateTimeColumn get paidAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Static currency dictionary. NOT synced — see `domain/currency.dart`.
@DataClassName('CurrencyRow')
class Currencies extends Table {
  TextColumn get code => text().withLength(min: 3, max: 8)();
  TextColumn get name => text()();
  IntColumn get decimals => integer()();
  TextColumn get symbol => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// FX rate time series. NOT synced — global market data, each device pulls
/// its own copy from the price feed.
@DataClassName('FxRateRow')
class FxRates extends Table {
  TextColumn get id => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8)();
  TextColumn get quoteCurrency => text().withLength(min: 3, max: 8)();
  TextColumn get rate => text().map(const DecimalConverter())();
  DateTimeColumn get asOf => dateTime()();
  TextColumn get source => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind =>
      text().map(const EnumStringConverter(TagKind.values))();
  TextColumn get color => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagLinkRow')
class TagLinks extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get tagId => text()();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  IntColumn get sortOrder => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// FIR-68 — categorisation taxonomy for expenses. Two-level tree (a row
/// with a non-null `parentId` is a sub-category). Distinct from
/// [Categories], which is the generic asset/holding tree without
/// icon/color/archive support.
///
/// `archivedAt` is a *user-archive* flag (the row stays visible in pickers
/// but is hidden from the default list and from picker defaults) and is
/// orthogonal to the SyncableTable `deletedAt` tombstone (which removes
/// the row). Default categories seeded by [ExpenseCategoryRepository] use
/// deterministic ids so re-running the seed across devices doesn't
/// duplicate them.
@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GoalRow')
class Goals extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(GoalType.values))();
  TextColumn get name => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8).nullable()();
  TextColumn get targetAmount =>
      text().map(const DecimalConverter()).nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get targetAllocationJson => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DeviceRow')
class Devices extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get platform =>
      text().map(const EnumStringConverter(DevicePlatform.values))();
  TextColumn get appVersion => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  TextColumn get lastHlc => text().map(const HlcConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only operation log. Not a SyncableTable: ops *describe* sync
/// events, they aren't themselves synced via the same mechanism — the
/// server consumes them on push and emits them back to peers on pull.
@DataClassName('OpLogRow')
class OpLogs extends Table {
  TextColumn get id => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get deviceId => text()();
  TextColumn get hlc => text().map(const HlcConverter())();
  TextColumn get op => text().map(const EnumStringConverter(OpKind.values))();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  TextColumn get patchJson => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Cached latest quote per (symbol, source). Local cache only — not synced.
///
/// Monetary fields are stored as TEXT (Decimal-stringified) because SQLite
/// REAL would silently truncate small fractional values used for crypto / FX.
@DataClassName('MarketQuoteRow')
class MarketQuotes extends Table {
  TextColumn get symbol => text()();
  TextColumn get source => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get price => text()();
  TextColumn get previousClose => text().nullable()();
  TextColumn get openPrice => text().nullable()();
  TextColumn get dayHigh => text().nullable()();
  TextColumn get dayLow => text().nullable()();
  IntColumn get volume => integer().nullable()();
  TextColumn get exchange => text().nullable()();
  DateTimeColumn get asOf => dateTime()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {symbol, source};
}

/// Cached daily/weekly/monthly bar per (symbol, interval, asOf, source).
@DataClassName('MarketHistoryRow')
class MarketHistoryBars extends Table {
  TextColumn get symbol => text()();
  TextColumn get interval => text()();
  DateTimeColumn get asOf => dateTime()();
  TextColumn get source => text()();
  TextColumn get openPrice => text()();
  TextColumn get high => text()();
  TextColumn get low => text()();
  TextColumn get closePrice => text()();
  IntColumn get volume => integer().nullable()();
  TextColumn get adjustedClose => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {symbol, interval, asOf, source};
}

/// Cached symbol-search results keyed by normalised query + source.
///
/// `results` holds a JSON array of SymbolInfo rows. Encoding inline avoids
/// a join table for what is otherwise a short-TTL convenience cache.
@DataClassName('MarketSymbolSearchRow')
class MarketSymbolSearches extends Table {
  TextColumn get query => text()();
  TextColumn get source => text()();
  TextColumn get results => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {query, source};
}

/// FIR-76 — read-only seed catalog of major securities (A-shares full set,
/// HK / US majors, popular ETFs). The trade-entry search hits this table
/// first so a fresh install with zero recorded transactions still finds
/// the user's instrument by symbol, English name, Chinese name, full
/// pinyin or pinyin initials.
///
/// Deliberately *not* a [SyncableTable]:
///   - The catalog is a market dictionary, not user data — every device
///     has the same rows, derived from a pinned source bundle.
///   - Rebuilding it on demand from a versioned asset is cheaper than
///     replicating ~10k rows through the OpLog.
///   - Excluding it from sync also lets us iterate the schema (new
///     fields, finer-grained tokens) without burning HLC budget.
///
/// `id` follows the `Asset.idFor` grammar (`<market>:<symbol>`) so a
/// catalog hit can be hoisted into the synced `assets` table without
/// remapping ids when the user records their first trade.
@DataClassName('SecuritiesCatalogRow')
class SecuritiesCatalog extends Table {
  TextColumn get id => text()();
  TextColumn get symbol => text()();

  /// Wire-form market label (`cn_a`, `us_stock`, …). Matches the value
  /// space `assets.market` uses, so dedupe by `(market, symbol)` against
  /// owned assets is a plain string compare and never has to round-trip
  /// through `AssetMarket`.
  TextColumn get market => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(AssetType.values))();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get nameEn => text().nullable()();
  TextColumn get nameCn => text().nullable()();

  /// Lower-cased full pinyin without tone marks, no separators
  /// (e.g. `guizhoumaotai`). Matches typed-as-pinyin queries
  /// (`gzmaotai`, `kweichowmoutai`).
  TextColumn get pinyin => text().nullable()();

  /// Pinyin initials, no separators (e.g. `gzmt`). Matches the very
  /// common abbreviated-pinyin search style.
  TextColumn get pinyinInitials => text().nullable()();

  /// Whitespace-separated bag of additional searchable terms — common
  /// short forms, English aliases, ticker variants. Indexed by FTS5 like
  /// any other column; kept out of the four canonical name fields so
  /// rank doesn't get diluted on exact lookups.
  TextColumn get aliases => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// FIR-76 — singleton row that pins which version of the seed catalog is
/// currently materialised in [SecuritiesCatalog]. The loader compares
/// the bundled catalog's version + checksum against this row before
/// touching the catalog table; a no-change reload is a free no-op.
///
/// Singleton convention: `id` is always `1`. We use an explicit row
/// rather than a key/value blob so a botched upgrade can be inspected
/// (or dumped) with a single `SELECT * FROM securities_catalog_meta`.
@DataClassName('SecuritiesCatalogMetaRow')
class SecuritiesCatalogMeta extends Table {
  IntColumn get id => integer()();
  TextColumn get version => text()();
  TextColumn get checksum => text()();
  IntColumn get rowCount => integer()();
  DateTimeColumn get loadedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
