part of 'tables.dart';

/// Options Income Planner — user's strategy stance. One row per user
/// (singleton, keyed by `owner_user_id`, matching the `settings` table
/// pattern). See `docs/domains/options-income.md` §6.2.
@DataClassName('OptionsStrategyProfileRow')
class OptionsStrategyProfileTable extends Table with SyncableTable {
  TextColumn get userId => text()();
  TextColumn get mode => text()();
  TextColumn get allowedStrategiesJson =>
      text().withDefault(const Constant('[]'))();
  IntColumn get minDte => integer()();
  IntColumn get maxDte => integer()();
  TextColumn get deltaPutMin => text().map(const DecimalConverter())();
  TextColumn get deltaPutMax => text().map(const DecimalConverter())();
  TextColumn get deltaCallMin => text().map(const DecimalConverter())();
  TextColumn get deltaCallMax => text().map(const DecimalConverter())();
  TextColumn get maxCapitalPerTradePct =>
      text().map(const DecimalConverter())();
  TextColumn get maxUnderlyingExposurePct =>
      text().map(const DecimalConverter())();
  TextColumn get minAnnualizedYield => text().map(const DecimalConverter())();
  IntColumn get minOpenInterest => integer()();
  IntColumn get minVolume => integer()();
  TextColumn get maxBidAskSpreadPct => text().map(const DecimalConverter())();
  BoolColumn get avoidEarnings => boolean().withDefault(const Constant(true))();
  BoolColumn get avoidMacroEvents =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get onlyOnApprovedUnderlyings =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get riskDisclosureAckAt => dateTime().nullable()();

  @override
  String? get tableName => 'options_strategy_profile';

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// Options Income Planner — trade journal entries (synced). One row per
/// open / closed position the user records. See `docs/domains/options-income.md`
/// §6.2 and §1.1 ("Trade Journal").
@DataClassName('OptionsTradeJournalRow')
class OptionsTradeJournal extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get strategy => text()(); // cash_secured_put | covered_call
  TextColumn get symbol => text()();
  TextColumn get optionSymbol => text()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get expirationAt => dateTime().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get entryCredit => text().map(const DecimalConverter())();
  TextColumn get exitDebit => text().map(const DecimalConverter()).nullable()();
  TextColumn get fees => text().map(const DecimalConverter()).nullable()();
  TextColumn get realizedPnl =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get status => text()(); // open | closed | assigned | expired
  TextColumn get notes => text().nullable()();
  TextColumn get brokerageAccountId => text().nullable()();
  TextColumn get cashAccountId => text().nullable()();
  TextColumn get underlyingMarket => text().nullable()();
  TextColumn get strikePrice =>
      text().map(const DecimalConverter()).nullable()();
  IntColumn get contractSize => integer().nullable()();
  IntColumn get contractQuantity => integer().withDefault(const Constant(1))();

  @override
  String? get tableName => 'options_trade_journal';

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Options Income Planner — symbols the user has explicitly approved for
/// sell-put / covered-call candidate generation. See
/// `docs/domains/options-income.md` §6.2.
@DataClassName('ApprovedUnderlyingRow')
class ApprovedUnderlyings extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get symbol => text()();
  TextColumn get market => text()();
  BoolColumn get allowPut => boolean().withDefault(const Constant(true))();
  BoolColumn get allowCall => boolean().withDefault(const Constant(true))();
  TextColumn get maxBuyPrice =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get minSellPrice =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get notes => text().nullable()();

  @override
  List<String> get customConstraints => [
    'UNIQUE(owner_user_id, market, symbol)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}
