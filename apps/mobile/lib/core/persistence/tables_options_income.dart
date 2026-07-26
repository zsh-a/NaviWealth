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
  TextColumn get minAnnualizedYield => text().map(const DecimalConverter())();
  IntColumn get minOpenInterest => integer()();
  IntColumn get minVolume => integer()();
  TextColumn get maxBidAskSpreadPct => text().map(const DecimalConverter())();
  // Buy-side LEAPS lane thresholds. Defaults mirror the balanced preset so
  // migrated rows behave like a freshly-created balanced profile.
  IntColumn get leapsMinDte => integer().withDefault(const Constant(365))();
  IntColumn get leapsMaxDte => integer().withDefault(const Constant(1095))();
  TextColumn get leapsDeltaMin => text()
      .map(const DecimalConverter())
      .withDefault(const Constant('0.65'))();
  TextColumn get leapsDeltaMax => text()
      .map(const DecimalConverter())
      .withDefault(const Constant('0.80'))();
  TextColumn get leapsMaxSpreadPct => text()
      .map(const DecimalConverter())
      .withDefault(const Constant('0.08'))();
  IntColumn get leapsMinOpenInterest =>
      integer().withDefault(const Constant(50))();
  BoolColumn get avoidEarnings => boolean().withDefault(const Constant(true))();
  BoolColumn get avoidMacroEvents =>
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
  TextColumn get underlyingAssetId => text()();
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

/// Long calls held as an upside overlay beside Wheel positions. This table is
/// intentionally separate from the Wheel journal because a bought call is
/// neither a short-premium trade nor a Wheel lifecycle stage.
@DataClassName('OptionsLeapsCallPositionRow')
class OptionsLeapsCallPositions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get underlyingAssetId => text()();
  TextColumn get symbol => text()();
  TextColumn get optionSymbol => text()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get expirationAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get strikePrice => text().map(const DecimalConverter())();
  TextColumn get entryDebit => text().map(const DecimalConverter())();
  TextColumn get exitCredit =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get fees =>
      text().map(const DecimalConverter()).withDefault(const Constant('0'))();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  IntColumn get contractSize => integer().withDefault(const Constant(100))();
  IntColumn get contractQuantity => integer().withDefault(const Constant(1))();
  TextColumn get status => text()();
  TextColumn get currentMark =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get currentDelta =>
      text().map(const DecimalConverter()).nullable()();
  DateTimeColumn get markedAt => dateTime().nullable()();
  TextColumn get brokerageAccountId => text().nullable()();
  TextColumn get cashAccountId => text().nullable()();
  TextColumn get underlyingMarket => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  String? get tableName => 'options_leaps_call_positions';

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// User intent and guardrails for composing income sleeves on one asset.
///
/// Live positions and derived metrics stay in their owning source tables;
/// this synced row only records which sleeves the user wants and the limits
/// that the deterministic coordinator should enforce.
@DataClassName('IncomeStrategyPlanRow')
class IncomeStrategyPlans extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get assetId => text()(); // canonical `<market>:<symbol>` asset id
  TextColumn get symbol => text()();
  TextColumn get market => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get sleeveIntentsJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get capitalBudget =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get annualIncomeTarget =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get maxPositionWeight =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get notes => text().nullable()();

  /// Optional strategy-group membership. Plans sharing a non-empty group id
  /// are coordinated as one cross-underlying group (e.g. TQQQ wheel funding
  /// a QQQ LEAPS call). Null keeps the asset as its own implicit group.
  TextColumn get groupId => text().nullable()();
  TextColumn get groupLabel => text().nullable()();

  @override
  List<String> get customConstraints => ['UNIQUE(owner_user_id, asset_id)'];

  @override
  String? get tableName => 'income_strategy_plans';

  @override
  Set<Column<Object>> get primaryKey => {id};
}
