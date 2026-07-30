part of 'tables.dart';

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
  TextColumn get logoUrl => text().nullable()();
  TextColumn get metadataJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WatchlistItemRow')
class WatchlistItems extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get symbol => text()();
  TextColumn get market => text()();
  DateTimeColumn get addedAt => dateTime()();
  TextColumn get alertRulesJson => text().withDefault(const Constant('{}'))();

  @override
  List<String> get customConstraints => [
    'UNIQUE(owner_user_id, market, symbol)',
  ];

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
  TextColumn get nameOverride => text().nullable()();
  TextColumn get systemKey => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get ledgerAccountId => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Monthly category budgets owned by FinanceOS.
///
/// One row per (categoryId, periodMonth) — pinning a budget to a category
/// + calendar month lets the dashboard read "this month's progress" with a
/// single keyed lookup. Currency is stored explicitly so a multi-currency
/// installation can budget in the category's native currency rather than
/// always in the report base.
///
/// The aggregate "spent vs. budgeted" view is **not** stored here; it is a
/// pure derivation over postings against the same category — see
/// `features/finance/cashflow/data/budget_progress_provider.dart`.
@DataClassName('BudgetRow')
class Budgets extends Table with SyncableTable {
  TextColumn get id => text()();

  /// Foreign key into `categories.id`. Untyped (no DB-level FK) so an
  /// orphaned category doesn't cascade-wipe budget history; the UI
  /// surfaces orphans with a "category missing" marker instead.
  TextColumn get categoryId => text()();

  /// Budget month, encoded `YYYY-MM` (e.g. `'2026-05'`). String avoids
  /// timezone foot-guns from storing a DateTime midnight.
  TextColumn get periodMonth => text().withLength(min: 7, max: 7)();

  /// Budget amount in the category's chosen currency.
  TextColumn get amount => text().map(const DecimalConverter())();

  /// ISO 4217 / synthetic unit (allows budgeting in points, miles, etc.
  /// if a future category opts into a non-money unit — same shape as
  /// postings.unit).
  TextColumn get currency => text().withLength(min: 3, max: 16)();

  /// Optional user note (e.g. "extra dining for Mum's birthday").
  TextColumn get note => text().nullable()();

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

/// Identity boundary for a user-defined logical investment portfolio.
@DataClassName('InvestmentPortfolioRow')
class InvestmentPortfolios extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8).nullable()();
  TextColumn get goalId => text().nullable()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Synced user-authored strategy types. Built-in templates live in code and
/// merge with these rows through the FinanceOS strategy catalog.
@DataClassName('PortfolioStrategyTemplateRow')
class PortfolioStrategyTemplates extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get localizedNamesJson => text()();
  TextColumn get iconToken => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get capitalRole => text()();
  TextColumn get defaultSettingsJson => text()();
  TextColumn get defaultInternalTargetJson => text()();
  IntColumn get defaultDriftBandBps => integer()();
  TextColumn get defaultTransferPolicy => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
    'CHECK (default_drift_band_bps >= 0 '
        'AND default_drift_band_bps <= 10000)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Denominator for portfolio-level target allocation.
@DataClassName('RebalanceUniverseRow')
class RebalanceUniverses extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8)();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Portfolio target weights inside a rebalance universe.
@DataClassName('PortfolioAllocationTargetRow')
class PortfolioAllocationTargets extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get universeId => text()();
  TextColumn get portfolioId => text()();
  IntColumn get targetWeightBps => integer()();
  IntColumn get driftBandBps => integer()();
  TextColumn get transferPolicy => text()();

  @override
  List<String> get customConstraints => [
    'CHECK (target_weight_bps >= 0 AND target_weight_bps <= 10000)',
    'CHECK (drift_band_bps >= 0 AND drift_band_bps <= 10000)',
    'UNIQUE(owner_user_id, universe_id, portfolio_id)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Open, independently versioned strategy modules attached to a portfolio.
@DataClassName('PortfolioStrategyConfigRow')
class PortfolioStrategyConfigs extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get portfolioId => text()();
  TextColumn get kind => text()();
  IntColumn get schemaVersion => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get capitalRole => text()();
  TextColumn get rebalanceGroupId => text().nullable()();
  TextColumn get configJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A capital-owning partition inside one logical portfolio.
@DataClassName('PortfolioRebalanceGroupRow')
class PortfolioRebalanceGroups extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get portfolioId => text()();
  TextColumn get name => text()();
  TextColumn get strategyKind => text()();
  IntColumn get targetWeightBps => integer()();
  IntColumn get driftBandBps => integer()();
  TextColumn get transferPolicy => text()();
  TextColumn get internalTargetJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
    'CHECK (target_weight_bps >= 0 AND target_weight_bps <= 10000)',
    'CHECK (drift_band_bps >= 0 AND drift_band_bps <= 10000)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Exclusive ownership of capital by a rebalance group.
///
/// A lot row carries either an optional positive quantity or NULL for the
/// whole remaining lot. A cash-account row carries a positive amount and
/// currency. The table is intentionally limited to these two real sources.
@DataClassName('PortfolioCapitalAssignmentRow')
class PortfolioCapitalAssignments extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get portfolioId => text()();
  TextColumn get rebalanceGroupId => text()();
  TextColumn get sourceKind => text()();
  TextColumn get sourceId => text()();
  TextColumn get quantity => text().map(const DecimalConverter()).nullable()();
  TextColumn get amount => text().map(const DecimalConverter()).nullable()();
  TextColumn get currency => text().withLength(min: 3, max: 8).nullable()();
  DateTimeColumn get assignedAt => dateTime()();
  DateTimeColumn get unassignedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK ((source_kind = \'lot\' AND amount IS NULL AND currency IS NULL '
        'AND (quantity IS NULL OR CAST(quantity AS REAL) > 0)) OR '
        '(source_kind = \'cashAccount\' AND quantity IS NULL '
        'AND amount IS NOT NULL AND CAST(amount AS REAL) > 0 '
        'AND currency IS NOT NULL))',
    'CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}
