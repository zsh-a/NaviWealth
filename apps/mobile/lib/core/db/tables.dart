import 'package:drift/drift.dart';

@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 128)();
  TextColumn get kind => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get institution => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  TextColumn get assetClass => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  RealColumn get averageCost => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TxnRow')
class Txns extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get assetId => text().nullable().references(Assets, #id)();
  TextColumn get kind => text()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  RealColumn get quantity => real().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get fee => real().withDefault(const Constant(0))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FxRateRow')
class FxRates extends Table {
  TextColumn get base => text().withLength(min: 3, max: 8)();
  TextColumn get quote => text().withLength(min: 3, max: 8)();
  DateTimeColumn get asOf => dateTime()();
  RealColumn get rate => real()();

  @override
  Set<Column<Object>> get primaryKey => {base, quote, asOf};
}

@DataClassName('AppMetaRow')
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Cached latest quote per (symbol, source). Schema v2 (FIR-26).
///
/// `price` and other monetary fields are stored as TEXT (Decimal-stringified)
/// because SQLite REAL is double-precision and would silently truncate small
/// fractional values used for crypto / FX rates. The cache layer parses on
/// read; performance impact is negligible at our row counts.
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
/// `results` holds a JSON array of [SymbolInfo] rows. Encoding inline
/// avoids cascade tables for what is otherwise a short-TTL convenience
/// cache; if search becomes a hot path we will migrate to a join table.
@DataClassName('MarketSymbolSearchRow')
class MarketSymbolSearches extends Table {
  TextColumn get query => text()();
  TextColumn get source => text()();
  TextColumn get results => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {query, source};
}
