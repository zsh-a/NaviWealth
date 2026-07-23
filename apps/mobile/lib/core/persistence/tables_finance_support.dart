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

/// A user-defined logical investment sleeve. Portfolios classify capital by
/// purpose without changing the accounting account or the underlying ledger.
@DataClassName('InvestmentPortfolioRow')
class InvestmentPortfolios extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get strategy => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8).nullable()();
  TextColumn get goalId => text().nullable()();
  TextColumn get targetAllocationJson => text().nullable()();
  TextColumn get targetAnnualIncome =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Assigns one derived investment lot to exactly one logical portfolio.
///
/// The row id is the lot id, so moving a lot between portfolios updates the
/// same synced row and concurrent devices converge through the normal LWW
/// protocol. Lots without an active row remain in the virtual "Unassigned"
/// portfolio.
@DataClassName('PortfolioLotMembershipRow')
class PortfolioLotMemberships extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get portfolioId => text()();
  DateTimeColumn get assignedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
