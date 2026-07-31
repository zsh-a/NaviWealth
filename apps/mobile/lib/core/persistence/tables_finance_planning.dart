part of 'tables.dart';

/// Recoverable per-user FIRE planning input.
///
/// Derived projections, stress-test results and reviews remain read models;
/// only user-authored assumptions are synced and included in backups.
@DataClassName('FirePlanRow')
class FirePlans extends Table with SyncableTable {
  TextColumn get userId => text()();
  TextColumn get baseCurrency => text()();
  TextColumn get monthlyExpenses => text().map(const DecimalConverter())();
  TextColumn get monthlySurplus => text().map(const DecimalConverter())();
  RealColumn get inflationRate => real()();
  TextColumn get targetNetWorth => text().map(const DecimalConverter())();
  RealColumn get safeWithdrawalRate => real()();
  IntColumn get targetCashBucketMonths => integer()();
  TextColumn get lifestyleMode => text()();
  TextColumn get reservesJson => text().withDefault(const Constant('[]'))();
  TextColumn get riskSettingsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// A durable decision envelope. Domain-specific inputs and deterministic
/// outputs stay versioned JSON so adding a scenario template does not require
/// widening the table.
@DataClassName('FinancialDecisionRow')
class FinancialDecisions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get template => text()();
  TextColumn get selectedVariant => text()();
  IntColumn get calculatorVersion => integer()();
  TextColumn get baselineJson => text()();
  TextColumn get assumptionsJson => text()();
  TextColumn get selectedOutcomeJson => text()();
  DateTimeColumn get decidedAt => dateTime()();
  DateTimeColumn get reviewDate => dateTime()();
  TextColumn get actualOutcomeJson => text().nullable()();
  TextColumn get reviewEvidenceJson => text().nullable()();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get actionId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A durable, user-controlled periodic investment plan. Market simulation
/// results remain derived/cache data; this row is the commitment that can be
/// paused, resumed, executed, and synced across devices.
@DataClassName('DcaPlanRow')
class DcaPlans extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get allocationsJson => text()();
  TextColumn get amountPerContribution =>
      text().map(const DecimalConverter())();
  TextColumn get currency => text()();
  TextColumn get market => text()();
  TextColumn get frequency => text()();
  DateTimeColumn get nextDueAt => dateTime()();
  DateTimeColumn get endAt => dateTime().nullable()();
  DateTimeColumn get lastExecutedAt => dateTime().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Stateful Financial Inbox item. [sourceKey] is stable across recomputation,
/// which lets a resolved signal stay quiet until its evidence changes.
@DataClassName('FinancialSignalRow')
class FinancialSignals extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get sourceKey => text()();
  TextColumn get fingerprint => text()();
  TextColumn get priority => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get evidenceJson => text().withDefault(const Constant('{}'))();
  TextColumn get route => text()();
  DateTimeColumn get firstDetectedAt => dateTime()();
  DateTimeColumn get lastDetectedAt => dateTime()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get actionId => text().nullable()();
  TextColumn get revalidationStatus => text().nullable()();
  DateTimeColumn get revalidatedAt => dateTime().nullable()();
  DateTimeColumn get actionCompletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FinancialMonthlyCloseRow')
class FinancialMonthlyCloses extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get periodMonth => text()();
  TextColumn get evidenceJson => text().withDefault(const Constant('{}'))();
  TextColumn get snapshotJson => text().withDefault(const Constant('{}'))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get overrideReason => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Account-level statement balance evidence for a monthly close.
///
/// The ledger balance is captured at verification time so a later posting
/// cannot rewrite what the user actually reviewed. A new verification simply
/// replaces the period/account/unit fact with a fresh deterministic result.
@DataClassName('FinancialReconciliationRow')
class FinancialReconciliations extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get periodMonth => text()();
  TextColumn get accountId => text()();
  TextColumn get unit => text()();
  TextColumn get statementBalance => text().map(const DecimalConverter())();
  TextColumn get ledgerBalance => text().map(const DecimalConverter())();
  TextColumn get difference => text().map(const DecimalConverter())();
  TextColumn get status => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get verifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

const List<String> financePlanningIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_dca_plans_owner_due '
      'ON dca_plans(owner_user_id, enabled, next_due_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_dca_plans_owner_hlc '
      'ON dca_plans(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_financial_decisions_owner_review '
      'ON financial_decisions(owner_user_id, status, review_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_financial_decisions_owner_hlc '
      'ON financial_decisions(owner_user_id, hlc)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_signals_owner_source '
      'ON financial_signals(owner_user_id, source_key)',
  'CREATE INDEX IF NOT EXISTS idx_financial_signals_owner_status '
      'ON financial_signals(owner_user_id, status, last_detected_at DESC) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_financial_signals_owner_hlc '
      'ON financial_signals(owner_user_id, hlc)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_monthly_closes_period '
      'ON financial_monthly_closes(owner_user_id, period_month)',
  'CREATE INDEX IF NOT EXISTS idx_financial_monthly_closes_owner_hlc '
      'ON financial_monthly_closes(owner_user_id, hlc)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_reconciliations_fact '
      'ON financial_reconciliations('
      'owner_user_id, period_month, account_id, unit)',
  'CREATE INDEX IF NOT EXISTS idx_financial_reconciliations_period '
      'ON financial_reconciliations(owner_user_id, period_month, status) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_financial_reconciliations_owner_hlc '
      'ON financial_reconciliations(owner_user_id, hlc)',
];
