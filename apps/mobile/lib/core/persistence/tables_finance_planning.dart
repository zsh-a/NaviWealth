part of 'tables.dart';

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
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FinancialMonthlyCloseRow')
class FinancialMonthlyCloses extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get periodMonth => text()();
  TextColumn get completedStepsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

const List<String> financePlanningIndexStmts = [
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
];
