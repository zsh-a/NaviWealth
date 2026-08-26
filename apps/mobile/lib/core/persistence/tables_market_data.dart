part of 'tables.dart';

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

  /// Trading/observation date supplied by the provider. This is deliberately
  /// separate from [fetchedAt]: a cached quote may describe an older market
  /// day even though the app recorded it today.
  DateTimeColumn get asOf => dateTime()();

  /// When this observation was written to the local store / received from
  /// the provider. Used for freshness and audit UI; never used as the FX
  /// valuation date.
  DateTimeColumn get fetchedAt => dateTime()();
  TextColumn get source => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Cached latest quote per (market, symbol, source). Local cache only — not
/// synced. Market is part of the key because a bare ticker can exist on more
/// than one venue/provider route.
///
/// Monetary fields are stored as TEXT (Decimal-stringified) because SQLite
/// REAL would silently truncate small fractional values used for crypto / FX.
@DataClassName('MarketQuoteRow')
class MarketQuotes extends Table {
  TextColumn get market => text()();
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
  Set<Column<Object>> get primaryKey => {market, symbol, source};
}

/// Cached daily/weekly/monthly bar per (market, symbol, interval, asOf,
/// source).
@DataClassName('MarketHistoryRow')
class MarketHistoryBars extends Table {
  TextColumn get market => text()();
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
  Set<Column<Object>> get primaryKey => {
    market,
    symbol,
    interval,
    asOf,
    source,
  };
}

/// Cached symbol-search results keyed by market + normalised query + source.
///
/// `results` holds a JSON array of SymbolInfo rows. Encoding inline avoids
/// a join table for what is otherwise a short-TTL convenience cache.
@DataClassName('MarketSymbolSearchRow')
class MarketSymbolSearches extends Table {
  TextColumn get market => text()();
  TextColumn get query => text()();
  TextColumn get source => text()();
  TextColumn get results => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {market, query, source};
}

/// Read-only seed catalog of major securities (A-shares full set,
/// HK / US majors, popular ETFs). The trade-entry search hits this table
/// first so a fresh install with zero recorded trades still finds
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

/// Singleton row that pins which version of the seed catalog is
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
