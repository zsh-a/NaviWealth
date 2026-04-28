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
  TextColumn get paymentMethod =>
      text().map(const EnumStringConverter(RepaymentMethod.values)).withDefault(
        Constant(RepaymentMethod.equalInstallment.name),
      )();
  TextColumn get rateType =>
      text().map(const EnumStringConverter(LiabilityRateType.values)).withDefault(
        Constant(LiabilityRateType.fixed.name),
      )();
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
